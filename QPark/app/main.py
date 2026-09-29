"""Titik masuk desktop, konfigurasi, dan log lokal."""
from __future__ import annotations

import json
import logging
import os
from logging.handlers import RotatingFileHandler
from pathlib import Path

import flet as ft
from app.bootstrap import create_repository
from app.config import ROOT, load_config
from app.ui.app_controller import ParkingApp
from app.ui.common import BACKGROUND, DANGER, MUTED, PRIMARY, status_box


def configure_logging() -> None:
    """Simpan rincian teknis terpisah dari pesan antarmuka."""
    folder = ROOT / "logs"
    folder.mkdir(exist_ok=True)
    handler = RotatingFileHandler(folder / "qpark.log", maxBytes=1_000_000, backupCount=2, encoding="utf-8")
    logging.basicConfig(level=logging.INFO, handlers=[handler, logging.StreamHandler()],
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")


def mark_startup(ready: bool) -> None:
    marker = os.environ.get("QPARK_STARTUP_MARKER")
    if marker:
        Path(marker).write_text(json.dumps({"ready": ready}), encoding="utf-8")


async def main(page: ft.Page) -> None:
    """Tampilkan kesalahan konfigurasi/database tanpa menutup jendela mendadak."""
    page.title = "QPark — Pengelolaan Parkir"
    page.theme_mode = ft.ThemeMode.LIGHT
    page.theme = ft.Theme(color_scheme_seed=PRIMARY, font_family="Segoe UI")
    page.bgcolor = BACKGROUND
    page.window.width, page.window.height = 1366, 768
    page.window.min_width, page.window.min_height = 1024, 650
    page.add(ft.Text("Menyiapkan QPark...", color=MUTED), ft.ProgressRing(color=PRIMARY))
    try:
        repository = create_repository(load_config())
        application = ParkingApp(page, repository)
        await application.start()
        mark_startup(True)
    except Exception:
        logging.getLogger(__name__).exception("Penyiapan aplikasi gagal")
        mark_startup(False)
        page.clean()
        page.add(ft.Text("QPark belum siap", size=26, color=DANGER),
                 status_box("Database atau konfigurasi tidak dapat dibuka. Periksa .env, izin folder "
                            "data, serta logs/qpark.log. Tutup jendela lalu jalankan kembali.", False))


def run() -> None:
    configure_logging()
    ft.run(main, view=ft.AppView.FLET_APP)


if __name__ == "__main__":
    run()
