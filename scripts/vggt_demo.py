"""Local VGGT demo using the official camera/depth heads and GLB exporter."""

from __future__ import annotations

import argparse
import gc
import json
import os
from pathlib import Path
import shutil
import sys
import threading
import time
import uuid

for stream in (sys.stdout, sys.stderr):
    if stream is not None and hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT / "repos" / "vggt"
CHECKPOINT = ROOT / "checkpoints" / "vggt" / "model.pt"
OUTPUTS = ROOT / "outputs" / "vggt"

os.environ.setdefault("GRADIO_ANALYTICS_ENABLED", "False")
os.environ.setdefault("HF_HUB_OFFLINE", "1")
for variable in ("NO_PROXY", "no_proxy"):
    existing = os.environ.get(variable, "")
    os.environ[variable] = ",".join(filter(None, (existing, "127.0.0.1", "localhost", "::1")))
os.environ.setdefault("GRADIO_TEMP_DIR", str(OUTPUTS / "gradio_cache"))
sys.path.insert(0, str(REPO))

import gradio as gr
import numpy as np
import torch
import torch.nn.functional as F

from vggt.models.vggt import VGGT
from vggt.utils.geometry import unproject_depth_map_to_point_map
from vggt.utils.load_fn import load_and_preprocess_images
from vggt.utils.pose_enc import pose_encoding_to_extri_intri
from visual_util import predictions_to_glb

_model = None
_lock = threading.Lock()


def get_model():
    """Load local weights only; unused point regression/tracking heads stay absent."""
    global _model
    if _model is None:
        if not CHECKPOINT.is_file():
            raise FileNotFoundError(f"VGGT checkpoint is missing: {CHECKPOINT}")
        model = VGGT(enable_point=False, enable_track=False).eval()
        state = torch.load(CHECKPOINT, map_location="cpu", weights_only=True, mmap=True)
        state = {name: value for name, value in state.items()
                 if not name.startswith(("point_head.", "track_head."))}
        model.load_state_dict(state, strict=True, assign=True)
        del state
        # Keep the transformer compact; official prediction heads run in float32.
        model.aggregator.to(dtype=torch.bfloat16)
        _model = model
        gc.collect()
    return _model


def _predict(images, model):
    images = images.unsqueeze(0).to("cuda")
    with torch.inference_mode():
        with torch.autocast("cuda", dtype=torch.bfloat16):
            tokens, patch_start = model.aggregator(images)
        # The official model also disables autocast for the prediction heads.
        tokens = [item.float() if item is not None else None for item in tokens]
        pose = model.camera_head(tokens)[-1]
        depth, confidence = model.depth_head(tokens, images, patch_start, frames_chunk_size=1)
        extrinsic, intrinsic = pose_encoding_to_extri_intri(pose, images.shape[-2:])
        values = {
            "pose_enc": pose, "depth": depth, "depth_conf": confidence,
            "extrinsic": extrinsic, "intrinsic": intrinsic, "images": images,
        }
        return {name: value.float().cpu().numpy().squeeze(0) for name, value in values.items()}


