Unicode true
SetCompressor /SOLID lzma
Name "Harness Miku v0.1.0 (Windows x64)"
OutFile "HarnessMiku-Windows-x64-Setup.exe"
RequestExecutionLevel user
ShowInstDetails show
Page instfiles
Section
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File LICENSE
  File codex-host.js
  File codex_patch.py
  File conversation.js
  File desktop-main.js
  File desktop-ui.js
  File dsc-core-worker.js
  File features.py
  File fixed-voice.json
  File hashes.json
  File install_windows.py
  File layout.js
  File lines.json
  File lite.py
  File miku-mark.svg
  File performance.py
  File pinned-recap.js
  File place-cache.js
  File port.py
  File recap-tones.json
  File recap.js
  File renderer_patch.py
  File retry-persona.txt
  File speech-main.js
  File speech-ui.js
  File theme.css
  File third_party_notices.md
  File voice-main.js
  File voice-preload.cjs
  File windows-runtime.json
  File windows-setup.ps1
  File worker-init.js
  DetailPrint "Preparing Harness Miku. Select the original model ZIP if requested."
  nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\windows-setup.ps1" -Model "$EXEDIR\New1007-RetrynowMiku.zip"'
  Pop $0
  StrCmp $0 "0" done
  SetErrorLevel 1
  Abort "Installation failed. See details above."
  done:
SectionEnd
