"""Smoke test kontrol/callback Flet asli tanpa renderer Windows.

FakePage hanya menggantikan koneksi jendela. Ini bukan bukti visual NFR-06.
"""
from __future__ import annotations

import asyncio
from dataclasses import fields
from datetime import timedelta
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch
from tests import test_parking as fixture

import flet as ft
from app.domain.errors import AuthorizationError, DataAccessError
from app.ui.app_controller import ParkingApp
from flet.controls.base_control import BaseControl
from flet.messaging.protocol import configure_encode_object_for_msgpack
import msgpack


def walk(control):
    if isinstance(control, BaseControl):
        yield control
        for field in fields(control):
            if field.name.startswith('_') or field.name in ('data', 'ref'):
                continue
            child = getattr(control, field.name)
            if isinstance(child, BaseControl):
                yield from walk(child)
            elif isinstance(child, list):
                for value in child:
                    yield from walk(value)


class FakePage:
    def __init__(self):
        self.controls = []
        self.dialogs = []
        self.window = SimpleNamespace(center=AsyncMock(), to_front=AsyncMock())

    def add(self, *controls):
        self.controls.extend(controls)
        self.update()

    def clean(self):
        self.controls.clear()
        self.dialogs.clear()

    def update(self):
        # Serializer Flet sebenarnya mendeteksi properti/kontrol tidak serializable.
        for control in self.controls + self.dialogs:
            msgpack.packb(control, default=configure_encode_object_for_msgpack(BaseControl))

    def show_dialog(self, dialog):
        dialog.open = True
        self.dialogs.append(dialog)
        self.update()

    def pop_dialog(self):
        return self.dialogs.pop() if self.dialogs else None


class UISmokeTest(unittest.TestCase):
    setUpClass = classmethod(fixture.ParkingFlowTest.setUpClass.__func__)
    tearDown = fixture.ParkingFlowTest.tearDown

    def setUp(self):
        fixture.ParkingFlowTest.setUp(self)
        self.page = FakePage()
        self.app = ParkingApp(self.page, self.repo)
        self.app.parking = self.parking
        self.app.login(self.officer)

    def nodes(self):
        return [node for root in self.page.controls + self.page.dialogs for node in walk(root)]

    def field(self, label):
        return next(node for node in self.nodes() if isinstance(node, ft.TextField) and node.label == label)

    def button(self, label):
        return next(node for node in self.nodes() if isinstance(node, (ft.Button, ft.OutlinedButton, ft.TextButton)) and node.content == label)

    def text(self):
        return '\n'.join(str(node.value) for node in self.nodes() if isinstance(node, ft.Text))

    def click(self, label):
        node = self.button(label)
        asyncio.run(node.on_click(SimpleNamespace(control=node)))

    def test_all_six_pages_construct_and_serialize(self):
        for key in ('dashboard', 'entry', 'payment', 'history'):
            self.app.navigate(key)
            self.page.update()
            self.assertNotIn('Halaman gagal dimuat', self.text())
        self.app.login(self.admin)
        self.app.navigate('settings')
        self.assertNotIn('Halaman gagal dimuat', self.text())
        self.app.show_login()
        self.assertIn('QPark', self.text())
        self.assertIsNotNone(self.field('Nama pengguna *').on_submit)
        self.assertIsNotNone(self.field('Kata sandi *').on_submit)

    def test_window_methods_are_awaited(self):
        asyncio.run(self.app.start())
        self.page.window.center.assert_awaited_once()
        self.page.window.to_front.assert_awaited_once()

    def test_entry_save_and_dirty_logout_cancel_then_confirm(self):
        self.app.navigate('entry')
        self.field('Nomor polisi *').value = 'AB1234AA'
        self.app.logout()
        self.assertIn('Isian yang belum disimpan', self.text())
        self.click('Kembali')
        self.assertIsNotNone(self.app.user)
        self.assertEqual('AB1234AA', self.field('Nomor polisi *').value)
        with patch.object(ft.TextField, 'focus', new_callable=AsyncMock):
            self.click('Simpan kendaraan masuk')
        self.assertEqual(1, len(self.repo.list_active()))
        self.assertFalse(self.app.dirty_check())
        self.field('Nomor polisi *').value = 'B1234AA'
        self.app.logout()
        self.click('Lanjut keluar')
        self.assertIsNone(self.app.user)
        with self.assertRaises(AuthorizationError):
            self.parking.dashboard(self.officer.id_user)
        self.assertEqual(1, len(self.repo.list_active()))

    def test_database_error_hides_all_stale_slot_cards(self):
        self.app.navigate('dashboard')
        with patch.object(self.parking, 'dashboard', side_effect=DataAccessError('Database gagal dibaca')):
            self.click('Muat ulang')
        self.assertIn('Data slot tidak tersedia', self.text())
        self.assertNotIn('Tersedia', self.text())
        self.assertNotIn('Kapasitas', self.text())

    def test_payment_cancel_then_pay_and_double_click(self):
        item = self.parking.record_entry(self.officer.id_user, 'AB9999AA', 'Motor')
        self.app.navigate('payment')
        self.click('Pilih')
        self.field('Uang diterima (rupiah) *').value = '5000'
        self.click('Konfirmasi pembayaran')
        self.click('Kembali')
        self.assertEqual('Aktif', self.repo.get_transaction(item.id_transaksi).status_parkir)
        self.click('Konfirmasi pembayaran')
        handler = self.button('Ya, simpan').on_click
        asyncio.run(handler())
        asyncio.run(handler())
        self.assertIn('Bukti pembayaran', self.text())
        self.assertIn('Kembalian: Rp3.000', self.text())
        self.assertFalse(self.app.dirty_check())
        self.assertEqual('Selesai', self.repo.get_transaction(item.id_transaksi).status_parkir)

    def test_price_change_refreshes_total_and_change_before_reconfirm(self):
        item = self.parking.record_entry(self.officer.id_user, 'AB9999AA', 'Motor')
        self.app.navigate('payment')
        self.click('Pilih')
        self.field('Uang diterima (rupiah) *').value = '5000'
        self.click('Konfirmasi pembayaran')
        self.clock.value += timedelta(hours=1, seconds=1)
        self.click('Ya, simpan')
        self.assertEqual('Aktif', self.repo.get_transaction(item.id_transaksi).status_parkir)
        self.assertIn('Total: Rp4.000', self.text())
        self.assertIn('Kembalian: Rp1.000', self.text())
        self.click('Konfirmasi pembayaran')
        self.click('Ya, simpan')
        self.assertEqual(4000, self.repo.get_transaction(item.id_transaksi).total_biaya)

    def test_settings_dirty_and_role_menus(self):
        self.assertNotIn('settings', self.app.nav_keys)
        self.app.login(self.admin)
        self.assertNotIn('entry', self.app.nav_keys)
        self.app.navigate('settings')
        self.field('Kapasitas *').value = '10'
        self.assertTrue(self.app.dirty_check())
        self.click('Simpan motor')
        self.assertFalse(self.app.dirty_check())
        self.field('Nama petugas *').value = 'Baru'
        self.assertTrue(self.app.dirty_check())

    def test_disabled_account_next_ui_action_returns_to_login(self):
        self.app.navigate('entry')
        self.field('Nomor polisi *').value = 'AB1234CD'
        self.admin_service.set_officer_active(self.admin.id_user, self.officer.id_user, False)
        self.click('Simpan kendaraan masuk')
        self.assertIsNone(self.app.user)
        self.assertEqual([], self.repo.list_active())
