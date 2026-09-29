"""Jalankan dengan interpreter venv; launcher.py menyiapkan dependensi otomatis."""
import sys


def main() -> int:
    try:
        from app.main import run
        run()
        return 0
    except KeyboardInterrupt:
        return 130
    except Exception:
        import traceback
        traceback.print_exc()
        print("QPark gagal dibuka. Gunakan python launcher.py untuk memeriksa dependensi.", flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
