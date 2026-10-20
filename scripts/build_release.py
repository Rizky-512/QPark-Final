"""Build Flutter and replace rilis/web only after a successful build."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]

def find_flutter():
    found=shutil.which('flutter')
    if found:return found
    roots=[]
    if os.environ.get('FLUTTER_ROOT'):roots.append(Path(os.environ['FLUTTER_ROOT']))
    roots.extend((Path.home()/'development/flutter',Path.home()/'flutter',Path('C:/src/flutter')))
    executable='flutter.bat' if sys.platform=='win32' else 'flutter'
    for root in roots:
        candidate=root/'bin'/executable
        if candidate.is_file():return str(candidate)
    return None

def main():
    flutter=find_flutter()
    if not flutter:
        print('Flutter SDK belum ditemukan di PATH, FLUTTER_ROOT, atau folder development/flutter.');return 1
    build=[flutter,'build','web','--release','--no-web-resources-cdn']
    defines=ROOT/'dart_defines.json'
    if defines.exists():build.append(f'--dart-define-from-file={defines}')
    for args in ([flutter,'pub','get'],build):
        completed=subprocess.run(args,cwd=ROOT)
        if completed.returncode:return completed.returncode
    destination=ROOT/'rilis/web';stage=ROOT/'rilis/web_new'
    if stage.exists():shutil.rmtree(stage)
    shutil.copytree(ROOT/'build/web',stage)
    if destination.exists():shutil.rmtree(destination)
    stage.rename(destination)
    manifest={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for folder in ['lib','web','assets'] for p in (ROOT/folder).rglob('*') if p.is_file()}
    manifest['pubspec.yaml']=hashlib.sha256((ROOT/'pubspec.yaml').read_bytes()).hexdigest()
    manifest['pubspec.lock']=hashlib.sha256((ROOT/'pubspec.lock').read_bytes()).hexdigest()
    (ROOT/'rilis/source_manifest.json').write_text(json.dumps(manifest,indent=2))
    print('Build baru tersedia di rilis/web. Jalankan buka_web.bat.');return 0
if __name__=='__main__':sys.exit(main())
