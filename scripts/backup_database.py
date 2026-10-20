"""Consistent backup using SQLite online backup, including committed WAL data."""
import argparse
from pathlib import Path
import sqlite3

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('destination',type=Path);a=p.parse_args()
    if not a.source.is_file():p.error('Database sumber tidak ditemukan.')
    if a.destination.exists():p.error('Tujuan sudah ada; pilih nama baru agar backup lama tidak tertimpa.')
    a.destination.parent.mkdir(parents=True,exist_ok=True)
    with sqlite3.connect(f'file:{a.source.resolve().as_posix()}?mode=ro',uri=True) as src,sqlite3.connect(a.destination) as dst:
        src.backup(dst)
        if dst.execute('PRAGMA integrity_check').fetchone()[0]!='ok':raise RuntimeError('Backup gagal pemeriksaan integritas.')
    print('Backup konsisten dibuat:',a.destination)
if __name__=='__main__':main()
