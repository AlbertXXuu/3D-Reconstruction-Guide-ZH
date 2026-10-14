"""Verify real two-view DUSt3R inference and the same GLB export used by its UI."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import time

from dust3r_demo import ROOT, REPO, prepare_runtime


def main():
    prepare_runtime()
    import numpy as np
    import torch
    import trimesh
    from dust3r.model import AsymmetricCroCo3DStereo
    from dust3r.demo import get_reconstructed_scene
    from dust3r.utils.device import to_numpy

    output = ROOT / "outputs" / "dust3r" / datetime.now(timezone(timedelta(hours=8))).strftime("smoke-%Y%m%d-%H%M%S-%f")
    output.mkdir(parents=True)
    images = [REPO / "croco" / "assets" / name for name in ("Chateau1.png", "Chateau2.png")]
    weights = ROOT / "checkpoints" / "dust3r" / "DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth"
    started = time.perf_counter()
    torch.cuda.reset_peak_memory_stats()
    model = AsymmetricCroCo3DStereo.from_pretrained(str(weights)).to("cuda")
    scene, glb, _, gallery = get_reconstructed_scene(
        str(output), model, "cuda", False, 512, [str(path) for path in images],
        "cosine", 100, 3.0, True, False, True, False, 0.05, "complete", 1, 0,
    )
    poses = to_numpy(scene.get_im_poses())
    depths = to_numpy(scene.get_depthmaps())
    if not np.isfinite(poses).all() or not all(np.isfinite(depth).all() for depth in depths):
        raise RuntimeError("Non-finite scene geometry")
    exported = trimesh.load(glb, force="scene")
    vertices = sum(len(geometry.vertices) for geometry in exported.geometry.values())
    if vertices == 0 or len(gallery) != 6:
        raise RuntimeError("Incomplete reconstruction/export")
    report = {
        "model": "dust3r", "passed": True, "python": __import__("sys").executable,
        "torch": torch.__version__, "gpu": torch.cuda.get_device_name(0),
        "input_images": [str(path) for path in images], "weights": str(weights),
        "output_glb": str(glb), "output_bytes": Path(glb).stat().st_size,
        "vertices": vertices, "camera_pose_shape": list(poses.shape),
        "gallery_images": len(gallery), "peak_allocated_gib": torch.cuda.max_memory_allocated() / 2**30,
        "elapsed_seconds": time.perf_counter() - started, "completed_at": datetime.now(timezone(timedelta(hours=8))).isoformat(),
    }
    report_path = ROOT / "outputs" / "setup" / "dust3r-smoke.json"
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
