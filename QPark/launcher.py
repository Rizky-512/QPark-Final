"""Siapkan lingkungan desktop dan jalankan QPark tanpa aktivasi manual."""
from __future__ import annotations

import argparse
import json
import os
import platform
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VENV_DIR = ROOT / ".venv"
REQUIREMENTS = ROOT / "requirements.txt"
FLET_VERSION = "1.0.2"


def _env() -> dict[str, str]:
    """Gunakan proyek ini sebagai sumber impor, bukan PYTHONPATH dari editor."""
    env = os.environ.copy()
    env.pop("PYTHONHOME", None)
    env["PYTHONPATH"] = str(ROOT)
    env["PYTHONUTF8"] = "1"
    env["PYTHONUNBUFFERED"] = "1"
    return env


def _probe(python: Path, code: str) -> subprocess.CompletedProcess[str] | None:
    """Cek interpreter dengan batas waktu; executable rusak tidak dipercaya."""
    try:
        return subprocess.run([str(python), "-c", code], cwd=ROOT, env=_env(),
                              capture_output=True, text=True, encoding="utf-8",
                              errors="replace", timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None


def _python_healthy(python: Path, pip: bool = True) -> bool:
    code = "import sys, sqlite3, ssl, venv; assert sys.version_info >= (3,10)"
    if pip:
        code += "; import pip"
    result = _probe(python, code)
    return result is not None and result.returncode == 0


def _flet_ready(python: Path) -> bool:
    """Uji impor sungguhan, API desktop, serta versi paket yang telah diuji."""
    result = _probe(python, (
        "import flet as ft, flet_desktop; from importlib.metadata import version; "
        f"assert version('flet') == version('flet-desktop') == '{FLET_VERSION}'; "
        "assert callable(ft.run); ft.Text('QPark'); ft.Button('Masuk')"
    ))
    return result is not None and result.returncode == 0


def _run(command: list[str], timeout: int | None = None) -> None:
    subprocess.run(command, cwd=ROOT, env=_env(), check=True, timeout=timeout)


def _venv_python() -> Path:
    return VENV_DIR / ("Scripts/python.exe" if os.name == "nt" else "bin/python")


def _base_candidates() -> list[Path]:
    """Prioritaskan Python dasar; py membantu ketika VS Code memakai venv rusak."""
    candidates = [Path(getattr(sys, "_base_executable", sys.executable)), Path(sys.executable)]
    if os.name == "nt":
        for version in ("-3.12", "-3.11", "-3.13", "-3.14", "-3.10", "-3"):
            try:
                result = subprocess.run(["py", version, "-c", "import sys; print(sys.executable)"],
                                        capture_output=True, text=True, timeout=15)
                if result.returncode == 0 and result.stdout.strip():
                    candidates.append(Path(result.stdout.strip()))
            except (OSError, subprocess.TimeoutExpired):
                break
    return list(dict.fromkeys(candidates))


def _quarantine_venv() -> None:
    """Pertahankan venv lama sebagai cadangan; jangan sentuh data aplikasi."""
    if VENV_DIR.exists():
        backup = ROOT / f".venv-rusak-{time.time_ns()}"
        VENV_DIR.rename(backup)
        print(f"Lingkungan lama dipindahkan ke {backup.name}.", flush=True)


def _create_venv(base: Path) -> Path:
    print(f"Membuat .venv dengan {base} ...", flush=True)
    _run([str(base), "-m", "venv", str(VENV_DIR)], timeout=180)
    python = _venv_python()
    if not _python_healthy(python):
        raise RuntimeError("Python atau pip di .venv tidak dapat dijalankan.")
    return python


def _install_dependencies(python: Path, repair: bool = False) -> None:
    """Pasang paket desktop saja; tidak memperbarui pip setiap peluncuran."""
    print("Menyiapkan Flet desktop. Instalasi pertama memerlukan internet...", flush=True)
    command = [str(python), "-m", "pip", "install", "--disable-pip-version-check",
               "--timeout", "30", "--retries", "2", "--only-binary=:all:"]
    if repair:
        command.append("--force-reinstall")
    _run(command + ["-r", str(REQUIREMENTS)], timeout=600)
    if not _flet_ready(python):
        if not repair:
            _install_dependencies(python, repair=True)
        else:
            raise RuntimeError("Paket terpasang, tetapi import Flet desktop masih gagal.")


def _ensure_environment() -> Path:
    """Pulihkan pip/venv rusak dan coba interpreter kompatibel yang tersedia."""
    python = _venv_python()
    bases = _base_candidates()
    recovery_dir = ROOT / ".venv-qpark"
    recovery_python = recovery_dir / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if recovery_python.exists() and _python_healthy(recovery_python) and _flet_ready(recovery_python):
        print("Menggunakan lingkungan pemulihan .venv-qpark.", flush=True)
        return recovery_python
    if _python_healthy(python):
        try:
            if not _flet_ready(python):
                _install_dependencies(python)
            return python
        except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
            print(f"Lingkungan lama belum siap: {exc}", flush=True)
    elif python.exists():
        print(".venv ditemukan tetapi tidak sehat; mencoba pemulihan pip.", flush=True)
        try:
            _run([str(python), "-m", "ensurepip", "--upgrade"], timeout=120)
            if _python_healthy(python):
                if not _flet_ready(python):
                    _install_dependencies(python)
                return python
        except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
            print(f"Pemulihan pip gagal: {exc}", flush=True)
    # Jangan memindahkan interpreter yang sedang menjalankan launcher di Windows.
    running_inside = Path(sys.executable).is_relative_to(VENV_DIR)
    try:
        if running_inside and VENV_DIR.exists():
            # Executable yang sedang dipakai tidak dapat dipindah di Windows.
            # Buat lingkungan baru terpisah dengan Python dasarnya.
            for base in bases:
                if base.is_relative_to(VENV_DIR) or not _python_healthy(base, pip=False):
                    continue
                try:
                    print(".venv sedang dipakai VS Code; membangun .venv-qpark pengganti.", flush=True)
                    _run([str(base), "-m", "venv", str(recovery_dir)], timeout=180)
                    if not _python_healthy(recovery_python):
                        raise RuntimeError("Lingkungan pemulihan tidak sehat.")
                    _install_dependencies(recovery_python)
                    return recovery_python
                except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
                    print(f"Pemulihan melalui {base} gagal: {exc}", flush=True)
            raise RuntimeError("Lingkungan yang dipakai editor belum dapat dipulihkan.")
        _quarantine_venv()
        for base in bases:
            if base.is_relative_to(VENV_DIR) or not _python_healthy(base, pip=False):
                continue
            try:
                python = _create_venv(base)
                _install_dependencies(python)
                return python
            except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
                print(f"Penyiapan dengan {base} gagal: {exc}", flush=True)
                _quarantine_venv()
    except (OSError, RuntimeError) as exc:
        print(f"Pembuatan ulang .venv tidak berhasil: {exc}", flush=True)
    # Tidak mengubah paket global secara otomatis. Hanya pakai cadangan yang siap.
    for base in bases:
        if _python_healthy(base) and _flet_ready(base):
            print(f"Menggunakan interpreter cadangan yang siap: {base}", flush=True)
            return base
    raise RuntimeError(
        "Lingkungan desktop belum tersedia. Periksa internet/proxy dan log pip di atas. "
        "Gunakan Python 3.10+ 64-bit (3.12 dianjurkan) dari python.org; "
        "bila tidak ada wheel untuk versi Anda, pilih interpreter 3.12 di VS Code."
    )


def _run_app(python: Path) -> int:
    """Teruskan keluaran dan exit code; deteksi client yang gagal membuka sesi."""
    marker = ROOT / "logs" / f"startup-{os.getpid()}.json"
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.unlink(missing_ok=True)
    env = _env()
    env["QPARK_STARTUP_MARKER"] = str(marker)
    print("Membuka QPark. Client desktop mungkin perlu diunduh pada peluncuran pertama.", flush=True)
    try:
        result = subprocess.run([str(python), "-u", str(ROOT / "main.py")], cwd=ROOT, env=env)
        if result.returncode:
            return result.returncode
        if not marker.exists():
            print("Client desktop berhenti sebelum halaman siap. Periksa koneksi unduhan, "
                  "antivirus, dan logs/qpark.log.", flush=True)
            return 1
        state = json.loads(marker.read_text(encoding="utf-8"))
        return 0 if state.get("ready") else 1
    finally:
        marker.unlink(missing_ok=True)


def _pause_on_error(code: int, no_pause: bool) -> None:
    if code and not no_pause and os.name == "nt":
        try:
            input("\nTekan Enter untuk menutup. Salin pesan error di atas bila perlu...")
        except (EOFError, OSError):
            pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Launcher desktop QPark")
    parser.add_argument("--no-pause", action="store_true", help="Untuk pemanggilan dari run.bat/otomasi")
    parser.add_argument("--check", action="store_true", help="Siapkan dan periksa dependensi tanpa membuka UI")
    args = parser.parse_args(argv)
    print(f"=== QPark Launcher ===\nFolder: {ROOT}\nPython: {sys.version.split()[0]} ({platform.machine()})", flush=True)
    code = 1
    try:
        if sys.version_info < (3, 10):
            raise RuntimeError("Python 3.10 atau lebih baru diperlukan.")
        if os.name == "nt" and sys.maxsize <= 2**32:
            raise RuntimeError("Client Flet Windows memerlukan Python 64-bit.")
        if not REQUIREMENTS.is_file() or not (ROOT / "main.py").is_file():
            raise RuntimeError("Ekstrak ZIP sepenuhnya; requirements.txt/main.py tidak ditemukan.")
        python = _ensure_environment()
        print("Dependensi desktop siap.", flush=True)
        code = 0 if args.check else _run_app(python)
    except KeyboardInterrupt:
        print("\nDihentikan oleh pengguna.")
        code = 130
    except Exception as exc:
        print(f"\nQPark belum dapat dibuka: {exc}", flush=True)
        code = 1
    _pause_on_error(code, args.no_pause)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
