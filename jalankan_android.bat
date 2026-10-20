@echo off
setlocal
cd /d "%~dp0"
set "FLUTTER_CMD=flutter"
where flutter >nul 2>nul
if not errorlevel 1 goto flutter_ready
if defined FLUTTER_ROOT if exist "%FLUTTER_ROOT%\bin\flutter.bat" set "FLUTTER_CMD=%FLUTTER_ROOT%\bin\flutter.bat"
if exist "%USERPROFILE%\development\flutter\bin\flutter.bat" set "FLUTTER_CMD=%USERPROFILE%\development\flutter\bin\flutter.bat"
if exist "C:\src\flutter\bin\flutter.bat" set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"
if not "%FLUTTER_CMD%"=="flutter" goto flutter_ready
echo Flutter SDK belum ditemukan di PATH, FLUTTER_ROOT, atau %%USERPROFILE%%\development\flutter.
pause
exit /b 1
:flutter_ready
if "%QPARK_API_URL%"=="" set "QPARK_API_URL=http://10.0.2.2:7357"
echo API: %QPARK_API_URL%
echo Pastikan server berjalan. Untuk HP fisik, atur QPARK_API_URL ke URL server yang dapat dijangkau.
echo Flutter: %FLUTTER_CMD%
call "%FLUTTER_CMD%" pub get
if errorlevel 1 goto gagal
if exist dart_defines.json (
  call "%FLUTTER_CMD%" run --dart-define-from-file=dart_defines.json --dart-define=API_BASE_URL=%QPARK_API_URL%
) else (
  call "%FLUTTER_CMD%" run --dart-define=API_BASE_URL=%QPARK_API_URL%
)
if errorlevel 1 goto gagal
exit /b 0
:gagal
pause
exit /b 1
