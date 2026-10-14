"""Reconstruct two official Chateau images with the same function as the demo."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import time

from mast3r_demo import PROJECT_ROOT, REPO_ROOT, DEFAULT_WEIGHTS, configure_runtime


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", choices=("cuda", "cpu"), default="cuda")
    parser.add_argument("--weights", type=Path, default=DEFAULT_WEIGHTS)
    parser.add_argument("--image-size", type=int, choices=(224, 512), default=512)
    parser.add_argument("--coarse-iterations", type=int, default=30)
    parser.add_argument("--fine-iterations", type=int, default=20)
    parser.add_argument("--output-dir", type=Path, default=PROJECT_ROOT / "outputs" / "mast3r" / "smoke")
    args = parser.parse_args()
    configure_runtime(args.output_dir)

    import numpy as np
    import torch
    import trimesh
    from mast3r.demo import get_reconstructed_scene
    from mast3r.model import AsymmetricMASt3R

    if args.device == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA is unavailable.")
    images = [REPO_ROOT / "dust3r" / "croco" / "assets" / f"Chateau{i}.png" for i in (1, 2)]
    for path in (args.weights, *images):
        if not path.is_file():
            raise FileNotFoundError(path)
    torch.set_num_threads(min(8, os.cpu_count() or 1))
    torch.backends.cuda.matmul.allow_tf32 = True
    start = time.perf_counter()
    model = AsymmetricMASt3R.from_pretrained(str(args.weights)).eval().to(args.device)
    state, glb = get_reconstructed_scene(
        str(args.output_dir), False, model, None, args.device, False, args.image_size,
        None, [str(path) for path in images], "refine+depth", 0.07, args.coarse_iterations,
        0.01, args.fine_iterations, 1.5, 0.0, True, False, True, False, 0.05,
        "complete", 1, False, 0, 0.0, False,
    )
    final_glb = args.output_dir / "chateau_scene.glb"
    shutil.copy2(glb, final_glb)
    state.outfile_name = str(final_glb)
    scene = trimesh.load(str(final_glb), force="scene")
    vertex_count = sum(len(geometry.vertices) for geometry in scene.geometry.values())
    if not scene.geometry or vertex_count == 0:
        raise RuntimeError("Exported GLB contains no geometry.")
    poses = state.sparse_ga.get_im_poses().detach().cpu().numpy()
    intrinsics = state.sparse_ga.intrinsics.detach().cpu().numpy()
    if poses.shape != (2, 4, 4) or not np.isfinite(poses).all() or not np.isfinite(intrinsics).all():
        raise RuntimeError("Camera outputs are invalid.")
    np.savez_compressed(args.output_dir / "cameras.npz", cam2world=poses, intrinsics=intrinsics)
    report = {
        "passed": True,
        "python": sys.executable,
        "device": args.device,
        "image_size": args.image_size,
        "coarse_iterations": args.coarse_iterations,
        "fine_iterations": args.fine_iterations,
        "input_images": [str(path) for path in images],
        "seconds": round(time.perf_counter() - start, 3),
        "glb": str(final_glb),
        "glb_bytes": final_glb.stat().st_size,
        "glb_sha256": hashlib.sha256(final_glb.read_bytes()).hexdigest(),
        "geometry_count": len(scene.geometry),
        "vertex_count": vertex_count,
        "camera_count": int(poses.shape[0]),
        "peak_cuda_allocated_bytes": torch.cuda.max_memory_allocated() if args.device == "cuda" else None,
    }
    (args.output_dir / "smoke-result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
