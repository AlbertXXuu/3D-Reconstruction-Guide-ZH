"""Check the configured local demo runtimes and assets without loading models."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IMPORTS = ["torch", "numpy", "PIL", "gradio", "trimesh", "requests"]
PROBE = '''import importlib, json, sys
modules = {name: importlib.import_module(name) for name in json.loads(sys.argv[1])}
runtime = {"python": sys.executable, "base_prefix": sys.base_prefix,
 "modules": {name: {"version": str(getattr(module, "__version__", "unknown")),
 "file": str(getattr(module, "__file__", "built-in"))} for name, module in modules.items()}}
for name, key in (("numpy", "numpy"), ("PIL", "pillow"), ("gradio", "gradio"), ("requests", "requests")):
 if name in modules: runtime[key] = runtime["modules"][name]["version"]
if "torch" in modules:
 torch = modules["torch"]
 runtime.update(torch=torch.__version__, torch_cuda=torch.version.cuda,
  cuda_available=torch.cuda.is_available(),
  bf16_supported=torch.cuda.is_available() and torch.cuda.is_bf16_supported())
print(json.dumps(runtime))'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--config", type=Path, default=ROOT / "workspace.json")
    parser.add_argument("--model", action="append", help="Check only this configured model; repeat for several models")
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text(encoding="utf-8-sig"))
        models = config["models"]
        if not isinstance(models, dict) or not models:
            raise ValueError("models must be a non-empty object")
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(f"Cannot read model configuration: {error}")
    selected = list(dict.fromkeys(name.lower() for name in args.model)) if args.model else list(models)
    unknown = [name for name in selected if name not in models]
    if unknown:
        parser.error(f"Unknown model: {', '.join(unknown)}. Configured models: {', '.join(models)}")
    environment = dict(os.environ, PYTHONUTF8="1")
    report = {"workspace": str(ROOT), "passed": True, "models": {}}
    for name in selected:
        settings = models[name]
        if not isinstance(settings, dict) or not all(
            isinstance(settings.get(key), str) and settings[key].strip()
            for key in ("python", "script", "repository", "checkpoint")
        ):
            parser.error(f"{name}: python, script, repository and checkpoint must be non-empty paths")
        if type(settings.get("port")) is not int or not 1 <= settings["port"] <= 65535:
            parser.error(f"{name}: port must be an integer from 1 to 65535")
        checks = settings.get("checks", {})
        imports = checks.get("imports", DEFAULT_IMPORTS) if isinstance(checks, dict) else None
        if not isinstance(imports, list) or not imports or not all(
            isinstance(module, str) and re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*", module) for module in imports
        ):
            parser.error(f"{name}: checks.imports must be a non-empty list of Python module names")
        require_cuda = checks.get("cuda", True)
        require_bf16 = checks.get("bf16", False)
        if not isinstance(require_cuda, bool) or not isinstance(require_bf16, bool):
            parser.error(f"{name}: checks.cuda and checks.bf16 must be booleans")
        imports = list(dict.fromkeys(imports + (["torch"] if require_cuda or require_bf16 else [])))
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
                probe = subprocess.run([str(python), "-B", "-c", PROBE, json.dumps(imports)], env=environment, capture_output=True,
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
        item["checks"] = {"imports": imports, "cuda": require_cuda, "bf16": require_bf16}
        if require_cuda:
            item["passed"] = item["passed"] and item.get("runtime", {}).get("cuda_available", False)
        if require_bf16:
            item["passed"] = item["passed"] and item.get("runtime", {}).get("bf16_supported", False)
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
