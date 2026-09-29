"""Launcher diuji tanpa unduhan atau pembukaan jendela sungguhan."""
from __future__ import annotations
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import launcher


class LauncherTest(unittest.TestCase):
    def test_import_probe_rejects_broken_import_despite_metadata(self):
        with patch.object(launcher, "_probe", return_value=subprocess.CompletedProcess([], 1)) as probe:
            self.assertFalse(launcher._flet_ready(Path("python")))
            self.assertIn("import flet as ft, flet_desktop", probe.call_args.args[1])

    def test_import_probe_accepts_matching_desktop(self):
        with patch.object(launcher, "_probe", return_value=subprocess.CompletedProcess([], 0)):
            self.assertTrue(launcher._flet_ready(Path("python")))

    def test_healthy_environment_does_not_reinstall(self):
        with patch.object(launcher, "_base_candidates", return_value=[]), \
             patch.object(launcher, "_python_healthy", return_value=True), \
             patch.object(launcher, "_flet_ready", return_value=True), \
             patch.object(launcher, "_install_dependencies") as install:
            self.assertEqual(launcher._venv_python(), launcher._ensure_environment())
            install.assert_not_called()

    def test_broken_venv_is_quarantined_and_rebuilt(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            venv = root / ".venv"
            venv.mkdir()
            (venv / "broken.txt").write_text("keep")
            with patch.object(launcher, "ROOT", root), patch.object(launcher, "VENV_DIR", venv), \
                 patch.object(launcher, "_base_candidates", return_value=[Path("/base/python")]), \
                 patch.object(launcher, "_python_healthy", side_effect=[False, True]), \
                 patch.object(launcher, "_create_venv", return_value=Path("/new/python")) as create, \
                 patch.object(launcher, "_install_dependencies"):
                self.assertEqual(Path("/new/python"), launcher._ensure_environment())
                create.assert_called_once()
                self.assertEqual(1, len(list(root.glob(".venv-rusak-*"))))

    def test_pip_repair_when_python_file_exists(self):
        with tempfile.TemporaryDirectory() as folder:
            python = Path(folder) / "python.exe"
            python.touch()
            with patch.object(launcher, "_venv_python", return_value=python), \
                 patch.object(launcher, "_base_candidates", return_value=[]), \
                 patch.object(launcher, "_python_healthy", side_effect=[False, True]), \
                 patch.object(launcher, "_flet_ready", return_value=True), \
                 patch.object(launcher, "_run") as run:
                self.assertEqual(python, launcher._ensure_environment())
                self.assertIn("ensurepip", run.call_args.args[0])

    def test_probe_timeout_means_unhealthy(self):
        with patch.object(launcher.subprocess, "run", side_effect=subprocess.TimeoutExpired("python", 30)):
            self.assertIsNone(launcher._probe(Path("python"), "import flet"))

    def test_child_nonzero_exit_preserved(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(launcher, "ROOT", Path(folder)), \
             patch.object(launcher.subprocess, "run", return_value=subprocess.CompletedProcess([], 7)):
            self.assertEqual(7, launcher._run_app(Path("python")))

    def test_child_zero_without_window_is_failure(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(launcher, "ROOT", Path(folder)), \
             patch.object(launcher.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)):
            self.assertEqual(1, launcher._run_app(Path("python")))

    def test_child_ready_and_normal_close_is_success(self):
        def run(*args, **kwargs):
            Path(kwargs["env"]["QPARK_STARTUP_MARKER"]).write_text('{"ready": true}')
            return subprocess.CompletedProcess([], 0)
        with tempfile.TemporaryDirectory() as folder, patch.object(launcher, "ROOT", Path(folder)), \
             patch.object(launcher.subprocess, "run", side_effect=run):
            self.assertEqual(0, launcher._run_app(Path("python")))

    def test_paths_do_not_depend_on_working_directory(self):
        self.assertTrue(launcher.ROOT.is_absolute())
        self.assertEqual(str(launcher.ROOT), launcher._env()["PYTHONPATH"])

    def test_check_mode_returns_without_opening_app(self):
        with patch.object(launcher, "_ensure_environment", return_value=Path("python")), \
             patch.object(launcher, "_run_app") as run:
            self.assertEqual(0, launcher.main(["--check", "--no-pause"]))
            run.assert_not_called()

    def test_locked_running_venv_uses_separate_recovery_environment(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            venv = root / '.venv'
            venv.mkdir()
            python = venv / 'Scripts/python.exe'
            python.parent.mkdir()
            python.touch()
            with patch.object(launcher, 'ROOT', root), patch.object(launcher, 'VENV_DIR', venv), \
                 patch.object(launcher.sys, 'executable', str(python)), \
                 patch.object(launcher, '_venv_python', return_value=python), \
                 patch.object(launcher, '_base_candidates', return_value=[Path('/base/python')]), \
                 patch.object(launcher, '_python_healthy', side_effect=[False, False, True, True]), \
                 patch.object(launcher, '_run'), patch.object(launcher, '_install_dependencies'):
                result = launcher._ensure_environment()
                self.assertIn('.venv-qpark', str(result))
                self.assertTrue(python.exists())
