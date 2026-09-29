from __future__ import annotations

import sqlite3
import tempfile
import unittest
from dataclasses import replace
from datetime import date, datetime, timedelta
from pathlib import Path

from app.data.sqlite_repository import SQLiteParkingRepository
from app.domain.errors import (
    AuthenticationError,
    AuthorizationError,
    ConflictError,
    NotFoundError,
    PriceChangedError,
    ValidationError,
)
from app.logic.security import hash_password
from app.logic.services import AdminService, AuthService, ParkingService, normalize_plate


class MutableClock:
    def __init__(self, value: datetime) -> None:
        self.value = value

    def __call__(self) -> datetime:
        return self.value


class ParkingFlowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.admin_hash = hash_password("Admin123!")
        cls.officer_hash = hash_password("Petugas123!")

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.repo = SQLiteParkingRepository(Path(self.temp.name) / "test.db")
        self.repo.initialize()
        self.repo.seed_defaults(self.admin_hash, self.officer_hash)
        self.auth = AuthService(self.repo)
        self.admin = self.auth.login("admin", "Admin123!")
        self.officer = self.auth.login("petugas", "Petugas123!")
        self.clock = MutableClock(datetime(2026, 9, 29, 9, 0, 0))
        self.parking = ParkingService(self.repo, self.clock)
        self.admin_service = AdminService(self.repo)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_login_valid_invalid_and_role_guard(self) -> None:
        self.assertEqual("Admin", self.admin.role)
        with self.assertRaises(AuthenticationError):
            self.auth.login("admin", "salah")
        with self.assertRaises(AuthorizationError):
            self.parking.record_entry(self.admin.id_user, "AB1234CD", "Motor")
        with self.assertRaises(ValidationError):
            self.admin_service.create_officer(
                self.admin.id_user, "Baru", "petugasbaru", "pendek"
            )
        created = self.admin_service.create_officer(
            self.admin.id_user, "Petugas Baru", "petugasbaru", "Rahasia123!"
        )
        self.assertEqual("petugasbaru", created.username)
        with self.assertRaises(ConflictError):
            self.admin_service.create_officer(
                self.admin.id_user, "Duplikat", "petugasbaru", "Rahasia456!"
            )
        self.admin_service.set_officer_active(
            self.admin.id_user, self.officer.id_user, False
        )
        with self.assertRaises(AuthenticationError):
            self.auth.login("petugas", "Petugas123!")
        with self.assertRaises(AuthorizationError):
            self.parking.dashboard(self.officer.id_user)

    def test_plate_normalization_duplicate_and_capacity(self) -> None:
        first = self.parking.record_entry(self.officer.id_user, "ab 1234 cd", "Motor")
        self.assertEqual("AB1234CD", first.nomor_polisi)
        with self.assertRaises(ConflictError):
            self.parking.record_entry(self.officer.id_user, "AB1234CD", "Mobil")
        self.parking.record_entry(self.officer.id_user, "B2222XY", "Motor")
        with self.assertRaises(ConflictError):
            self.parking.record_entry(self.officer.id_user, "D3333ZZ", "Motor")
        summaries = {item.jenis_kendaraan: item for item in self.repo.get_slot_summaries()}
        self.assertEqual(0, summaries["Motor"].kosong)
        self.assertEqual(1, summaries["Mobil"].kosong)

    def test_plate_validation(self) -> None:
        self.assertEqual("AB123CD", normalize_plate(" ab 123 cd "))
        for invalid in ("", "A1", "AB-1234", "ABCDEFGHIJKLM"):
            with self.assertRaises(ValidationError):
                normalize_plate(invalid)

    def test_billing_boundaries_and_across_midnight(self) -> None:
        entry = self.parking.record_entry(self.officer.id_user, "AB1000AA", "Motor")
        for seconds, hours in ((0, 1), (3600, 1), (3601, 2)):
            quote = self.parking._calculate_quote(
                entry, entry.waktu_masuk + timedelta(seconds=seconds)
            )
            self.assertEqual(hours, quote.jam_tertagih)
        midnight_entry = replace(entry, waktu_masuk=datetime(2026, 9, 29, 23, 30))
        quote = self.parking._calculate_quote(
            midnight_entry, datetime(2026, 9, 30, 0, 30)
        )
        self.assertEqual(1, quote.jam_tertagih)

    def test_payment_and_repeat_prevention(self) -> None:
        entry = self.parking.record_entry(self.officer.id_user, "AB1111AA", "Motor")
        self.clock.value = datetime(2026, 9, 29, 10, 1, 0)
        quote = self.parking.quote_payment(self.officer.id_user, entry.id_transaksi)
        self.assertEqual(2, quote.jam_tertagih)
        self.assertEqual(4000, quote.total_biaya)
        with self.assertRaises(ValidationError):
            self.parking.complete_payment(
                self.officer.id_user, entry.id_transaksi, 3000, quote.total_biaya
            )
        paid = self.parking.complete_payment(
            self.officer.id_user, entry.id_transaksi, 5000, quote.total_biaya
        )
        self.assertEqual("Selesai", paid.status_parkir)
        self.assertEqual("Lunas", paid.status_pembayaran)
        self.assertEqual(1000, paid.kembalian)
        reopened = SQLiteParkingRepository(self.repo.db_path)
        self.assertEqual(
            "Lunas", reopened.get_transaction(entry.id_transaksi).status_pembayaran
        )
        with self.assertRaises(NotFoundError):
            self.parking.complete_payment(
                self.officer.id_user, entry.id_transaksi, 5000, quote.total_biaya
            )

    def test_price_change_requires_reconfirmation(self) -> None:
        entry = self.parking.record_entry(self.officer.id_user, "AB2222AA", "Motor")
        self.clock.value = datetime(2026, 9, 29, 10, 0, 0)
        old_quote = self.parking.quote_payment(self.officer.id_user, entry.id_transaksi)
        self.clock.value = datetime(2026, 9, 29, 10, 0, 1)
        with self.assertRaises(PriceChangedError) as context:
            self.parking.complete_payment(
                self.officer.id_user, entry.id_transaksi, 5000, old_quote.total_biaya
            )
        self.assertEqual(4000, context.exception.new_total)
        self.assertEqual("Aktif", self.repo.get_transaction(entry.id_transaksi).status_parkir)

    def test_rate_snapshot_capacity_validation_and_history(self) -> None:
        entry = self.parking.record_entry(self.officer.id_user, "AB3333AA", "Motor")
        with self.assertRaises(ValidationError):
            self.admin_service.update_settings(self.admin.id_user, "Motor", 0, 3000)
        self.admin_service.update_settings(self.admin.id_user, "Motor", 2, 3000)
        self.assertEqual(2000, self.repo.get_transaction(entry.id_transaksi).tarif_per_jam_saat_masuk)
        self.clock.value += timedelta(minutes=30)
        quote = self.parking.quote_payment(self.officer.id_user, entry.id_transaksi)
        self.parking.complete_payment(
            self.officer.id_user, entry.id_transaksi, 2000, quote.total_biaya
        )
        history = self.parking.history(
            self.admin.id_user, date(2026, 9, 29), date(2026, 9, 29), "Motor"
        )
        self.assertEqual(1, len(history))
        count, income = self.admin_service.revenue(
            self.admin.id_user, date(2026, 9, 29), date(2026, 9, 29), "Motor"
        )
        self.assertEqual((1, 2000), (count, income))

    def test_database_rejects_inconsistent_status(self) -> None:
        connection = sqlite3.connect(self.repo.db_path)
        try:
            connection.execute("PRAGMA foreign_keys = ON")
            with self.assertRaises(sqlite3.IntegrityError):
                connection.execute(
                    """INSERT INTO transaksi_parkir (
                        id_transaksi, nomor_polisi, jenis_kendaraan, waktu_masuk,
                        tarif_per_jam_saat_masuk, status_parkir, status_pembayaran,
                        id_petugas_masuk
                    ) VALUES ('BAD', 'AB1234', 'Motor', '2026-09-29 09:00:00',
                              2000, 'Aktif', 'Lunas', ?)""",
                    (self.officer.id_user,),
                )
            with self.assertRaises(sqlite3.IntegrityError):
                connection.execute(
                    """INSERT INTO transaksi_parkir (
                        id_transaksi, nomor_polisi, jenis_kendaraan, waktu_masuk,
                        waktu_keluar, tarif_per_jam_saat_masuk,
                        status_parkir, status_pembayaran, id_petugas_masuk,
                        id_petugas_keluar
                    ) VALUES ('BAD2', 'AB5678', 'Motor', '2026-09-29 09:00:00',
                              '2026-09-29 10:00:00', 2000, 'Selesai', 'Lunas', ?, ?)""",
                    (self.officer.id_user, self.officer.id_user),
                )
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main()
