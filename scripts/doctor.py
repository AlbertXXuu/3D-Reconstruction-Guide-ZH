"""Check the configured local demo runtimes and assets without loading models."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROBE = '''import json, sys, torch, numpy, PIL, gradio, trimesh, requests
print(json.dumps({"python": sys.executable, "base_prefix": sys.base_prefix,
 "torch": torch.__version__, "torch_cuda": torch.version.cuda,
 "cuda_available": torch.cuda.is_available(), "numpy": numpy.__version__,
 "pillow": PIL.__version__, "gradio": gradio.__version__, "requests": requests.__version__}))'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    config = json.loads((ROOT / "workspace.json").read_text(encoding="utf-8"))
    environment = dict(os.environ, PYTHONUTF8="1")
    report = {"workspace": str(ROOT), "passed": True, "models": {}}
    for name, settings in config["models"].items():
        python = Path(settings["python"])
        if not python.is_absolute():
            python = ROOT / python
        checkpoint = ROOT / settings["checkpoint"]
        item = {"python_exists": python.is_file(), "script_exists": (ROOT / settings["script"]).is_file(),
                "repo_exists": (ROOT / settings["repository"]).is_dir(), "checkpoint_exists": checkpoint.is_file(),
                "checkpoint_bytes": checkpoint.stat().st_size if checkpoint.is_file() else 0,
                "url": f"http://127.0.0.1:{settings['port']}/"}
        if python.is_file():
            try:
                probe = subprocess.run([str(python), "-B", "-c", PROBE], env=environment, capture_output=True,
                                       text=True, encoding="utf-8", errors="replace", timeout=60)
                item["import_passed"] = probe.returncode == 0
                if probe.returncode == 0:
                    item["runtime"] = json.loads(probe.stdout.strip().splitlines()[-1])
                else:
                    item["import_error"] = probe.stderr[-2500:]
                check = subprocess.run([str(python), "-m", "pip", "check"], env=environment, capture_output=True,
                                       text=True, encoding="utf-8", errors="replace", timeout=60)
                item["pip_check_passed"] = check.returncode == 0
                item["pip_check"] = (check.stdout + check.stderr).strip()
            except (OSError, subprocess.TimeoutExpired, ValueError) as error:
                item["error"] = str(error)
        item["passed"] = all(item.get(key, False) for key in
                             ("python_exists", "script_exists", "repo_exists", "checkpoint_exists", "import_passed", "pip_check_passed"))
        item["passed"] = item["passed"] and item.get("runtime", {}).get("cuda_available", False)
        report["models"][name] = item
        report["passed"] = report["passed"] and item["passed"]
    serialized = json.dumps(report, indent=2, ensure_ascii=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(serialized, encoding="utf-8")
    print(serialized)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
