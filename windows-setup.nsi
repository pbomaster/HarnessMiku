Unicode true
SetCompressor /SOLID lzma
Name "Harness Miku v29 (Windows x64)"
OutFile "HarnessMiku-Windows-x64-Setup.exe"
RequestExecutionLevel user
ShowInstDetails show
Page instfiles
Section
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File windows-setup.ps1
  File *.py
  File *.js
  File *.cjs
  File *.json
  File *.css
  File retry-persona.txt
  File miku-mark.svg
  File LICENSE
  File third_party_notices.md
  DetailPrint "Preparing Harness Miku. Select the original model ZIP if requested."
  nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\windows-setup.ps1" -Model "$EXEDIR\New1007-RetrynowMiku.zip"'
  Pop $0
  StrCmp $0 "0" done
  SetErrorLevel 1
  Abort "Installation failed. See details above."
  done:
SectionEnd
