"""Sesi, navigasi, dan penanganan kesalahan presentasi; bebas backend konkret."""
from __future__ import annotations

import inspect
import logging
from typing import Callable
import flet as ft
from app.data.repository import ParkingRepository
from app.domain.errors import AuthorizationError, ParkingError
from app.domain.models import User
from app.logic import AdminService, AuthService, ParkingService
from app.ui.common import BACKGROUND, PRIMARY, SURFACE, BORDER, MUTED, SUCCESS_BG, DANGER, ON_PRIMARY, status_box
from app.ui.dashboard_page import build_dashboard_page
from app.ui.entry_page import build_entry_page
from app.ui.history_page import build_history_page
from app.ui.login_page import build_login_page
from app.ui.payment_page import build_payment_page
from app.ui.settings_page import build_settings_page


class ParkingApp:
    def __init__(self, page: ft.Page, repository: ParkingRepository) -> None:
        self.page = page
        self.auth = AuthService(repository)
        self.parking = ParkingService(repository)
        self.admin = AdminService(repository)
        self.user: User | None = None
        self.content = ft.Container(expand=True, padding=24)
        self.nav_keys: list[str] = []
        self.nav: ft.NavigationRail | None = None
        self.current_key = "dashboard"
        self.dirty_check: Callable[[], bool] = lambda: False
        self.navigation_pending = False

    @property
    def user_id(self) -> int:
        if self.user is None:
            raise AuthorizationError("Silakan masuk kembali.")
        return self.user.id_user

    async def start(self) -> None:
        self.page.padding = 0
        self.page.bgcolor = BACKGROUND
        self.show_login()
        try:
            if getattr(self.page, "web", False):
                return
            await self.page.window.center()
            await self.page.window.to_front()
        except Exception:
            logging.getLogger(__name__).warning("Posisi jendela tidak dapat diatur", exc_info=True)

    def show_login(self) -> None:
        if self.user:
            self.auth.logout(self.user.id_user)
        self.user = None
        self.dirty_check = lambda: False
        self.navigation_pending = False
        self.nav_keys = []
        self.page.clean()
        self.page.add(build_login_page(self))

    def login(self, user: User) -> None:
        self.user = user
        self.show_shell()

    def show_message(self, message: str, success: bool = True) -> None:
        self.page.show_dialog(ft.SnackBar(
            content=ft.Text(("Berhasil: " if success else "Perhatian: ") + message, color=ON_PRIMARY),
            bgcolor=PRIMARY if success else DANGER, show_close_icon=True))

    def handle_error(self, exc: Exception) -> None:
        """Pesan bisnis aman; kesalahan tak terduga dicatat untuk diagnosis."""
        if isinstance(exc, AuthorizationError):
            self.show_login()
        if isinstance(exc, ParkingError):
            self.show_message(str(exc), False)
        else:
            logging.getLogger(__name__).exception("Operasi antarmuka gagal")
            self.show_message("Operasi belum berhasil. Periksa logs/qpark.log lalu coba kembali.", False)

    def action(self, callback: Callable) -> Callable:
        """Bungkus callback agar error tidak menghilang di event loop Flet."""
        async def guarded(event=None) -> None:
            try:
                result = callback(event)
                if inspect.isawaitable(result):
                    await result
            except Exception as exc:
                self.handle_error(exc)
            self.page.update()
        return guarded

    def confirm_leave(self, destination: Callable[[], None], label: str) -> None:
        """Minta persetujuan bila form berisi perubahan yang belum disimpan."""
        if self.navigation_pending:
            return
        if not self.dirty_check():
            destination()
            return
        self.navigation_pending = True

        def cancel(_=None) -> None:
            self.navigation_pending = False
            self.page.pop_dialog()
            if self.nav and self.current_key in self.nav_keys:
                self.nav.selected_index = self.nav_keys.index(self.current_key)

        def proceed(_=None) -> None:
            self.navigation_pending = False
            self.page.pop_dialog()
            destination()

        self.page.show_dialog(ft.AlertDialog(
            modal=True, title="Form belum disimpan",
            content=ft.Text("Isian yang belum disimpan akan dibuang. Transaksi tersimpan tetap aman."),
            actions=[ft.TextButton("Kembali", on_click=self.action(cancel)),
                     ft.Button(label, on_click=self.action(proceed))]))

    def logout(self, _=None) -> None:
        self.confirm_leave(self.show_login, "Lanjut keluar")

    def show_shell(self) -> None:
        assert self.user is not None
        items = [("dashboard", "Beranda", ft.Icons.DASHBOARD_OUTLINED)]
        if self.user.role == "Petugas":
            items += [("entry", "Kendaraan masuk", ft.Icons.LOGIN),
                      ("payment", "Keluar & bayar", ft.Icons.PAYMENTS_OUTLINED)]
        items += [("history", "Riwayat", ft.Icons.HISTORY)]
        if self.user.role == "Admin":
            items += [("settings", "Pengaturan", ft.Icons.SETTINGS_OUTLINED)]
        self.nav_keys = [key for key, _, _ in items]
        self.nav = ft.NavigationRail(
            destinations=[ft.NavigationRailDestination(icon=icon, label=label) for _, label, icon in items],
            selected_index=0, extended=True, label_type=ft.NavigationRailLabelType.NONE,
            min_extended_width=204, bgcolor=SURFACE, indicator_color=SUCCESS_BG, expand=True, scrollable=True,
            selected_label_text_style=ft.TextStyle(color=PRIMARY, weight=ft.FontWeight.BOLD),
            on_change=self.action(lambda e: self.confirm_leave(
                lambda: self.navigate(self.nav_keys[e.control.selected_index]), "Pindah halaman")))
        sidebar = ft.Container(width=220, bgcolor=SURFACE,
            border=ft.Border.only(right=ft.BorderSide(1, BORDER)), content=ft.Column(controls=[
                ft.Container(padding=20, content=ft.Row(controls=[
                    ft.Icon(ft.Icons.LOCAL_PARKING, color=PRIMARY, size=30),
                    ft.Text("QPark", size=25, color=PRIMARY, weight=ft.FontWeight.BOLD)])),
                ft.Divider(height=1, color=BORDER), self.nav,
                ft.Container(padding=16, content=ft.Column(controls=[
                    ft.Text(self.user.nama, weight=ft.FontWeight.BOLD),
                    ft.Text(self.user.role, color=MUTED, size=12),
                    ft.OutlinedButton("Keluar akun", icon=ft.Icons.LOGOUT,
                                      on_click=self.action(self.logout), width=184)]))]))
        self.page.clean()
        self.page.add(ft.Row(spacing=0, expand=True, controls=[sidebar, self.content]))
        self.navigate("dashboard")

    def navigate(self, key: str) -> None:
        builders = {"dashboard": build_dashboard_page, "entry": build_entry_page,
                    "payment": build_payment_page, "history": build_history_page, "settings": build_settings_page}
        self.parking.require_user(self.user_id)
        if key not in self.nav_keys:
            raise AuthorizationError("Anda tidak berhak membuka halaman tersebut.")
        self.current_key = key
        self.dirty_check = lambda: False
        if self.nav:
            self.nav.selected_index = self.nav_keys.index(key)
        try:
            self.content.content = builders[key](self)
        except Exception as exc:
            self.content.content = status_box("Halaman gagal dimuat. Gunakan menu untuk mencoba lagi.", False)
            self.handle_error(exc)
        self.page.update()
