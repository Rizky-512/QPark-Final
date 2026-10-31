"""Periodic verified local backups. Does not prune or overwrite existing backups."""
from contextlib import closing
from datetime import datetime, timezone
import logging
from pathlib import Path
import sqlite3
import threading
import uuid


def backup_once(source, directory):
    source, directory = Path(source), Path(directory)
    if not source.is_file():
        raise ValueError('Database sumber tidak ditemukan.')
    directory.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    destination = directory / f'qpark-{stamp}-{uuid.uuid4().hex[:8]}.db'
    with destination.open('xb'):
        pass
    try:
        with closing(sqlite3.connect(source.resolve().as_uri()+'?mode=ro', uri=True)) as src, closing(sqlite3.connect(destination)) as dst:
            src.backup(dst, pages=256)
            if dst.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise ValueError('Backup gagal pemeriksaan integritas.')
        return destination
    except Exception:
        destination.unlink(missing_ok=True)
        raise


class BackupWorker:
    def __init__(self, source, directory, interval_seconds=86400):
        self.source, self.directory, self.interval = source, directory, interval_seconds
        self.stopped = threading.Event()
        self.thread = threading.Thread(target=self._run, name='qpark-backup', daemon=True)

    def start(self):
        self.thread.start()

    def stop(self):
        self.stopped.set()
        self.thread.join(timeout=5)

    def _run(self):
        while not self.stopped.is_set():
            try:
                backup_once(self.source, self.directory)
                logging.getLogger('qpark.backup').info('backup_ok integrity=ok')
            except Exception:
                # No connection strings, credentials or database contents in logs.
                logging.getLogger('qpark.backup').error('backup_failed; periksa ruang disk dan izin folder backup')
            if self.stopped.wait(self.interval):
                break
