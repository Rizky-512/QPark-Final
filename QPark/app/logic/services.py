"""Use case aplikasi; tidak mengimpor komponen UI atau SQLite."""

from __future__ import annotations

import math
import re
from datetime import date, datetime
from typing import Callable

from app.data.repository import ParkingRepository
from app.domain.errors import (
    AuthenticationError,
    AuthorizationError,
    NotFoundError,
    PriceChangedError,
    ValidationError,
)
from app.domain.models import PaymentQuote, SlotSummary, Transaction, User
from app.logic.security import hash_password, verify_password
from app.logic import sessions

VEHICLE_TYPES = ("Motor", "Mobil")
PLATE_PATTERN = re.compile(r"^[A-Z0-9]{3,12}$")


def normalize_plate(value: str | None) -> str:
    """Hilangkan spasi dan validasi pelat untuk pencocokan lintas jenis."""
    normalized = "".join((value or "").upper().split())
    if not PLATE_PATTERN.fullmatch(normalized):
        raise ValidationError(
            "Nomor polisi wajib berisi 3–12 karakter huruf atau angka."
        )
    return normalized


MAX_INTEGER = 2**63 - 1


def parse_integer(value: str | int | None, field: str) -> int:
    """Terima bilangan bulat nonnegatif ASCII yang muat dalam SQLite."""
    if type(value) not in (str, int):
        raise ValidationError(f"{field} harus berupa bilangan bulat minimal 0.")
    text = str(value).strip()
    if not re.fullmatch(r"[0-9]{1,19}", text) or int(text) > MAX_INTEGER:
        raise ValidationError(f"{field} harus berupa bilangan bulat minimal 0 dan tidak terlalu besar.")
    return int(text)


def parse_rupiah(value: str | int | None, field: str) -> int:
    """Terima 5000, 5.000, atau Rp5.000; pecahan dan pengelompokan salah ditolak."""
    if type(value) not in (str, int):
        raise ValidationError(f"{field} harus berupa bilangan bulat rupiah.")
    text = str(value).strip()
    if text.lower().startswith("rp"):
        text = text[2:].strip()
    if not re.fullmatch(r"(?:[0-9]+|[1-9][0-9]{0,2}(?:\.[0-9]{3})+)", text):
        raise ValidationError(f"{field} harus bulat, misalnya 5000 atau Rp5.000; tanpa pecahan.")
    return parse_integer(text.replace(".", ""), field)


def validate_period(start: date, end: date, vehicle_type: str | None) -> None:
    """Validasi bersama untuk filter riwayat dan pendapatan."""
    if type(start) is not date or type(end) is not date:
        raise ValidationError("Tanggal awal dan akhir wajib berupa tanggal yang valid.")
    if end < start:
        raise ValidationError("Tanggal akhir tidak boleh sebelum tanggal awal.")
    if vehicle_type and vehicle_type not in VEHICLE_TYPES:
        raise ValidationError("Jenis kendaraan tidak valid.")


def format_rupiah(value: int | None) -> str:
    """Tampilkan bilangan bulat rupiah dengan pemisah ribuan Indonesia."""
    return f"Rp{(value or 0):,}".replace(",", ".")


class SecuredService:
    def __init__(self, repository: ParkingRepository) -> None:
        self.repository = repository

    def require_user(self, user_id: int, role: str | None = None) -> User:
        """Periksa sesi, status akun terkini, dan hak peran pada setiap tindakan."""
        if not sessions.is_active(self.repository, user_id):
            raise AuthorizationError("Sesi telah berakhir. Silakan masuk kembali.")
        user = self.repository.get_user(user_id)
        if not user or not user.aktif:
            sessions.revoke(self.repository, user_id)
            raise AuthorizationError(
                "Sesi tidak lagi aktif. Silakan masuk kembali."
            )
        if role and user.role != role:
            raise AuthorizationError("Anda tidak berhak melakukan tindakan ini.")
        return user


