"""Pengaturan khusus admin; perubahan form dilacak per bagian."""
from __future__ import annotations
from datetime import date
from typing import TYPE_CHECKING
import flet as ft
from app.ui.common import PRIMARY, MUTED, SUCCESS_BG, BORDER, page_heading, panel, parse_date, vehicle_options, format_rupiah, status_box
if TYPE_CHECKING:
    from app.ui.app_controller import ParkingApp


def build_settings_page(app: ParkingApp) -> ft.Control:
    app.admin.require_user(app.user_id, "Admin")
    values = app.admin.settings(app.user_id)
    fields: dict[str, tuple[ft.TextField, ft.TextField]] = {}
    saved: dict[str, tuple[str, str]] = {}
    name = ft.TextField(label="Nama petugas *", width=240, dense=True)
    username = ft.TextField(label="Nama pengguna *", width=220, dense=True)
    password = ft.TextField(label="Kata sandi (min. 8 karakter) *", password=True,
                            can_reveal_password=True, width=250, dense=True)
    officers_area, account_result, revenue_area = ft.Column(), ft.Column(), ft.Column()
    busy = False

    def dirty() -> bool:
        return bool(name.value or username.value or password.value or any(
            (capacity.value, rate.value) != saved[kind] for kind, (capacity, rate) in fields.items()))
    app.dirty_check = dirty

    def save_settings(kind: str) -> None:
        capacity, rate = fields[kind]
        app.admin.update_settings(app.user_id, kind, capacity.value or "", rate.value or "")
        saved[kind] = (capacity.value, rate.value)
        app.show_message(f"Kapasitas dan tarif {kind} disimpan.")

    setting_rows = []
    for kind in ("Motor", "Mobil"):
        capacity = ft.TextField(label="Kapasitas *", value=str(values[kind]["kapasitas"]), width=145, dense=True)
        rate = ft.TextField(label="Tarif per jam *", value=str(values[kind]["tarif"]), prefix="Rp ", width=190, dense=True)
        fields[kind], saved[kind] = (capacity, rate), (capacity.value, rate.value)
        handler = app.action(lambda _, selected=kind: save_settings(selected))
        rate.on_submit = capacity.on_submit = handler
        setting_rows.append(ft.Row(wrap=True, controls=[
            ft.Icon(ft.Icons.TWO_WHEELER if kind == "Motor" else ft.Icons.DIRECTIONS_CAR, color=PRIMARY),
            ft.Text(kind, width=55, weight=ft.FontWeight.BOLD), capacity, rate,
            ft.Button(f"Simpan {kind.lower()}", icon=ft.Icons.SAVE, on_click=handler)]))

    def load_officers() -> None:
        officers = app.admin.list_officers(app.user_id)
        officers_area.controls = []
        for officer in officers:
            switch = ft.Switch(label="Aktif" if officer.aktif else "Nonaktif", value=officer.aktif)
            def toggle(_, control=switch, officer_id=officer.id_user) -> None:
                try:
                    app.admin.set_officer_active(app.user_id, officer_id, bool(control.value))
                    control.label = "Aktif" if control.value else "Nonaktif"
                    app.show_message("Status petugas diperbarui.")
                except Exception:
                    control.value = not control.value
                    raise
            switch.on_change = app.action(toggle)
            officers_area.controls.append(ft.Container(padding=10, border=ft.Border.all(1, BORDER), border_radius=8,
                content=ft.Row(controls=[ft.Icon(ft.Icons.BADGE_OUTLINED, color=PRIMARY),
                    ft.Column(expand=True, spacing=2, controls=[ft.Text(officer.nama, weight=ft.FontWeight.BOLD),
                        ft.Text(f"@{officer.username}", color=MUTED, size=12)]), switch])))
        if not officers:
            officers_area.controls = [ft.Text("Belum ada akun petugas.", color=MUTED)]

    add_button = ft.Button("Tambah akun", icon=ft.Icons.PERSON_ADD)
    def create_officer(_=None) -> None:
        nonlocal busy
        if busy:
            return
        busy = True
        add_button.disabled = True
        app.page.update()
        try:
            officer = app.admin.create_officer(app.user_id, name.value, username.value, password.value)
            name.value = username.value = password.value = ""
            account_result.controls = [status_box(f"Akun @{officer.username} berhasil dibuat.", True)]
            load_officers()
        finally:
            busy = False
            add_button.disabled = False
    add_button.on_click = password.on_submit = app.action(create_officer)

    today = date.today()
    start = ft.TextField(label="Tanggal awal (YYYY-MM-DD)", value=today.replace(day=1).isoformat(), width=215, dense=True)
    end = ft.TextField(label="Tanggal akhir (YYYY-MM-DD)", value=today.isoformat(), width=215, dense=True)
    vehicle = ft.Dropdown(label="Jenis kendaraan", value="Semua", options=vehicle_options(True), width=165, dense=True)
    def load_revenue(_=None) -> None:
        revenue_area.controls = [ft.Text("Menghitung pendapatan...", color=MUTED)]
        app.page.update()
        try:
            count, total = app.admin.revenue(app.user_id, parse_date(start.value, "Tanggal awal"),
                parse_date(end.value, "Tanggal akhir"), None if vehicle.value == "Semua" else vehicle.value)
        except Exception:
            revenue_area.controls = [status_box("Pendapatan gagal dihitung; periksa filter atau coba lagi.", False)]
            raise
        cards = []
        for title, value in [("Transaksi lunas", str(count)), ("Total pendapatan", format_rupiah(total))]:
            cards.append(ft.Container(col={"xs": 12, "md": 6}, padding=16, bgcolor=SUCCESS_BG, border_radius=8,
                content=ft.Column(spacing=4, controls=[ft.Text(value, size=26, color=PRIMARY, weight=ft.FontWeight.BOLD),
                                                      ft.Text(title, color=MUTED)])))
        revenue_area.controls = [ft.ResponsiveRow(controls=cards)]
    start.on_submit = end.on_submit = app.action(load_revenue)
    load_officers()
    load_revenue()
    return ft.Column(expand=True, scroll=ft.ScrollMode.AUTO, spacing=20, controls=[
        page_heading("Pengaturan admin", "Kelola tarif, kapasitas, petugas, dan ringkasan pendapatan."),
        panel(ft.Column(spacing=16, controls=[ft.Text("Kapasitas dan tarif", size=20, weight=ft.FontWeight.BOLD),
            ft.Text("Tarif baru berlaku untuk kendaraan yang masuk berikutnya.", color=MUTED, size=12), *setting_rows])),
        panel(ft.Column(spacing=16, controls=[ft.Text("Ringkasan pendapatan", size=20, weight=ft.FontWeight.BOLD),
            ft.Row(wrap=True, controls=[start, end, vehicle, ft.Button("Hitung", icon=ft.Icons.CALCULATE, on_click=app.action(load_revenue))]), revenue_area])),
        panel(ft.Column(spacing=16, controls=[ft.Text("Akun petugas", size=20, weight=ft.FontWeight.BOLD), officers_area,
            ft.Divider(color=BORDER), ft.Text("Tambah petugas", weight=ft.FontWeight.BOLD),
            ft.Row(wrap=True, controls=[name, username, password, add_button]), account_result]))])
