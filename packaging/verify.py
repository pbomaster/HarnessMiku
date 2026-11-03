"""Fail closed on unknown files, nested archives, or Live2D content before publishing."""
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path

COMMON = set("""README.md LICENSE third_party_notices.md docs/preview.webp codex_patch.py codex-host.js
desktop-main.js desktop-ui.js features.py fixed-voice.json hashes.json layout.js lines.json
miku-mark.svg pinned-recap.js port.py recap-tones.json recap.js retry-persona.txt speech-main.js
speech-ui.js theme.css voice-main.js voice-preload.cjs""".split())
MAC = COMMON | {"Install.command","Repair-Permissions.command","setup-sensevoice.sh"}
WIN = COMMON | {"install_windows.py","windows-setup.ps1","Install-Windows.cmd","windows-setup.nsi"}
SOURCE = MAC | WIN | {".github/workflows/release.yml",".github/workflows/withdraw-builds.yml",
                        "packaging/build-mac.sh","packaging/mac-installer.swift","packaging/verify.py"}
DENIED = set(json.loads(Path("hashes.json").read_text()).values())
PREVIEW_HASH = "cb86d22aee74164837d93104058a486a6bb81da6280104d8b8ea3c9974ccc903"
def audit(name, data):
    digest = hashlib.sha256(data).hexdigest()
    if name == 'docs/preview.webp' and digest == PREVIEW_HASH:
        return
    if digest in DENIED or data.startswith((b'MOC3',b'PK\x03\x04',b'\x89PNG',b'RIFF',b'\xff\xd8')):
        raise ValueError(f"Restricted or unreviewed asset: {name}")
    data.decode('utf8')
    if b'\0' in data:
        raise ValueError(f"Unexpected binary: {name}")

def package(name, files):
    target = Path("release")/name
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as out:
        for path in sorted(files):
            audit(path,Path(path).read_bytes())
            out.write(path,'HarnessMiku/'+path)
    with zipfile.ZipFile(target) as z:
        assert len(z.namelist()) == len(files)
        for path in files:
            content=z.read('HarnessMiku/'+path)
            assert content==Path(path).read_bytes()
            audit(path,content)

def exact(folder, expected):
    actual = {p.relative_to(folder).as_posix() for p in folder.rglob('*') if p.is_file()}
    if actual != expected: raise ValueError(f"Unexpected inventory: {actual ^ expected}")
    for name in expected:
        data=(folder/name).read_bytes()
        assert data==Path(name).read_bytes()
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
