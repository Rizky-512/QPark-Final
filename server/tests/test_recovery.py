from contextlib import closing
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from scripts.restore_database import restore
from server.store import Store
from server.recovery import backup_once


class RecoveryTest(unittest.TestCase):
    def test_backup_restore_preserves_committed_wal_and_rejects_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            live, backup, restored = (root / name for name in ('live.db', 'backup.db', 'restored.db'))
            Store(live)
            with closing(sqlite3.connect(live)) as db:
                db.execute('PRAGMA journal_mode=WAL')
                db.execute("INSERT INTO metadata VALUES('recovery_marker','committed')")
                db.commit()
                subprocess.run([sys.executable, 'scripts/backup_database.py', str(live), str(backup)], check=True, capture_output=True)
            restore(backup, restored)
            with closing(sqlite3.connect(restored)) as db:
                self.assertEqual(db.execute("SELECT value FROM metadata WHERE key='recovery_marker'").fetchone()[0], 'committed')
            with self.assertRaises(FileExistsError):
                restore(backup, restored)
            automatic = backup_once(live, root/'automatic')
            self.assertTrue(automatic.is_file())
            self.assertNotEqual(automatic, backup_once(live, root/'automatic'))

    def test_corrupt_backup_does_not_create_target(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory)/'bad.db', Path(directory)/'target.db'
            source.write_bytes(b'not a database')
            with self.assertRaises(sqlite3.DatabaseError):
                restore(source, target)
            self.assertFalse(target.exists())
