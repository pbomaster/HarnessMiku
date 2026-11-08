@echo off
setlocal
pushd "%~dp0" || exit /b 1
powershell.exe -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\windows-setup.ps1" %*
set "setupResult=%ERRORLEVEL%"
if not "%setupResult%"=="0" pause
popd
exit /b %setupResult%
