@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 scripts\launch.py --open
  if errorlevel 1 goto gagal
  exit /b 0
)
where python >nul 2>nul
if not errorlevel 1 (
  python scripts\launch.py --open
  if errorlevel 1 goto gagal
  exit /b 0
)
echo Python 3.10 atau lebih baru belum ditemukan. Pasang Python dan aktifkan Add to PATH.
:gagal
echo QPark berhenti. Periksa pesan di atas.
pause
exit /b 1
