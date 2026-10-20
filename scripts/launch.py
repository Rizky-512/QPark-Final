"""Validate release freshness before starting the packaged server."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
def main():
    if sys.version_info<(3,10):print('Gunakan Python 3.10 atau lebih baru.');return 1
    manifest=ROOT/'rilis/source_manifest.json'
    rebuild=not (ROOT/'rilis/web/index.html').exists() or not manifest.exists()
    if manifest.exists():
        try:
            current = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                       for folder in ['lib', 'web', 'assets']
                       for p in (ROOT / folder).rglob('*') if p.is_file()}
            for name in ['pubspec.yaml', 'pubspec.lock']:
                current[name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
            rebuild = rebuild or current != json.loads(manifest.read_text())
        except (OSError, ValueError):
            rebuild = True
    if rebuild:
        print('Build belum tersedia atau kode berubah. Menyiapkan build terbaru...',flush=True)
        r=subprocess.run([sys.executable,str(ROOT/'scripts/build_release.py')],cwd=ROOT)
        if r.returncode:return r.returncode
    sys.path.insert(0,str(ROOT))
    from server.app import main as serve
    return serve()
if __name__=='__main__':sys.exit(main())
