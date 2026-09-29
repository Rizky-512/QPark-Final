"""Kasus penerimaan tambahan AT-01–AT-12 dan kegagalan database nyata."""
from __future__ import annotations

import sqlite3
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta
from unittest.mock import patch

from app.domain.errors import AuthenticationError, AuthorizationError, ConflictError, DataAccessError, NotFoundError, PriceChangedError, ValidationError
from app.logic.security import hash_password, verify_password
from app.logic.services import ParkingService, parse_integer, parse_rupiah
from tests import test_parking as fixture


class AcceptanceTest(unittest.TestCase):
    setUpClass = classmethod(fixture.ParkingFlowTest.setUpClass.__func__)
    setUp = fixture.ParkingFlowTest.setUp
    tearDown = fixture.ParkingFlowTest.tearDown

    def entry(self, plate: str = "AB1234CD", kind: str = "Motor"):
        return self.parking.record_entry(self.officer.id_user, plate, kind)

    def paid(self, plate: str = "AB1234CD", kind: str = "Motor", cash: int = 10000):
        entry = self.entry(plate, kind)
        quote = self.parking.quote_payment(self.officer.id_user, entry.id_transaksi)
        return self.parking.complete_payment(self.officer.id_user, entry.id_transaksi, cash, quote.total_biaya)

    def test_at01_logout_revokes_all_protected_access(self):
        self.auth.logout(self.officer.id_user)
        for operation in [lambda: self.parking.dashboard(self.officer.id_user),
                          lambda: self.entry(), lambda: self.parking.find_active(self.officer.id_user)]:
            with self.assertRaises(AuthorizationError):
                operation()
        self.auth.login(" PeTuGaS ", "Petugas123!")
        self.assertEqual(2, len(self.parking.dashboard(self.officer.id_user)[0]))

    def test_at01_empty_unknown_wrong_and_disabled_login(self):
        for name, secret in [("", ""), ("missing", "12345678"), ("admin", "bad")]:
            with self.assertRaisesRegex(AuthenticationError, "Nama pengguna atau kata sandi tidak valid"):
                self.auth.login(name, secret)
        self.admin_service.set_officer_active(self.admin.id_user, self.officer.id_user, False)
        with self.assertRaises(AuthenticationError):
            self.auth.login("petugas", "Petugas123!")

    def test_at02_all_admin_operations_refuse_officer(self):
        uid = self.officer.id_user
        operations = [lambda: self.admin_service.settings(uid),
                      lambda: self.admin_service.update_settings(uid, "Motor", 2, 2000),
                      lambda: self.admin_service.list_officers(uid),
                      lambda: self.admin_service.create_officer(uid, "Baru", "baru", "12345678"),
                      lambda: self.admin_service.set_officer_active(uid, uid, False),
                      lambda: self.admin_service.revenue(uid, date.today(), date.today())]
        for operation in operations:
            with self.assertRaises(AuthorizationError):
                operation()

    def test_at02_admin_cannot_operate_entry_quote_or_payment(self):
        item = self.entry()
        for operation in [lambda: self.parking.record_entry(self.admin.id_user, "B123AAA", "Motor"),
                          lambda: self.parking.quote_payment(self.admin.id_user, item.id_transaksi),
                          lambda: self.parking.find_active(self.admin.id_user),
                          lambda: self.parking.complete_payment(self.admin.id_user, item.id_transaksi, 5000, 2000)]:
            with self.assertRaises(AuthorizationError):
                operation()

    def test_at02_username_lowercase_unique_and_minimum_password(self):
        officer = self.admin_service.create_officer(self.admin.id_user, " Baru ", " BARU ", "12345678")
        self.assertEqual(("Baru", "baru"), (officer.nama, officer.username))
        with self.assertRaises(ConflictError):
            self.admin_service.create_officer(self.admin.id_user, "Lagi", "BaRu", "12345678")
        for name, username, password in [(" ", "xxx", "12345678"), ("A", "ab", "12345678"), ("A", "abc", "1234567")]:
            with self.assertRaises(ValidationError):
                self.admin_service.create_officer(self.admin.id_user, name, username, password)

    def test_at03_entry_snapshot_timestamp_officer_and_slots(self):
        entry = self.entry()
        self.assertEqual(self.clock.value, entry.waktu_masuk)
        self.assertEqual((2000, "Aktif", "Belum Bayar", self.officer.id_user),
                         (entry.tarif_per_jam_saat_masuk, entry.status_parkir, entry.status_pembayaran, entry.id_petugas_masuk))
        summaries, rows = self.parking.dashboard(self.officer.id_user)
        self.assertEqual(1, next(s.kosong for s in summaries if s.jenis_kendaraan == "Motor"))
        self.assertEqual([entry.id_transaksi], [r.id_transaksi for r in rows])

    def test_at04_plate_may_reenter_only_after_paid(self):
        old = self.paid()
        new = self.entry(" ab 1234 cd ", "Mobil")
        self.assertEqual(old.nomor_polisi, new.nomor_polisi)
        self.assertNotEqual(old.id_transaksi, new.id_transaksi)

    def test_at05_invalid_input_leaves_no_transaction(self):
        for plate, kind in [("", "Motor"), ("  ", "Motor"), ("A1", "Motor"), ("AB-123", "Motor"), ("AB123", "Sepeda")]:
            with self.assertRaises(ValidationError):
                self.entry(plate, kind)
        self.assertEqual([], self.repo.list_active())

    def test_at05_zero_capacity_and_missing_configuration(self):
        self.admin_service.update_settings(self.admin.id_user, "Motor", 0, 2000)
        with self.assertRaises(ConflictError):
            self.entry()
        with sqlite3.connect(self.repo.db_path) as con:
            con.execute("DELETE FROM kapasitas_parkir WHERE jenis_kendaraan='Motor'")
        with self.assertRaises(DataAccessError):
            self.parking.dashboard(self.officer.id_user)
        with self.assertRaises(ValidationError):
            self.entry()

    def test_at06_zero_sixty_sixtyone_and_subsecond_precision(self):
        self.clock.value = self.clock.value.replace(microsecond=900000)
        item = self.entry()
        for duration, hours in [(timedelta(0), 1), (timedelta(minutes=60), 1),
                                (timedelta(minutes=61), 2), (timedelta(hours=1, microseconds=1), 2)]:
            self.clock.value = item.waktu_masuk + duration
            quote = self.parking.quote_payment(self.officer.id_user, item.id_transaksi)
            self.assertEqual(hours, quote.jam_tertagih)

    def test_at06_clock_backward_rejected(self):
        item = self.entry()
        self.clock.value -= timedelta(seconds=1)
        with self.assertRaises(ValidationError):
            self.parking.quote_payment(self.officer.id_user, item.id_transaksi)
        with self.assertRaises(ValidationError):
            self.parking.complete_payment(self.officer.id_user, item.id_transaksi, 5000, 2000)
        self.assertEqual("Aktif", self.repo.get_transaction(item.id_transaksi).status_parkir)

    def test_at07_rupiah_formats_and_invalid_numbers(self):
        for value in [5000, "5000", "5.000", "Rp5.000", " rp 5.000 "]:
            self.assertEqual(5000, parse_rupiah(value, "Uang"))
        for value in ["", None, " ", "-1", "1.5", "1,5", "5.00", "1..000", "5 000", "5,000", True, 5.0, "²", "9"*40]:
            with self.assertRaises(ValidationError, msg=str(value)):
                parse_rupiah(value, "Uang")
        for value in ["2.0", "-1", "2.000", False, "∞"]:
            with self.assertRaises(ValidationError):
                parse_integer(value, "Kapasitas")

    def test_at07_receipt_complete_and_slot_released(self):
        item = self.entry()
        self.clock.value += timedelta(minutes=61)
        with self.assertRaises(ValidationError):
            self.parking.complete_payment(self.officer.id_user, item.id_transaksi, 3000, 4000)
        paid = self.parking.complete_payment(self.officer.id_user, item.id_transaksi, "Rp5.000", 4000)
        self.assertEqual((2, 4000, 5000, 1000, "Tunai", "Lunas", self.clock.value),
                         (paid.jam_tertagih, paid.total_biaya, paid.uang_diterima, paid.kembalian, paid.metode_pembayaran, paid.status_pembayaran, paid.waktu_keluar))
        self.assertEqual([], self.repo.list_active())

    def test_at08_quote_cancel_has_no_write(self):
        item = self.entry()
        for _ in range(3):
            self.parking.quote_payment(self.officer.id_user, item.id_transaksi)
        self.assertEqual(item, self.repo.get_transaction(item.id_transaksi))
        self.assertEqual(1, len(self.repo.list_active()))

    def test_at08_entry_failure_rolls_back_insert(self):
        with patch.object(self.repo, "_transaction", side_effect=sqlite3.OperationalError("injected read failure")):
            with self.assertLogs("app.data.sqlite_repository", level="ERROR"):
                with self.assertRaises(DataAccessError):
                    self.entry()
        self.assertEqual([], self.repo.list_active())

    def test_at08_payment_failure_rolls_back_update(self):
        item = self.entry()
        with patch.object(self.repo, "_transaction", side_effect=[item, sqlite3.OperationalError("injected failure")]):
            with self.assertLogs("app.data.sqlite_repository", level="ERROR"):
                with self.assertRaises(DataAccessError):
                    self.parking.complete_payment(self.officer.id_user, item.id_transaksi, 5000, 2000)
        self.assertEqual(item, self.repo.get_transaction(item.id_transaksi))
        self.assertEqual(1, len(self.repo.list_active()))

    def test_at08_concurrent_entry_cannot_exceed_capacity(self):
        self.admin_service.update_settings(self.admin.id_user, "Motor", 1, 2000)
        def enter(plate):
            try:
                return self.entry(plate)
            except ConflictError:
                return None
        with ThreadPoolExecutor(max_workers=2) as pool:
            result = list(pool.map(enter, ["AB1000A", "AB2000A"]))
        self.assertEqual(1, sum(item is not None for item in result))
        self.assertEqual(1, len(self.repo.list_active()))

    def test_at08_concurrent_payment_only_one_success(self):
        item = self.entry()
        def pay(_):
            try:
                return self.parking.complete_payment(self.officer.id_user, item.id_transaksi, 5000, 2000)
            except (ConflictError, NotFoundError):
                return None
        with ThreadPoolExecutor(max_workers=2) as pool:
            result = list(pool.map(pay, range(2)))
        self.assertEqual(1, sum(row is not None for row in result))
        self.assertEqual((1, 2000), self.admin_service.revenue(self.admin.id_user, self.clock.value.date(), self.clock.value.date()))

    def test_at09_reconfirmation_succeeds_at_new_price(self):
        item = self.entry()
        self.clock.value += timedelta(hours=1, seconds=1)
        with self.assertRaises(PriceChangedError):
            self.parking.complete_payment(self.officer.id_user, item.id_transaksi, 5000, 2000)
        self.assertEqual("Aktif", self.repo.get_transaction(item.id_transaksi).status_parkir)
        paid = self.parking.complete_payment(self.officer.id_user, item.id_transaksi, 5000, 4000)
        self.assertEqual(1000, paid.kembalian)

    def test_at10_inclusive_dates_midnight_and_last_microsecond(self):
        self.clock.value = datetime(2026, 9, 29)
        first = self.paid("AB111AA")
        self.clock.value = datetime(2026, 9, 29, 23, 59, 59, 999999)
        last = self.paid("AB222AA", "Mobil")
        self.clock.value = datetime(2026, 9, 30)
        self.paid("AB333AA")
        day = date(2026, 9, 29)
        rows = self.parking.history(self.admin.id_user, day, day)
        self.assertEqual({first.id_transaksi, last.id_transaksi}, {r.id_transaksi for r in rows})
        self.assertEqual([last.id_transaksi], [r.id_transaksi for r in self.parking.history(self.officer.id_user, day, day, "Mobil")])
        self.assertEqual((2, 7000), self.admin_service.revenue(self.admin.id_user, day, day))
        self.assertEqual((0, 0), self.admin_service.revenue(self.admin.id_user, date(2020, 1, 1), date(2020, 1, 1)))

    def test_at10_search_by_plate_id_and_literal_percent(self):
        item = self.entry()
        self.assertEqual(item.id_transaksi, self.parking.find_active(self.officer.id_user, "ab 1234 cd")[0].id_transaksi)
        self.assertEqual([], self.parking.find_active(self.officer.id_user, "%"))
        paid = self.parking.complete_payment(self.officer.id_user, item.id_transaksi, 10000, 2000)
        day = self.clock.value.date()
        for query in ("ab 1234 cd", paid.id_transaksi.lower()):
            self.assertEqual(1, len(self.parking.history(self.officer.id_user, day, day, query=query)))
        self.assertEqual(paid, self.parking.transaction_detail(self.officer.id_user, paid.id_transaksi))

    def test_at10_invalid_period_or_vehicle(self):
        for service in [self.parking.history, self.admin_service.revenue]:
            with self.assertRaises(ValidationError):
                service(self.admin.id_user, date(2026, 2, 2), date(2026, 2, 1))
            with self.assertRaises(ValidationError):
                service(self.admin.id_user, date.today(), date.today(), "Truk")
        self.assertEqual([], self.parking.history(self.admin.id_user, date.max, date.max))

    def test_at11_settings_rollback_preserves_rate_and_capacity(self):
        self.entry()
        old = self.repo.get_settings()
        with self.assertRaises(ValidationError):
            self.admin_service.update_settings(self.admin.id_user, "Motor", 0, 8000)
        self.assertEqual(old, self.repo.get_settings())
        for cap, rate in [("-1", "2000"), ("1.5", "2000"), (2, "0"), (2, "1.5"), (2, "-1"), (2, "")]:
            with self.assertRaises(ValidationError):
                self.admin_service.update_settings(self.admin.id_user, "Motor", cap, rate)

    def test_at11_rate_applies_only_to_future_entries(self):
        old = self.entry()
        self.admin_service.update_settings(self.admin.id_user, "Motor", 2, 3000)
        new = self.entry("AB5678CD")
        self.assertEqual((2000, 3000), (self.parking.quote_payment(self.officer.id_user, old.id_transaksi).total_biaya,
                                       self.parking.quote_payment(self.officer.id_user, new.id_transaksi).total_biaya))

    def test_at12_disable_open_session_denies_next_actions_and_detail(self):
        paid = self.paid()
        item = self.entry("AB9876CD")
        self.admin_service.set_officer_active(self.admin.id_user, self.officer.id_user, False)
        for operation in [lambda: self.entry("B8888AA"),
                          lambda: self.parking.quote_payment(self.officer.id_user, item.id_transaksi),
                          lambda: self.parking.complete_payment(self.officer.id_user, item.id_transaksi, 5000, 2000),
                          lambda: self.parking.transaction_detail(self.officer.id_user, paid.id_transaksi)]:
            with self.assertRaises(AuthorizationError):
                operation()
        self.assertEqual("Aktif", self.repo.get_transaction(item.id_transaksi).status_parkir)

    def test_at12_history_immutable_in_database(self):
        item = self.paid()
        with sqlite3.connect(self.repo.db_path) as con:
            for sql in ["UPDATE transaksi_parkir SET uang_diterima=2000 WHERE id_transaksi=?",
                        "DELETE FROM transaksi_parkir WHERE id_transaksi=?"]:
                with self.assertRaises(sqlite3.IntegrityError):
                    con.execute(sql, (item.id_transaksi,))
        self.assertEqual(item, self.repo.get_transaction(item.id_transaksi))

    def test_at12_hash_salt_and_corrupt_database_error(self):
        hashed = hash_password("same1234")
        self.assertNotEqual(hashed, hash_password("same1234"))
        self.assertTrue(verify_password("same1234", hashed))
        self.assertFalse(verify_password("wrong", hashed))
        self.assertFalse(verify_password("x", "broken"))
        self.repo.db_path.write_bytes(b"not a database")
        with self.assertLogs("app.data.sqlite_repository", level="ERROR"):
            with self.assertRaises(DataAccessError):
                self.parking.dashboard(self.officer.id_user)
