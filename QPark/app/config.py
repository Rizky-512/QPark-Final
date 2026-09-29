"""Konfigurasi lokal tanpa dependensi dotenv; environment mengalahkan .env."""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class AppConfig:
    backend: str = "sqlite"
    database_path: Path = ROOT / "data" / "qpark.db"


def load_config(root: Path = ROOT) -> AppConfig:
    """Baca pasangan KEY=VALUE sederhana, tanpa menjalankan ekspansi shell."""
    values: dict[str, str] = {}
    env_file = root / ".env"
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8-sig").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip('"\'')
    backend = os.environ.get("DB_BACKEND", values.get("DB_BACKEND", "sqlite")).strip().lower()
    path = Path(os.environ.get("SQLITE_PATH", values.get("SQLITE_PATH", "data/qpark.db")))
    return AppConfig(backend, path if path.is_absolute() else root / path)
