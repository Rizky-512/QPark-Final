"""Archive old SQLite records without guessing new sessions or payment states."""
import argparse
from pathlib import Path
import sqlite3
import json
import hashlib
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from server.store import Store

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('--target',type=Path,default=Path('data/qpark_server_v3.db'));a=p.parse_args()
    if not a.source.is_file():p.error('Sumber tidak ditemukan.')
    if a.source.resolve()==a.target.resolve():p.error('Sumber dan tujuan harus berbeda.')
    source_hash=hashlib.sha256(a.source.read_bytes()).hexdigest()
    with sqlite3.connect(f'file:{a.source.resolve().as_posix()}?mode=ro',uri=True) as src:
        src.row_factory=sqlite3.Row
        tables={r[0] for r in src.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if 'transaksi_parkir' not in tables:p.error('Tidak ditemukan tabel transaksi_parkir dari versi lama.')
        records=[dict(r) for r in src.execute('SELECT * FROM transaksi_parkir')]
    store=Store(a.target)
    with store.connection() as dst:
        dst.execute('BEGIN IMMEDIATE')
        dst.execute('CREATE TABLE IF NOT EXISTS legacy_archive(source_hash TEXT NOT NULL,row_number INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(source_hash,row_number))')
        for n,r in enumerate(records):dst.execute('INSERT OR IGNORE INTO legacy_archive VALUES(?,?,?)',(source_hash,n,json.dumps(r)))
        dst.commit()
    print(f'{len(records)} record diarsipkan. Tidak membuat sesi aktif atau pelunasan SRS baru. Sumber tidak diubah.')
if __name__=='__main__':main()
