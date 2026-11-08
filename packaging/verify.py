"""Fail closed on unknown files, nested archives, or Live2D content before publishing."""
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path

SHARED = set("""README.md
docs/preview.webp""".split())
MAC = SHARED | set("""Install.command
LICENSE
Repair-Permissions.command
Update.command
argon-notes.js
argon-system.js
codex-host.js
codex_patch.py
conversation.js
desktop-main.js
desktop-ui.js
dsc-core-worker.js
features.py
fixed-voice.json
hashes.json
layout.js
lines.json
lite.py
miku-bubble.txt
miku-mark.svg
miku-persona.txt
miku-title.txt
performance.py
pinned-recap.js
place-cache.js
port.py
recap-tones.json
recap.js
renderer_patch.py
retry-persona.txt
setup-sensevoice.sh
speech-main.js
speech-ui.js
theme.css
third_party_notices.md
voice-main.js
voice-preload.cjs
worker-init.js""".split())
WIN = SHARED | set("""Install-Windows.cmd
LICENSE
codex-host.js
codex_patch.py
conversation.js
desktop-main.js
desktop-ui.js
dsc-core-worker.js
features.py
fixed-voice.json
hashes.json
install_windows.py
layout.js
lines.json
lite.py
miku-mark.svg
performance.py
pinned-recap.js
place-cache.js
port.py
recap-tones.json
recap.js
renderer_patch.py
retry-persona.txt
speech-main.js
speech-ui.js
theme.css
third_party_notices.md
voice-main.js
voice-preload.cjs
windows-runtime.json
windows-setup.nsi
windows-setup.ps1
worker-init.js""".split())
SOURCE = WIN | {"macos/" + name for name in MAC - SHARED} | set(""".github/workflows/release.yml
.github/workflows/withdraw-builds.yml
.gitignore
Install.command
Repair-Permissions.command
Update.command
packaging/build-mac.sh
packaging/build-ios.sh
packaging/mac-installer.swift
packaging/verify.py
setup-sensevoice.sh""".split())
SOURCE |= set("""iOS/.gitignore
iOS/HarnessMiku.xcodeproj/project.pbxproj
iOS/HarnessMiku.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
iOS/HarnessMiku.xcodeproj/xcshareddata/xcschemes/HarnessMiku.xcscheme
iOS/HarnessMiku/Account.swift
iOS/HarnessMiku/Alerts.swift
iOS/HarnessMiku/App.swift
iOS/HarnessMiku/Assets.xcassets/AppIcon.appiconset/Contents.json
iOS/HarnessMiku/Assets.xcassets/AppIcon.appiconset/Icon.png
iOS/HarnessMiku/Assets.xcassets/Contents.json
iOS/HarnessMiku/CharacterSetup.swift
iOS/HarnessMiku/Chat.swift
iOS/HarnessMiku/FishSpeech.swift
iOS/HarnessMiku/HandsFreeInput.swift
iOS/HarnessMiku/LocalMikuRVC.swift
iOS/HarnessMiku/LocalMikuSpeech.swift
iOS/HarnessMiku/LipSync.swift
iOS/HarnessMiku/Preferences.swift
iOS/HarnessMiku/Push.entitlements
iOS/HarnessMiku/Services.swift
iOS/HarnessMiku/Stage.swift
iOS/HarnessMiku/Stage/actor.js
iOS/HarnessMiku/Stage/index.html
iOS/HarnessMiku/Stage/model-hashes.json
iOS/HarnessMiku/Stage/persona.txt
iOS/HarnessMiku/Stage/touch.js
iOS/HarnessMiku/Voice.swift
iOS/HarnessMiku/VoiceRoom.swift
iOS/LICENSE
iOS/Mac-Notices.md
iOS/Prepare.command
iOS/README.md
iOS/Relay/README.md
iOS/Relay/server.mjs
iOS/Tools/Tests/PromptChecks.swift
iOS/Tools/check-prompts.sh
iOS/Tools/check-sdk.sh
iOS/Tools/miku-mark.svg
iOS/Tools/pr7-gpu.patch
iOS/Tools/prepare-rvc-pack.py
iOS/Tools/prepare.py
iOS/Verify-Simulator.command""".split())
DENIED = set(json.loads(Path("hashes.json").read_text()).values())
PREVIEW_HASH = "cb86d22aee74164837d93104058a486a6bb81da6280104d8b8ea3c9974ccc903"
def audit(name, data):
    digest = hashlib.sha256(data).hexdigest()
    if name == 'iOS/HarnessMiku/Assets.xcassets/AppIcon.appiconset/Icon.png' and digest == '9042549d33f9b8af05be7090178266af92487fcac87ff04295d45e29017d17f2':
        return
    if name == 'docs/preview.webp' and digest == PREVIEW_HASH:
        return
    if digest in DENIED or data.startswith((b'MOC3',b'PK\x03\x04',b'\x89PNG',b'RIFF',b'\xff\xd8')):
        raise ValueError(f"Restricted or unreviewed asset: {name}")
    data.decode('utf8')
    if b'\0' in data:
        raise ValueError(f"Unexpected binary: {name}")