def reconstruct(image_paths, resolution=294, confidence=50.0, show_cameras=True):
    """Run real CUDA inference and preserve source copies, NPZ, GLB and metrics."""
    if not image_paths or not 1 <= len(image_paths) <= 4:
        raise ValueError("Select 1–4 photographs of the same scene (start with two views).")
    resolution = int(resolution)
    if resolution not in (294, 392, 518):
        raise ValueError("Resolution must be 294, 392 or 518.")
    if not 0 <= float(confidence) <= 100:
        raise ValueError("Confidence percentile must be between 0 and 100.")
    if not torch.cuda.is_available() or not torch.cuda.is_bf16_supported():
        raise RuntimeError("This local low-memory demo requires a CUDA GPU with bfloat16 support.")
    with _lock:
        start = time.perf_counter()
        job = OUTPUTS / (time.strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:8])
        (job / "images").mkdir(parents=True)
        copies = []
        for index, source in enumerate(image_paths):
            source = Path(source)
            if not source.is_file():
                raise FileNotFoundError(str(source))
            destination = job / "images" / f"{index:03d}_{source.name}"
            shutil.copy2(source, destination)
            copies.append(str(destination))
        images = load_and_preprocess_images(copies, mode="crop")
        if resolution != 518:
            h = max(14, round(images.shape[-2] * resolution / images.shape[-1] / 14) * 14)
            images = F.interpolate(images, size=(h, resolution), mode="bicubic", align_corners=False).clamp(0, 1)
        model = get_model()
        torch.cuda.reset_peak_memory_stats()
        try:
            model.to("cuda")
            predictions = _predict(images, model)
            torch.cuda.synchronize()
            peak = torch.cuda.max_memory_allocated()
        finally:
            # Release GPU weights between requests so the other local demos can run.
            model.cpu()
            gc.collect()
            torch.cuda.empty_cache()
        predictions["world_points_from_depth"] = unproject_depth_map_to_point_map(
            predictions["depth"], predictions["extrinsic"], predictions["intrinsic"]
        )
        for key, values in predictions.items():
            if not np.isfinite(values).all():
                raise RuntimeError(f"VGGT produced non-finite {key} values.")
        np.savez_compressed(job / "predictions.npz", **predictions)
        scene = predictions_to_glb(
            predictions, conf_thres=float(confidence), show_cam=bool(show_cameras),
            mask_sky=False, target_dir=str(job), prediction_mode="Depthmap and Camera Branch"
        )
        result = job / "scene.glb"
        scene.export(str(result))
        vertices = sum(len(geometry.vertices) for geometry in scene.geometry.values())
        if vertices == 0:
            raise RuntimeError("The exported scene is empty; lower the confidence percentile.")
        metrics = {
            "model": "facebook/VGGT-1B", "checkpoint": str(CHECKPOINT),
            "images": copies, "input_shape": list(images.shape), "resolution": resolution,
            "heads": ["camera", "depth"], "transformer_dtype": "bfloat16", "heads_dtype": "float32",
            "camera_convention": "OpenCV camera_from_world", "metric_scale_known": False,
            "confidence_percentile": float(confidence), "scene_vertices": vertices,
            "cuda_peak_allocated_bytes": peak, "elapsed_seconds": round(time.perf_counter() - start, 3),
            "output_glb": str(result), "output_npz": str(job / "predictions.npz"),
        }
        (job / "metrics.json").write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")
        message = (f"完成：{len(copies)} 张图，{images.shape[-1]}×{images.shape[-2]} 输入；"
                   f"{vertices:,} 个场景顶点；峰值显存 {peak / 1024**3:.2f} GiB；"
                   f"用时 {metrics['elapsed_seconds']:.1f} 秒。输出：{job.relative_to(ROOT).as_posix()}")
        return str(result), message, str(job / "predictions.npz"), copies


def build_demo():
    OUTPUTS.mkdir(parents=True, exist_ok=True)
    with gr.Blocks(title="VGGT 本地三维重建", analytics_enabled=False) as demo:
        gr.Markdown("# VGGT 本地三维重建\n上传同一场景的 1–4 张有重叠的照片。RTX 4060 8GB 建议先用两张、294 分辨率。\n"
                    "结果保存为 GLB（交互查看）和 NPZ（深度、置信度、相机、点云）。模型估计的尺度没有物理单位。")
        with gr.Row():
            with gr.Column():
                uploads = gr.File(label="场景照片", file_count="multiple", type="filepath", file_types=["image"])
                resolution = gr.Dropdown([294, 392, 518], value=294, label="输入宽度（294 已适配本机显存）")
                confidence = gr.Slider(0, 100, value=50, label="过滤最低置信度点的百分比")
                cameras = gr.Checkbox(True, label="显示相机位置")
                submit = gr.Button("开始重建", variant="primary")
                status = gr.Textbox(label="运行结果", lines=4)
                predictions = gr.File(label="下载预测数据 NPZ")
                gallery = gr.Gallery(label="输入预览", columns=2, height=260)
            with gr.Column():
                viewer = gr.Model3D(label="3D 点云（可旋转和下载 GLB）", height=620)
        example_images = [str(REPO / "examples" / "kitchen" / "images" / name) for name in ("00.png", "01.png")]
        gr.Examples(examples=[[example_images]], inputs=[uploads], label="官方 kitchen 双视图样例", cache_examples=False)
        submit.click(reconstruct, [uploads, resolution, confidence, cameras],
                     [viewer, status, predictions, gallery], api_name="reconstruct", concurrency_limit=1)
    return demo


def main():
    global CHECKPOINT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1", choices=["127.0.0.1", "localhost"])
    parser.add_argument("--port", type=int, default=7862)
    parser.add_argument("--weights", type=Path, default=CHECKPOINT, help="Local official model.pt checkpoint")
    args = parser.parse_args()
    CHECKPOINT = args.weights.expanduser().resolve()
    build_demo().queue(max_size=4, default_concurrency_limit=1).launch(
        server_name=args.host, server_port=args.port, share=False, show_error=True,
        allowed_paths=[str(OUTPUTS), str(REPO / "examples")],
    )


if __name__ == "__main__":
    main()