class AuthService:
    def __init__(self, repository: ParkingRepository) -> None:
        self.repository = repository

    def login(self, username: str | None, password: str | None) -> User:
        """Autentikasi akun aktif dengan pesan kegagalan yang sama."""
        clean_username = (username or "").strip().lower()
        if not clean_username or not password:
            raise AuthenticationError("Nama pengguna atau kata sandi tidak valid.")
        found = self.repository.get_user_for_login(clean_username)
        if not found:
            raise AuthenticationError("Nama pengguna atau kata sandi tidak valid.")
        user, password_hash = found
        if not user.aktif or not verify_password(password, password_hash):
            raise AuthenticationError("Nama pengguna atau kata sandi tidak valid.")
        sessions.activate(self.repository, user.id_user)
        return user

    def logout(self, user_id: int) -> None:
        """Cabut sesi sehingga service menolak ID yang dipakai setelah keluar."""
        sessions.revoke(self.repository, user_id)


class ParkingService(SecuredService):
    def __init__(
        self,
        repository: ParkingRepository,
        clock: Callable[[], datetime] = datetime.now,
    ) -> None:
        super().__init__(repository)
        self.clock = clock

    def dashboard(self, user_id: int, query: str = "") -> tuple[list[SlotSummary], list[Transaction]]:
        """Ambil slot dan daftar aktif tanpa mengganti kegagalan dengan data kosong."""
        self.require_user(user_id)
        return self.repository.get_slot_summaries(), self.repository.list_active(query)

    def record_entry(self, user_id: int, plate: str, vehicle_type: str) -> Transaction:
        """Validasi kendaraan lalu simpan masuk secara atomik melalui repository."""
        self.require_user(user_id, "Petugas")
        if vehicle_type not in VEHICLE_TYPES:
            raise ValidationError("Pilih jenis kendaraan Motor atau Mobil.")
        normalized = normalize_plate(plate)
        return self.repository.create_entry(
            normalized, vehicle_type, self.clock(), user_id
        )

    @staticmethod
    def _calculate_quote(transaction: Transaction, exited_at: datetime) -> PaymentQuote:
        """Hitung biaya minimum satu jam dengan pembulatan durasi ke atas."""
        duration = (exited_at - transaction.waktu_masuk).total_seconds()
        if duration < 0:
            raise ValidationError("Waktu keluar tidak boleh lebih awal dari waktu masuk.")
        billed_hours = max(1, math.ceil(duration / 3600))
        if billed_hours * transaction.tarif_per_jam_saat_masuk > MAX_INTEGER:
            raise ValidationError("Total biaya melampaui batas bilangan database.")
        return PaymentQuote(
            transaction=transaction,
            waktu_keluar=exited_at,
            durasi_detik=int(duration),
            jam_tertagih=billed_hours,
            total_biaya=billed_hours * transaction.tarif_per_jam_saat_masuk,
        )

    def quote_payment(self, user_id: int, transaction_id: str) -> PaymentQuote:
        """Berikan estimasi untuk transaksi yang masih aktif."""
        self.require_user(user_id, "Petugas")
        transaction = self.repository.get_transaction(transaction_id)
        if not transaction or transaction.status_parkir != "Aktif":
            raise NotFoundError("Transaksi aktif tidak ditemukan.")
        return self._calculate_quote(transaction, self.clock())

    def find_active(self, user_id: int, query: str = "") -> list[Transaction]:
        """Cari transaksi aktif khusus petugas berdasarkan pelat atau ID."""
        self.require_user(user_id, "Petugas")
        return self.repository.list_active(query)

    def complete_payment(
        self,
        user_id: int,
        transaction_id: str,
        received_value: str | int,
        expected_total: int,
    ) -> Transaction:
        """Hitung ulang biaya, minta konfirmasi ulang jika berubah, lalu bayar."""
        self.require_user(user_id, "Petugas")
        transaction = self.repository.get_transaction(transaction_id)
        if not transaction or transaction.status_parkir != "Aktif":
            raise NotFoundError("Transaksi aktif tidak ditemukan atau sudah selesai.")
        quote = self._calculate_quote(transaction, self.clock())
        if quote.total_biaya != expected_total:
            raise PriceChangedError(quote.total_biaya)
        received = parse_rupiah(received_value, "Uang diterima")
        if received < quote.total_biaya:
            raise ValidationError(
                f"Uang diterima kurang {format_rupiah(quote.total_biaya - received)}."
            )
        return self.repository.finish_transaction(
            transaction_id,
            quote.waktu_keluar,
            quote.jam_tertagih,
            quote.total_biaya,
            received,
            user_id,
        )

    def history(
        self,
        user_id: int,
        start: date,
        end: date,
        vehicle_type: str | None = None,
        query: str = "",
    ) -> list[Transaction]:
        """Tampilkan transaksi selesai dalam rentang hari inklusif."""
        self.require_user(user_id)
        validate_period(start, end, vehicle_type)
        return self.repository.list_history(start, end, vehicle_type, query)

    def transaction_detail(self, user_id: int, transaction_id: str) -> Transaction:
        """Baca ulang detail dengan pemeriksaan sesi, termasuk akun nonaktif."""
        self.require_user(user_id)
        transaction = self.repository.get_transaction(transaction_id)
        if not transaction or transaction.status_parkir != "Selesai":
            raise NotFoundError("Transaksi selesai tidak ditemukan.")
        return transaction


