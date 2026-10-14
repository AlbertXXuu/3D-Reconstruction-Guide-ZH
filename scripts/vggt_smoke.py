"""Run the official kitchen two-view VGGT smoke test and validate its GLB."""
import json
from pathlib import Path

import numpy as np
import trimesh

from vggt_demo import REPO, ROOT, reconstruct

images = [str(REPO / "examples" / "kitchen" / "images" / name) for name in ("00.png", "01.png")]
glb, message, npz, _ = reconstruct(images, 294, 50, True)
scene = trimesh.load(glb, force="scene")
vertices = sum(len(item.vertices) for item in scene.geometry.values())
if vertices == 0:
    raise RuntimeError("Exported GLB contains no vertices")
with np.load(npz, allow_pickle=False) as predictions:
    shapes = {key: list(predictions[key].shape) for key in predictions.files}
    assert predictions["extrinsic"].shape == (2, 3, 4)
    assert predictions["intrinsic"].shape == (2, 3, 3)
    assert all(np.isfinite(predictions[key]).all() for key in predictions.files)
metrics = json.loads(Path(glb).with_name("metrics.json").read_text(encoding="utf-8"))
metrics.update({"success": True, "glb_reloaded": True, "glb_vertices": vertices, "prediction_shapes": shapes})
status = ROOT / "outputs" / "setup" / "vggt-smoke.json"
status.write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")
print(message)
print(json.dumps(metrics, ensure_ascii=False, indent=2))
