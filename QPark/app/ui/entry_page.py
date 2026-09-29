"""Form masuk dan ringkasan hasil; isian tetap tersedia jika penyimpanan gagal."""
from __future__ import annotations
from typing import TYPE_CHECKING
import flet as ft
from app.ui.common import MUTED, page_heading, panel, status_box, vehicle_options, format_datetime, format_rupiah
if TYPE_CHECKING:
    from app.ui.app_controller import ParkingApp


def build_entry_page(app: ParkingApp) -> ft.Control:
    plate = ft.TextField(label="Nomor polisi *", hint_text="Contoh: AB 1234 CD", autofocus=True,
                         capitalization=ft.TextCapitalization.CHARACTERS)
    vehicle = ft.Dropdown(label="Jenis kendaraan *", value="Motor", options=vehicle_options())
    result = ft.Column()
    button = ft.Button("Simpan kendaraan masuk", icon=ft.Icons.SAVE, height=46)
    busy = False
    app.dirty_check = lambda: bool(plate.value or vehicle.value != "Motor")

    async def save(_=None) -> None:
        nonlocal busy
        if busy:
            return
        busy = True
        button.disabled, button.content = True, "Menyimpan..."
        app.page.update()
        try:
            transaction = app.parking.record_entry(app.user_id, plate.value or "", vehicle.value or "")
            result.controls = [status_box("Kendaraan berhasil masuk.", True), panel(ft.Column(spacing=10, controls=[
                ft.Text("Ringkasan kendaraan", size=19, weight=ft.FontWeight.BOLD),
                ft.Text(f"ID: {transaction.id_transaksi}"), ft.Text(f"Nomor polisi: {transaction.nomor_polisi}"),
                ft.Text(f"Jenis: {transaction.jenis_kendaraan}"), ft.Text(f"Masuk: {format_datetime(transaction.waktu_masuk)}"),
                ft.Text(f"Tarif tersimpan: {format_rupiah(transaction.tarif_per_jam_saat_masuk)}/jam"),
                ft.Text("Aktif • Belum Bayar", weight=ft.FontWeight.BOLD)]))]
            plate.value, vehicle.value = "", "Motor"
            await plate.focus()
        finally:
            busy = False
            button.disabled, button.content = False, "Simpan kendaraan masuk"

    button.on_click = app.action(save)
    plate.on_submit = button.on_click
    form = panel(ft.Column(spacing=16, controls=[ft.Text("Data kendaraan", size=19, weight=ft.FontWeight.BOLD),
        plate, vehicle, ft.Text("* Wajib diisi. Periksa pelat sebelum menyimpan.", size=12, color=MUTED), button]))
    form.col, result.col = {"xs": 12, "md": 6}, {"xs": 12, "md": 6}
    return ft.Column(expand=True, scroll=ft.ScrollMode.AUTO, spacing=20, controls=[
        page_heading("Kendaraan masuk", "Catat kendaraan yang tiba; waktu masuk diisi otomatis."),
        ft.ResponsiveRow(spacing=20, run_spacing=20, controls=[form, result])])