def source_path(name, files):
    return Path("macos", name) if files is MAC and name not in SHARED else Path(name)

def package(name, files):
    target = Path("release")/name
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as out:
        for path in sorted(files):
            audit(path,source_path(path,files).read_bytes())
            out.write(source_path(path,files),'HarnessMiku/'+path)
    with zipfile.ZipFile(target) as z:
        assert len(z.namelist()) == len(files)
        for path in files:
            content=z.read('HarnessMiku/'+path)
            assert content==source_path(path,files).read_bytes()
            audit(path,content)

def exact(folder, expected):
    actual = {p.relative_to(folder).as_posix() for p in folder.rglob('*') if p.is_file()}
    if actual != expected: raise ValueError(f"Unexpected inventory: {actual ^ expected}")
    for name in expected:
        data=(folder/name).read_bytes()
        assert data==source_path(name,expected).read_bytes()
        audit(name,data)

if __name__=='__main__':
    mode=sys.argv[1]
    if mode=='kits':
        files=set(subprocess.check_output(['git','ls-files','-z']).decode().rstrip('\0').split('\0'))
        if files!=SOURCE:raise ValueError(f"Review source manifest before upload: {files ^ SOURCE}")
        Path('release').mkdir(exist_ok=True)
        for name,items in [('HarnessMiku-Windows-x64.zip',WIN),('HarnessMiku-Mac.zip',MAC),('HarnessMiku-source.zip',SOURCE)]:
            package(name,items)
    elif mode=='exe':
        root=Path(sys.argv[2])
        payload={x for x in WIN if x not in {'README.md','docs/preview.webp','Install-Windows.cmd','windows-setup.nsi'}}
        # NSIS adds a single build-tool DLL. All remaining payload bytes must match reviewed sources.
        dll=root/'$PLUGINSDIR/nsExec.dll'
        allowed={hashlib.sha256(p.read_bytes()).digest() for p in Path('/usr/share/nsis/Plugins').rglob('nsExec.dll')}
        assert hashlib.sha256(dll.read_bytes()).digest() in allowed
        dll.unlink()
        assert all(p.is_relative_to(root/'$PLUGINSDIR') for p in root.rglob('*') if p.is_file())
        exact(root/'$PLUGINSDIR',payload)
    elif mode=='dmg':
        volume=Path(sys.argv[2]);app=volume/'Harness Miku Installer.app'; contents=app/'Contents'
        exact(contents/'Resources/HarnessMiku',MAC)
        for f in volume.rglob('*'):
            if f.is_file() and not f.is_relative_to(contents/'Resources/HarnessMiku'):
                assert f.relative_to(volume).as_posix() in {
                    'Harness Miku Installer.app/Contents/'+n for n in
                    ('MacOS/HarnessMikuInstaller','Info.plist','_CodeSignature/CodeResources')}
    else:raise ValueError(mode)
