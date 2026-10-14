"""Exercise configurable CPU probes without installing or loading models."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DoctorConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="guide-doctor-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.weights = self.directory / "shared weights.bin"
        self.weights.write_bytes(b"configuration fixture, not model weights")
        self.config = self.directory / "workspace.json"
        self.model = {
            "python": sys.executable, "script": str(ROOT / "scripts/doctor.py"),
            "repository": str(self.directory), "checkpoint": str(self.weights), "port": 7899,
            "checks": {"imports": ["json"], "cuda": False},
        }

    def run_doctor(self, models, *arguments):
        self.config.write_text(json.dumps({"models": models}), encoding="utf-8")
        return subprocess.run(
            [sys.executable, "-B", str(ROOT / "scripts/doctor.py"), "--config", str(self.config), *arguments],
            capture_output=True, text=True, encoding="utf-8", timeout=60,
        )

    def test_fourth_model_cpu_probe_and_selection(self):
        broken = dict(self.model, python=str(self.directory / "missing.exe"))
        result = self.run_doctor({"future-model": self.model, "not-selected": broken}, "--model", "FUTURE-MODEL")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        report = json.loads(result.stdout)
        self.assertTrue(report["passed"])
        self.assertEqual(list(report["models"]), ["future-model"])
        runtime = report["models"]["future-model"]["runtime"]
        self.assertEqual(list(runtime["modules"]), ["json"])
        self.assertNotIn("torch", runtime)
        self.assertNotIn("cuda_available", runtime)
        self.assertTrue(report["models"]["future-model"]["pip_check_passed"])

    def test_unknown_model_lists_configuration_and_rejects(self):
        result = self.run_doctor({"future-model": self.model}, "--model", "unknown")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Configured models: future-model", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_failed_custom_import_is_a_failed_report(self):
        model = dict(self.model, checks={"imports": ["missing_guide_fixture_module"], "cuda": False})
        result = self.run_doctor({"future-model": model})
        self.assertEqual(result.returncode, 1)
        item = json.loads(result.stdout)["models"]["future-model"]
        self.assertFalse(item["passed"])
        self.assertIn("missing_guide_fixture_module", item["import_error"])

    def test_invalid_import_configuration_rejected(self):
        model = dict(self.model, checks={"imports": "json", "cuda": False})
        result = self.run_doctor({"future-model": model})
        self.assertEqual(result.returncode, 2)
        self.assertIn("checks.imports", result.stderr)

    def test_missing_required_path_has_clear_error(self):
        model = dict(self.model)
        del model["checkpoint"]
        result = self.run_doctor({"future-model": model})
        self.assertEqual(result.returncode, 2)
        self.assertIn("checkpoint", result.stderr)


if __name__ == "__main__":
    unittest.main()
