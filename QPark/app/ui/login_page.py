"""Login akun aktif dengan pesan kegagalan umum dan dukungan Enter."""
from __future__ import annotations
from typing import TYPE_CHECKING
import flet as ft
from app.domain.errors import ParkingError
from app.ui.common import BACKGROUND, PRIMARY, ON_PRIMARY, MUTED, panel, status_box
if TYPE_CHECKING:
    from app.ui.app_controller import ParkingApp


def build_login_page(app: ParkingApp) -> ft.Control:
    username = ft.TextField(label="Nama pengguna *", autofocus=True,
                            prefix_icon=ft.Icons.PERSON_OUTLINE)
    password = ft.TextField(label="Kata sandi *", password=True, can_reveal_password=True,
                            prefix_icon=ft.Icons.LOCK_OUTLINE)
    message = ft.Column()
    button = ft.Button("Masuk", icon=ft.Icons.LOGIN, height=46, width=360,
                       bgcolor=PRIMARY, color=ON_PRIMARY)
    busy = False

    async def submit(_=None) -> None:
        nonlocal busy
        if busy:
            return
        busy = True
        button.disabled, button.content = True, "Memeriksa akun..."
        app.page.update()
        try:
            user = app.auth.login(username.value, password.value)
            app.login(user)
        except ParkingError as exc:
            message.controls = [status_box(str(exc), False)]
        finally:
            busy = False
            button.disabled, button.content = False, "Masuk"

    button.on_click = app.action(submit)
    password.on_submit = button.on_click
    async def focus_password(_=None) -> None:
        await password.focus()
    username.on_submit = app.action(focus_password)
    return ft.Container(expand=True, bgcolor=BACKGROUND, alignment=ft.Alignment.CENTER,
        content=panel(ft.Column(width=360, spacing=16, horizontal_alignment=ft.CrossAxisAlignment.CENTER, controls=[
            ft.Icon(ft.Icons.LOCAL_PARKING, size=52, color=PRIMARY),
            ft.Text("QPark", size=32, weight=ft.FontWeight.BOLD, color=PRIMARY),
            ft.Text("Pengelolaan Parkir", color=MUTED),
            username, password, button, message,
            ft.Text("Akun demo\nadmin / Admin123!\npetugas / Petugas123!",
                    size=12, color=MUTED, text_align=ft.TextAlign.CENTER)]), padding=28))
