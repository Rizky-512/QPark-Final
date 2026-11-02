"""Explicit profile builds; test output never replaces rilis/web."""
import argparse
from pathlib import Path
import subprocess
import shutil
from build_release import find_flutter, ROOT
from environment_config import read_profile


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--environment', required=True, choices=['demo', 'test'])
    p.add_argument('--config', type=Path, required=True)
    p.add_argument('--demo-config', type=Path)
    p.add_argument('--target', choices=['web', 'apk'], default='web')
    args = p.parse_args()
    try:
        read_profile(args.config, args.environment, args.demo_config)
    except (ValueError, OSError) as error:
        p.error(str(error))
    flutter = find_flutter()
    if not flutter:
        p.error('Flutter SDK tidak ditemukan.')
    command = [flutter, 'build', args.target, '--release', f'--dart-define-from-file={args.config.resolve()}']
    if args.target == 'web':
        command += ['--no-web-resources-cdn', f'--output=build/environments/{args.environment}/web']
    result = subprocess.run(command, cwd=ROOT)
    if result.returncode == 0 and args.target == 'apk':
        destination = ROOT / 'build/environments' / args.environment / 'apk'
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'build/app/outputs/flutter-apk/app-release.apk', destination / 'app-release.apk')
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
