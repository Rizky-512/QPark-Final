"""Konfigurasi backend, bootstrap, dan persistensi setelah proses dibuka ulang."""
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app.bootstrap import create_repository
from app.config import AppConfig, load_config
from app.domain.errors import ValidationError, AuthorizationError
from app.logic.services import AuthService, ParkingService, AdminService


class ConfigurationTest(unittest.TestCase):
    def test_defaults_and_relative_path_ignore_cwd(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {}, clear=True):
            root = Path(folder)
            config = load_config(root)
            self.assertEqual("sqlite", config.backend)
            self.assertEqual(root / 'data/qpark.db', config.database_path)
            (root / '.env').write_text('DB_BACKEND=sqlite\nSQLITE_PATH="data/custom.db"\n')
            self.assertEqual(root / 'data/custom.db', load_config(root).database_path)
            with patch.dict(os.environ, {'SQLITE_PATH': 'data/env.db'}):
                self.assertEqual(root / 'data/env.db', load_config(root).database_path)

    def test_unsupported_backend_is_explicitly_rejected(self):
        with self.assertRaises(ValidationError):
            create_repository(AppConfig(backend='supabase'))

    def test_at12_bootstrap_reopen_preserves_accounts_settings_and_transaction(self):
        with tempfile.TemporaryDirectory() as folder:
            config = AppConfig(database_path=Path(folder) / 'data/qpark.db')
            repo = create_repository(config)
            auth = AuthService(repo)
            admin = auth.login('admin', 'Admin123!')
            officer = auth.login('petugas', 'Petugas123!')
            entry = ParkingService(repo).record_entry(officer.id_user, 'AB1234CD', 'Motor')
            service = AdminService(repo)
            service.update_settings(admin.id_user, 'Motor', 4, 3000)
            service.set_officer_active(admin.id_user, officer.id_user, False)
            reopened = create_repository(config)
            self.assertEqual(entry, reopened.get_transaction(entry.id_transaksi))
            self.assertEqual({'tarif': 3000, 'kapasitas': 4}, reopened.get_settings()['Motor'])
            self.assertFalse(reopened.get_user(officer.id_user).aktif)
            with self.assertRaises(AuthorizationError):
                ParkingService(reopened).dashboard(admin.id_user)
