"""Palet hijau terpusat, format, dan komponen bersama seluruh halaman."""
from __future__ import annotations

from datetime import date, datetime
from typing import Sequence
import flet as ft
from app.domain.errors import ValidationError
from app.domain.models import Transaction
from app.logic.services import format_rupiah

PRIMARY = "#166534"
ACCENT = "#0F766E"
BACKGROUND = "#F3F8F4"
SURFACE = "#FFFFFF"
TEXT = "#172C20"
MUTED = "#53655A"
BORDER = "#D6E4DA"
SUCCESS = PRIMARY
SUCCESS_BG = "#EAF5ED"
DANGER = "#B42318"
DANGER_BG = "#FDEDEB"
ON_PRIMARY = "#FFFFFF"


def page_heading(title: str, subtitle: str) -> ft.Control:
    return ft.Column(spacing=4, controls=[
        ft.Text(title, size=26, weight=ft.FontWeight.BOLD, color=TEXT),
        ft.Text(subtitle, size=13, color=MUTED)])


def panel(content: ft.Control, padding: int = 20) -> ft.Container:
    return ft.Container(content=content, padding=padding, bgcolor=SURFACE,
                        border=ft.Border.all(1, BORDER), border_radius=12)


def status_box(message: str, success: bool) -> ft.Container:
    color = SUCCESS if success else DANGER
    return ft.Container(padding=12, bgcolor=SUCCESS_BG if success else DANGER_BG,
                        border_radius=8, content=ft.Row(controls=[
                            ft.Icon(ft.Icons.CHECK_CIRCLE if success else ft.Icons.ERROR_OUTLINE, color=color),
                            ft.Text(message, color=color, expand=True)]))


def format_datetime(value: datetime | None) -> str:
    return value.strftime("%d/%m/%Y %H:%M:%S") if value else "—"


def format_duration(seconds: int) -> str:
    hours, remaining = divmod(max(0, seconds), 3600)
    minutes, seconds = divmod(remaining, 60)
    return f"{hours} jam {minutes} menit {seconds} detik"


def parse_date(value: str | None, label: str) -> date:
    try:
        text = (value or "").strip()
        if len(text) != 10:
            raise ValueError
        return date.fromisoformat(text)
    except ValueError as exc:
        raise ValidationError(f"{label} harus berupa tanggal sah, contoh 2026-09-29.") from exc


def vehicle_options(include_all: bool = False) -> list[ft.DropdownOption]:
    kinds = ["Semua", "Motor", "Mobil"] if include_all else ["Motor", "Mobil"]
    return [ft.DropdownOption(key=kind, text=kind) for kind in kinds]


def transaction_table(rows: Sequence[Transaction]) -> ft.Control:
    if not rows:
        return ft.Container(padding=24, alignment=ft.Alignment.CENTER,
                            content=ft.Text("Belum ada kendaraan yang sesuai.", color=MUTED))
    return ft.Row(scroll=ft.ScrollMode.AUTO, controls=[ft.DataTable(
        heading_row_color=SUCCESS_BG, column_spacing=24,
        columns=[ft.DataColumn(ft.Text(title)) for title in ["ID transaksi", "Nomor polisi", "Jenis", "Waktu masuk", "Status"]],
        rows=[ft.DataRow(cells=[ft.DataCell(ft.Text(value, size=12)) for value in [
            row.id_transaksi, row.nomor_polisi, row.jenis_kendaraan,
            format_datetime(row.waktu_masuk), "Aktif • Belum Bayar"]]) for row in rows])])


def receipt(item: Transaction) -> ft.Control:
    """Bukti layar dan detail riwayat memakai data tersimpan yang sama."""
    seconds = int((item.waktu_keluar - item.waktu_masuk).total_seconds()) if item.waktu_keluar else 0
    lines = [
        f"ID: {item.id_transaksi}", f"Kendaraan: {item.nomor_polisi} • {item.jenis_kendaraan}",
        f"Masuk: {format_datetime(item.waktu_masuk)}", f"Keluar: {format_datetime(item.waktu_keluar)}",
        f"Durasi: {format_duration(seconds)}", f"Jam tertagih: {item.jam_tertagih} jam",
        f"Tarif saat masuk: {format_rupiah(item.tarif_per_jam_saat_masuk)}/jam",
        f"Total biaya: {format_rupiah(item.total_biaya)}", f"Tunai diterima: {format_rupiah(item.uang_diterima)}",
        f"Kembalian: {format_rupiah(item.kembalian)}", f"Petugas masuk: {item.nama_petugas_masuk}",
        f"Petugas keluar: {item.nama_petugas_keluar}"]
    return ft.Column(spacing=7, tight=True, controls=[
        ft.Text("Bukti pembayaran", size=20, weight=ft.FontWeight.BOLD, color=ACCENT),
        *[ft.Text(line, color=TEXT) for line in lines],
        status_box("Selesai • Lunas • Tunai", True)])
