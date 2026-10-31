"""Validate a SQLite backup and restore to a NEW path; never overwrite a live DB."""
from contextlib import closing
import argparse
from pathlib import Path
import sqlite3


def restore(source: Path, destination: Path):
    if not source.is_file():
        raise ValueError('Backup tidak ditemukan.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(source.resolve().as_uri() + '?mode=ro', uri=True)) as src:
        if src.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise ValueError('Backup gagal pemeriksaan integritas.')
        if src.execute('PRAGMA foreign_key_check').fetchone() is not None:
            raise ValueError('Backup memiliki referensi data yang rusak.')
        tables = {row[0] for row in src.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if not {'sessions', 'invoices', 'officers', 'metadata'}.issubset(tables):
            raise ValueError('Berkas bukan database server QPark.')
        # Exclusive creation prevents accidental overwrite even under a race.
        with destination.open('xb'):
            pass
        try:
            with closing(sqlite3.connect(destination)) as dst:
                src.backup(dst)
                if dst.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                    raise ValueError('Hasil pemulihan gagal pemeriksaan integritas.')
        except Exception:
            destination.unlink(missing_ok=True)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    try:
        restore(args.source, args.destination)
    except (ValueError, FileExistsError, sqlite3.Error) as error:
        parser.error(str(error))
    print('Pemulihan tervalidasi:', args.destination)
    print('Jalankan server dengan --db menunjuk hasil ini setelah server lama dihentikan.')


if __name__ == '__main__':
    main()
