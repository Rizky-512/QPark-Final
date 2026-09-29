"""Benchmark penerimaan NFR-02 dengan 1.000 transaksi dan 20 percobaan."""

from __future__ import annotations

import platform
import sys
import sqlite3
import statistics
import tempfile
import time
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.data.sqlite_repository import SQLiteParkingRepository
from app.logic import AuthService, ParkingService
from app.logic.security import hash_password


def measure(action, count: int = 20) -> list[float]:
    values = []
    for _ in range(count):
        started = time.perf_counter()
        action()
        values.append(time.perf_counter() - started)
    return values


def report(name: str, values: list[float]) -> bool:
    passed = sum(value <= 3 for value in values)
    p95 = sorted(values)[18]
    print(
        f"{name:12} lulus={passed}/20  median={statistics.median(values):.4f}s  "
        f"p95={p95:.4f}s  maksimum={max(values):.4f}s"
    )
    return passed >= 19


def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repository = SQLiteParkingRepository(Path(directory) / "benchmark.db")
        repository.initialize()
        repository.seed_defaults(hash_password("Admin123!"), hash_password("Petugas123!"))
        auth = AuthService(repository)
        admin = auth.login("admin", "Admin123!")
        officer = auth.login("petugas", "Petugas123!")
        parking = ParkingService(repository)

        connection = sqlite3.connect(repository.db_path)
        try:
            base = datetime(2026, 1, 1, 8, 0)
            rows = []
            for index in range(1000):
                entered = base + timedelta(minutes=index)
                exited = entered + timedelta(minutes=30)
                kind = "Motor" if index % 2 == 0 else "Mobil"
                rate = 2000 if kind == "Motor" else 5000
                rows.append(
                    (
                        f"BENCH-{index:04d}", f"B{index:04d}XX", kind,
                        entered.isoformat(sep=" "), exited.isoformat(sep=" "),
                        rate, 1, rate, "Tunai", rate, 0,
                        "Selesai", "Lunas", officer.id_user, officer.id_user,
                    )
                )
            connection.executemany(
                """INSERT INTO transaksi_parkir VALUES
                   (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                rows,
            )
            connection.commit()
        finally:
            connection.close()

        dashboard_times = measure(lambda: parking.dashboard(admin.id_user))
        search_times = measure(
            lambda: parking.history(
                admin.id_user, date(2026, 1, 1), date(2026, 12, 31), query="B0500XX"
            )
        )
        save_index = 0

        def save_once() -> None:
            nonlocal save_index
            transaction = parking.record_entry(
                officer.id_user, f"T{save_index:04d}ZZ", "Motor"
            )
            quote = parking.quote_payment(officer.id_user, transaction.id_transaksi)
            parking.complete_payment(officer.id_user, transaction.id_transaksi, 2000, quote.total_biaya)
            save_index += 1

        save_times = measure(save_once)
        print(f"Python {platform.python_version()} | {platform.platform()}")
        print("Dataset: 1.000 transaksi selesai, 1 operator aktif")
        passed = [report("Dashboard", dashboard_times), report("Pencarian", search_times), report("Simpan", save_times)]
        if not all(passed):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
