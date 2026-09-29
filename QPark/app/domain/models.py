"""Model domain yang bebas dari Flet dan implementasi database."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True, slots=True)
class User:
    id_user: int
    nama: str
    username: str
    role: str
    aktif: bool


@dataclass(frozen=True, slots=True)
class SlotSummary:
    jenis_kendaraan: str
    kapasitas: int
    terisi: int

    @property
    def kosong(self) -> int:
        return self.kapasitas - self.terisi

    @property
    def label_status(self) -> str:
        return "Penuh" if self.kosong == 0 else "Tersedia"


@dataclass(frozen=True, slots=True)
class Transaction:
    id_transaksi: str
    nomor_polisi: str
    jenis_kendaraan: str
    waktu_masuk: datetime
    waktu_keluar: datetime | None
    tarif_per_jam_saat_masuk: int
    jam_tertagih: int | None
    total_biaya: int | None
    metode_pembayaran: str | None
    uang_diterima: int | None
    kembalian: int | None
    status_parkir: str
    status_pembayaran: str
    id_petugas_masuk: int
    id_petugas_keluar: int | None
    nama_petugas_masuk: str = ""
    nama_petugas_keluar: str = ""


@dataclass(frozen=True, slots=True)
class PaymentQuote:
    transaction: Transaction
    waktu_keluar: datetime
    durasi_detik: int
    jam_tertagih: int
    total_biaya: int

