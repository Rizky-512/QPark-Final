@echo off
setlocal
cd /d "%~dp0"
if "%QPARK_API_URL%"=="" set "QPARK_API_URL=http://10.0.2.2:7357"
echo API: %QPARK_API_URL%
echo Pastikan server berjalan. Untuk HP fisik, atur QPARK_API_URL ke URL server yang dapat dijangkau.
call flutter pub get
if errorlevel 1 goto gagal
if exist dart_defines.json (
  call flutter run --dart-define-from-file=dart_defines.json --dart-define=API_BASE_URL=%QPARK_API_URL%
) else (
  call flutter run --dart-define=API_BASE_URL=%QPARK_API_URL%
)
if errorlevel 1 goto gagal
exit /b 0
:gagal
pause
exit /b 1
