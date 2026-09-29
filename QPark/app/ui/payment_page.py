"""Estimasi, konfirmasi ulang biaya, dan pembayaran tunai tanpa simpan ganda."""
from __future__ import annotations
from typing import TYPE_CHECKING
import flet as ft
from app.domain.errors import PriceChangedError, ValidationError
from app.domain.models import PaymentQuote
from app.logic.services import format_rupiah, parse_rupiah
from app.ui.common import PRIMARY, MUTED, DANGER, SUCCESS, BORDER, format_datetime, format_duration, page_heading, panel, status_box, receipt
if TYPE_CHECKING:
    from app.ui.app_controller import ParkingApp


def build_payment_page(app: ParkingApp) -> ft.Control:
    selected: PaymentQuote | None = None
    busy = False
    dialog_open = False
    search = ft.TextField(label="Cari transaksi aktif", hint_text="Nomor polisi atau ID", dense=True)
    results = ft.Column(spacing=8)
    payment_area = ft.Column(col={"xs": 12, "md": 7})
    received = ft.TextField(label="Uang diterima (rupiah) *", hint_text="Contoh: 5000 atau 5.000",
                            prefix="Rp ", keyboard_type=ft.KeyboardType.NUMBER)
    change = ft.Text("Kembalian: —", size=16, weight=ft.FontWeight.BOLD, color=MUTED)
    confirm_button = ft.Button("Konfirmasi pembayaran", icon=ft.Icons.PAYMENTS, height=44)
    app.dirty_check = lambda: selected is not None or bool(received.value)

    def update_change(_=None) -> None:
        if selected is None:
            return
        try:
            amount = parse_rupiah(received.value, "Uang diterima")
            difference = amount - selected.total_biaya
            change.value = ("Kembalian: " if difference >= 0 else "Uang kurang: ") + format_rupiah(abs(difference))
            change.color = SUCCESS if difference >= 0 else DANGER
        except ValidationError:
            change.value, change.color = "Masukkan uang dalam bilangan bulat rupiah.", MUTED
        app.page.update()

    def clear(_=None) -> None:
        nonlocal selected
        selected = None
        received.value = ""
        payment_area.controls = [panel(ft.Text("Pilih kendaraan aktif untuk melihat estimasi biaya.", color=MUTED))]

    def show_quote() -> None:
        assert selected is not None
        item = selected.transaction
        payment_area.controls = [panel(ft.Column(spacing=10, controls=[
            ft.Text("Detail dan estimasi", size=20, color=PRIMARY, weight=ft.FontWeight.BOLD),
            ft.Text(item.id_transaksi, size=12, color=MUTED),
            ft.Text(f"{item.nomor_polisi} • {item.jenis_kendaraan}", size=22, weight=ft.FontWeight.BOLD),
            ft.Text(f"Masuk: {format_datetime(item.waktu_masuk)}"),
            ft.Text(f"Estimasi keluar: {format_datetime(selected.waktu_keluar)}"),
            ft.Text(f"Durasi: {format_duration(selected.durasi_detik)}"),
            ft.Text(f"Tarif tersimpan: {format_rupiah(item.tarif_per_jam_saat_masuk)}/jam"),
            ft.Text(f"Jam tertagih: {selected.jam_tertagih} jam"),
            ft.Text(f"Total: {format_rupiah(selected.total_biaya)}", size=24, color=PRIMARY, weight=ft.FontWeight.BOLD),
            received, change,
            ft.Row(wrap=True, controls=[confirm_button, ft.OutlinedButton("Batal", on_click=app.action(clear))]),
            ft.Text("Biaya dihitung ulang saat konfirmasi. Pembatalan tidak melepas slot.", color=MUTED, size=12)]))]
        if received.value:
            update_change()

    def select(transaction_id: str) -> None:
        nonlocal selected
        selected = app.parking.quote_payment(app.user_id, transaction_id)
        received.value = ""
        change.value, change.color = "Kembalian: —", MUTED
        show_quote()

    def load(_=None) -> None:
        # Kosongkan hasil sebelumnya agar error tidak meninggalkan data yang menyesatkan.
        results.controls = [ft.Text("Memuat kendaraan...", color=MUTED)]
        app.page.update()
        try:
            items = app.parking.find_active(app.user_id, search.value or "")
        except Exception:
            results.controls = [status_box("Daftar kendaraan gagal dimuat. Coba cari kembali.", False)]
            raise
        results.controls = [ft.Text(f"{len(items)} kendaraan ditemukan", color=MUTED)]
        for item in items:
            results.controls.append(ft.Container(padding=10, border=ft.Border.all(1, BORDER), border_radius=8,
                content=ft.Row(controls=[ft.Column(expand=True, spacing=3, controls=[
                    ft.Text(item.nomor_polisi, weight=ft.FontWeight.BOLD),
                    ft.Text(item.id_transaksi, size=11, color=MUTED),
                    ft.Text(f"{item.jenis_kendaraan} • {format_datetime(item.waktu_masuk)}", size=12, color=MUTED)]),
                    ft.OutlinedButton("Pilih", on_click=app.action(lambda _, key=item.id_transaksi: select(key)))])))
        if not items:
            results.controls = [ft.Text("Belum ada kendaraan yang sesuai.", color=MUTED)]

    def cancel_dialog(_=None) -> None:
        nonlocal dialog_open
        dialog_open = False
        app.page.pop_dialog()

    def confirm_dialog(_=None) -> None:
        nonlocal dialog_open
        if selected is None or busy or dialog_open:
            return
        app.parking.require_user(app.user_id, "Petugas")
        amount = parse_rupiah(received.value, "Uang diterima")
        if amount < selected.total_biaya:
            raise ValidationError("Uang diterima belum mencukupi total biaya.")
        # Bekukan pilihan dan nominal sesuai yang benar-benar dikonfirmasi pengguna.
        snapshot = selected
        dialog_open = True
        save_button = ft.Button("Ya, simpan", icon=ft.Icons.CHECK)

        def complete(_=None) -> None:
            nonlocal selected, busy, dialog_open
            if busy or not dialog_open:
                return
            busy = True
            dialog_open = False
            save_button.disabled = confirm_button.disabled = True
            app.page.pop_dialog()
            app.page.update()
            try:
                paid = app.parking.complete_payment(app.user_id, snapshot.transaction.id_transaksi,
                                                    amount, snapshot.total_biaya)
                selected = None
                received.value = ""
                payment_area.controls = [status_box("Pembayaran tersimpan; slot kembali tersedia.", True), panel(receipt(paid))]
                load()
            except PriceChangedError as exc:
                # Tidak ada perubahan data. Hitung dan tampilkan kembali kembalian juga.
                selected = app.parking.quote_payment(app.user_id, snapshot.transaction.id_transaksi)
                show_quote()
                update_change()
                app.show_message(str(exc), False)
            finally:
                busy = False
                confirm_button.disabled = False

        save_button.on_click = app.action(complete)
        app.page.show_dialog(ft.AlertDialog(modal=True, title="Konfirmasi pembayaran",
            content=ft.Text(f"{snapshot.transaction.nomor_polisi}\nTotal: {format_rupiah(snapshot.total_biaya)}\n"
                            f"Tunai: {format_rupiah(amount)}\nKembalian: {format_rupiah(amount - snapshot.total_biaya)}"),
            actions=[ft.TextButton("Kembali", on_click=app.action(cancel_dialog)), save_button]))

    received.on_change = app.action(update_change)
    received.on_submit = confirm_button.on_click = app.action(confirm_dialog)
    search.on_submit = app.action(load)
    clear()
    load()
    left = panel(ft.Column(spacing=12, controls=[ft.Text("Kendaraan aktif", size=19, weight=ft.FontWeight.BOLD),
        search, ft.OutlinedButton("Cari / muat ulang", icon=ft.Icons.SEARCH, on_click=app.action(load)), results]))
    left.col = {"xs": 12, "md": 5}
    return ft.Column(expand=True, scroll=ft.ScrollMode.AUTO, spacing=20, controls=[
        page_heading("Keluar dan pembayaran", "Periksa estimasi, terima uang tunai, lalu konfirmasi pembayaran."),
        ft.ResponsiveRow(spacing=18, run_spacing=18, controls=[left, payment_area])])
