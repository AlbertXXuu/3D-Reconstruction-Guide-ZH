"""Run the preserved DUSt3R demo using local weights and persistent outputs."""
import argparse
import os
from pathlib import Path
import sys
from datetime import datetime, timedelta, timezone

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT / "repos" / "dust3r"


def prepare_runtime():
    for name in ("NO_PROXY", "no_proxy"):
        entries = [value.strip() for value in os.environ.get(name, "").split(",") if value.strip()]
        for host in ("127.0.0.1", "localhost"):
            if host not in entries:
                entries.append(host)
        os.environ[name] = ",".join(entries)
    os.environ["GRADIO_ANALYTICS_ENABLED"] = "False"
    os.environ.setdefault("MPLBACKEND", "Agg")
    sys.path.insert(0, str(REPO))
    os.chdir(REPO)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=7860)
    parser.add_argument("--image-size", type=int, choices=(224, 512), default=512)
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--weights", type=Path)
    args = parser.parse_args()
    prepare_runtime()
    import torch
    from dust3r.model import AsymmetricCroCo3DStereo
    from dust3r.demo import main_demo

    suffix = "512_dpt" if args.image_size == 512 else "224_linear"
    weights = args.weights or ROOT / "checkpoints" / "dust3r" / f"DUSt3R_ViTLarge_BaseDecoder_{suffix}.pth"
    if not weights.is_file():
        raise FileNotFoundError(f"Local weights missing: {weights}")
    if args.device.startswith("cuda") and not torch.cuda.is_available():
        raise RuntimeError("CUDA unavailable. Use the configured dust3r environment.")
    torch.backends.cuda.matmul.allow_tf32 = True
    output = ROOT / "outputs" / "dust3r" / datetime.now(timezone(timedelta(hours=8))).strftime("demo-%Y%m%d-%H%M%S-%f")
    output.mkdir(parents=True)
    model = AsymmetricCroCo3DStereo.from_pretrained(str(weights)).to(args.device)
    print(f"Local weights: {weights}\nPersistent outputs: {output}", flush=True)
    main_demo(str(output), model, args.device, args.image_size, "127.0.0.1", args.port)


if __name__ == "__main__":
    main()
