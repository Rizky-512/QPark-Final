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
echo Flutter: %FLUTTER_CMD%
call "%FLUTTER_CMD%" pub get
if errorlevel 1 goto gagal
if exist dart_defines.json (
  call "%FLUTTER_CMD%" build web --release --no-web-resources-cdn --dart-define-from-file=dart_defines.json
) else (
  call "%FLUTTER_CMD%" build web --release --no-web-resources-cdn
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