class AdminService(SecuredService):
    def settings(self, user_id: int) -> dict[str, dict[str, int]]:
        """Baca konfigurasi khusus admin."""
        self.require_user(user_id, "Admin")
        return self.repository.get_settings()

    def update_settings(
        self,
        user_id: int,
        vehicle_type: str,
        capacity_value: str | int,
        rate_value: str | int,
    ) -> None:
        """Validasi kapasitas dan tarif sebagai bilangan bulat yang sah."""
        self.require_user(user_id, "Admin")
        if vehicle_type not in VEHICLE_TYPES:
            raise ValidationError("Jenis kendaraan tidak valid.")
        capacity = parse_integer(capacity_value, "Kapasitas")
        rate = parse_rupiah(rate_value, "Tarif per jam")
        if rate <= 0:
            raise ValidationError("Tarif per jam harus lebih dari 0.")
        self.repository.update_settings(vehicle_type, capacity, rate)

    def list_officers(self, user_id: int) -> list[User]:
        """Tampilkan akun petugas tanpa hash password."""
        self.require_user(user_id, "Admin")
        return self.repository.list_users("Petugas")

    def create_officer(
        self,
        user_id: int,
        name: str | None,
        username: str | None,
        password: str | None,
    ) -> User:
        """Buat petugas dengan username unik huruf kecil dan hash bersalt."""
        self.require_user(user_id, "Admin")
        clean_name = (name or "").strip()
        clean_username = (username or "").strip().lower()
        if not clean_name:
            raise ValidationError("Nama petugas wajib diisi.")
        if not re.fullmatch(r"[a-z0-9._-]{3,30}", clean_username):
            raise ValidationError(
                "Nama pengguna harus 3–30 karakter: huruf kecil, angka, titik, garis bawah, atau minus."
            )
        if not password or len(password) < 8:
            raise ValidationError("Kata sandi minimal 8 karakter.")
        return self.repository.create_user(
            clean_name, clean_username, hash_password(password), "Petugas"
        )

    def set_officer_active(self, user_id: int, officer_id: int, active: bool) -> None:
        """Ubah status petugas tanpa menghapus jejak transaksi."""
        self.require_user(user_id, "Admin")
        self.repository.set_user_active(officer_id, active)

    def revenue(
        self,
        user_id: int,
        start: date,
        end: date,
        vehicle_type: str | None = None,
    ) -> tuple[int, int]:
        """Hitung jumlah lunas dan pendapatan dari total biaya, khusus admin."""
        self.require_user(user_id, "Admin")
        validate_period(start, end, vehicle_type)
        return self.repository.revenue_summary(start, end, vehicle_type)

