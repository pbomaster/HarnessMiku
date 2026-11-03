Unicode true
SetCompressor /SOLID lzma
Name "Harness Miku v0.0.3 (Windows x64)"
OutFile "HarnessMiku-Windows-x64-Setup.exe"
RequestExecutionLevel user
ShowInstDetails show
Page instfiles
Section
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File windows-setup.ps1
  File codex-host.js
  File codex_patch.py
  File desktop-main.js
  File desktop-ui.js
  File features.py
  File fixed-voice.json
  File hashes.json
  File install_windows.py
  File layout.js
  File lines.json
  File pinned-recap.js
  File port.py
  File recap-tones.json
  File recap.js
  File speech-main.js
  File speech-ui.js
  File theme.css
  File voice-main.js
  File voice-preload.cjs
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
