"""Riwayat transaksi selesai dengan tanggal inklusif, pencarian, dan detail."""
from __future__ import annotations
from datetime import date
from typing import TYPE_CHECKING
import flet as ft
from app.ui.common import MUTED, SUCCESS, SUCCESS_BG, page_heading, panel, parse_date, vehicle_options, format_datetime, format_rupiah, receipt, status_box
if TYPE_CHECKING:
    from app.ui.app_controller import ParkingApp


def build_history_page(app: ParkingApp) -> ft.Control:
    today = date.today()
    start = ft.TextField(label="Tanggal awal (YYYY-MM-DD)", value=today.replace(day=1).isoformat(), width=215, dense=True)
    end = ft.TextField(label="Tanggal akhir (YYYY-MM-DD)", value=today.isoformat(), width=215, dense=True)
    vehicle = ft.Dropdown(label="Jenis kendaraan", value="Semua", width=165, options=vehicle_options(True), dense=True)
    query = ft.TextField(label="Cari pelat / ID transaksi", width=280, dense=True)
    area = ft.Column()

    def show_detail(transaction_id: str) -> None:
        item = app.parking.transaction_detail(app.user_id, transaction_id)
        app.page.show_dialog(ft.AlertDialog(title="Detail transaksi", scrollable=True,
            content=ft.Container(width=520, content=receipt(item)),
            actions=[ft.Button("Tutup", on_click=app.action(lambda _: app.page.pop_dialog()))]))

    def load(_=None) -> None:
        area.controls = [ft.Text("Memuat riwayat...", color=MUTED)]
        app.page.update()
        try:
            items = app.parking.history(app.user_id, parse_date(start.value, "Tanggal awal"),
                parse_date(end.value, "Tanggal akhir"), None if vehicle.value == "Semua" else vehicle.value, query.value or "")
        except Exception:
            area.controls = [status_box("Riwayat tidak dapat ditampilkan. Periksa filter atau coba lagi.", False)]
            raise
        if not items:
            area.controls = [ft.Text("Tidak ada transaksi pada filter ini.", color=MUTED)]
            return
        rows = []
        for item in items:
            rows.append(ft.DataRow(cells=[
                *[ft.DataCell(ft.Text(value, size=12)) for value in [item.id_transaksi, item.nomor_polisi,
                    item.jenis_kendaraan, format_datetime(item.waktu_keluar), format_rupiah(item.total_biaya)]],
                ft.DataCell(ft.Text("Lunas", color=SUCCESS)),
                ft.DataCell(ft.IconButton(ft.Icons.VISIBILITY_OUTLINED, tooltip="Lihat detail",
                    on_click=app.action(lambda _, key=item.id_transaksi: show_detail(key))))]))
        area.controls = [ft.Text(f"{len(items)} transaksi ditemukan", color=MUTED),
            ft.Row(scroll=ft.ScrollMode.AUTO, controls=[ft.DataTable(heading_row_color=SUCCESS_BG, column_spacing=20,
                columns=[ft.DataColumn(ft.Text(title)) for title in ["ID", "Nomor polisi", "Jenis", "Waktu keluar", "Total", "Status", "Detail"]], rows=rows)])]

    for field in (start, end, query):
        field.on_submit = app.action(load)
    load()
    return ft.Column(expand=True, scroll=ft.ScrollMode.AUTO, spacing=20, controls=[
        page_heading("Riwayat transaksi", "Rentang tanggal mencakup seluruh hari awal dan akhir berdasarkan waktu keluar."),
        panel(ft.Column(spacing=16, controls=[ft.Row(wrap=True, controls=[start, end, vehicle, query,
            ft.Button("Terapkan filter", icon=ft.Icons.FILTER_ALT, on_click=app.action(load))]), area]))])
