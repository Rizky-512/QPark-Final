"""Slot dihitung dari transaksi aktif; kegagalan baca tidak menjadi angka nol."""
from __future__ import annotations
from typing import TYPE_CHECKING
import flet as ft
from app.domain.errors import AuthorizationError, ParkingError
from app.ui.common import PRIMARY, MUTED, DANGER, SUCCESS, page_heading, panel, status_box, transaction_table
if TYPE_CHECKING:
    from app.ui.app_controller import ParkingApp


def build_dashboard_page(app: ParkingApp) -> ft.Control:
    search = ft.TextField(label="Cari kendaraan aktif", hint_text="Nomor polisi atau ID transaksi",
                          prefix_icon=ft.Icons.SEARCH, width=350, dense=True)
    summaries_area = ft.ResponsiveRow(spacing=16, run_spacing=16)
    active_area = ft.Column()

    def load(_=None) -> None:
        summaries_area.controls = [ft.ProgressRing(color=PRIMARY)]
        active_area.controls = []
        app.page.update()
        try:
            summaries, active = app.parking.dashboard(app.user_id, search.value or "")
            cards = []
            for item in summaries:
                full = item.kosong == 0
                color = DANGER if full else SUCCESS
                card = panel(ft.Column(spacing=16, controls=[
                    ft.Row(controls=[ft.Icon(ft.Icons.TWO_WHEELER if item.jenis_kendaraan == "Motor" else ft.Icons.DIRECTIONS_CAR, color=PRIMARY),
                        ft.Text(item.jenis_kendaraan, size=20, weight=ft.FontWeight.BOLD, expand=True),
                        ft.Icon(ft.Icons.BLOCK if full else ft.Icons.CHECK_CIRCLE, color=color, size=20),
                        ft.Text(item.label_status, color=color, weight=ft.FontWeight.BOLD)]),
                    ft.Row(alignment=ft.MainAxisAlignment.SPACE_BETWEEN, controls=[
                        ft.Column(spacing=2, controls=[ft.Text(str(value), size=28, weight=ft.FontWeight.BOLD,
                            color=color if label == "Kosong" else PRIMARY), ft.Text(label, color=MUTED)])
                        for label, value in [("Kapasitas", item.kapasitas), ("Terisi", item.terisi), ("Kosong", item.kosong)]])]))
                card.col = {"xs": 12, "md": 6}
                cards.append(card)
            summaries_area.controls = cards
            active_area.controls = [transaction_table(active)]
        except Exception as exc:
            message = str(exc) if isinstance(exc, ParkingError) else "Pembacaan data gagal. Coba lagi."
            summaries_area.controls = [status_box("Data slot tidak tersedia. " + message, False)]
            active_area.controls = []
            if isinstance(exc, AuthorizationError) or not isinstance(exc, ParkingError):
                raise
        app.page.update()

    search.on_submit = app.action(load)
    load()
    return ft.Column(expand=True, scroll=ft.ScrollMode.AUTO, spacing=20, controls=[
        page_heading("Beranda", "Ketersediaan tempat parkir Motor dan Mobil saat ini."), summaries_area,
        panel(ft.Column(spacing=14, controls=[
            ft.Row(wrap=True, controls=[ft.Text("Kendaraan aktif", size=19, weight=ft.FontWeight.BOLD), search,
                ft.OutlinedButton("Muat ulang", icon=ft.Icons.REFRESH, on_click=app.action(load))]), active_area]))])
