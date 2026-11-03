@echo off
setlocal
cd /d "%~dp0"
py -3 -X utf8 install_windows.py %*
if errorlevel 1 echo Install failed. Check Python 3.12+, Git and the original Harness installation.
pause
