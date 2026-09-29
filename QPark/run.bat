@echo off
setlocal
cd /d "%~dp0"
set PYTHONUTF8=1
where py >nul 2>&1
if not errorlevel 1 goto use_py
python -c "import sys; assert sys.version_info >= (3,10)" >nul 2>&1
if not errorlevel 1 goto use_python
echo Python tidak ditemukan. Pasang Python 3.10+ 64-bit dari python.org.
pause
exit /b 1
:use_py
py -3 launcher.py --no-pause
goto done
:use_python
python launcher.py --no-pause
:done
set EXITCODE=%ERRORLEVEL%
if "%EXITCODE%"=="0" exit /b 0
echo.
echo QPark berhenti dengan kode %EXITCODE%. Pesan error ada di atas.
pause
exit /b %EXITCODE%
