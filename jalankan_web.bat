@echo off
setlocal
cd /d "%~dp0"
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter SDK belum ditemukan. Untuk rilis siap pakai, gunakan buka_web.bat.
  pause
  exit /b 1
)
call flutter pub get
if errorlevel 1 goto gagal
if exist dart_defines.json (
  call flutter build web --release --no-web-resources-cdn --dart-define-from-file=dart_defines.json
) else (
  call flutter build web --release --no-web-resources-cdn
)
if errorlevel 1 goto gagal
where py >nul 2>nul
if not errorlevel 1 (
  py -3 -m server.app --directory build\web --open
) else (
  python -m server.app --directory build\web --open
)
if errorlevel 1 goto gagal
exit /b 0
:gagal
pause
exit /b 1
