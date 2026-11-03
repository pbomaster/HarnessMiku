#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)/$(uname -m)" != Darwin/arm64 ]]; then
    echo "Apple Silicon Mac용입니다."; exit 1
fi
command -v python3 >/dev/null || { echo "Python 3를 설치해 주세요."; exit 1; }
# Xcode command line tools supply git and Apple's signing commands.
git --version >/dev/null
destination="$HOME/Applications/Harness Miku.app"
if [[ -e "$destination" ]]; then
    echo "기존 Harness Miku.app을 닫고 다른 이름으로 옮긴 뒤 다시 실행해 주세요."; exit 1
fi
model="${1:-$PWD/New1007-RetrynowMiku.zip}"
if [[ ! -f "$model" ]]; then
    model="$(osascript -e 'POSIX path of (choose file with prompt "원본 New1007-RetrynowMiku.zip 선택" of type {"zip"})')"
fi
/bin/bash "$PWD/setup-sensevoice.sh"
mkdir -p "$HOME/Applications"
work="$(mktemp -d "$HOME/Applications/.harness-miku.XXXXXXXX")"
mountpoint="$work/mount"
cleanup() {
    if mount | grep -Fq " on $mountpoint ("; then hdiutil detach "$mountpoint" -quiet || { echo "임시 마운트 분리 실패: $mountpoint"; return; }; fi
    rm -rf "$work"
}
trap cleanup EXIT
image="$work/Harness.dmg"
official="https://download.deepseek.com/dsh-desk/bin/mac-arm64/deepseek-harness-0.2.1-rc.5-mac-arm64.dmg"
digest="7f387a78a7800de26af98a796c833295ebe57ee72f1f36a0810f296c871c2baf"
valid_image() { [[ -f "$1" && "$(shasum -a 256 "$1" | cut -d' ' -f1)" == "$digest" ]]; }
filename="deepseek-harness-0.2.1-rc.5-mac-arm64.dmg"
cache_dir="$HOME/Library/Caches/HarnessMiku"
if [[ -n "${2:-}" ]]; then
    image="$2"
else
    for candidate in "$PWD/$filename" "$HOME/Downloads/$filename" "$cache_dir/$filename"; do
        if valid_image "$candidate"; then image="$candidate"; break; fi
    done
    if [[ "$image" == "$work/Harness.dmg" ]]; then
        echo "고정 버전의 macOS 원본을 받는 중…"
        curl -fL --retry 2 "$official" -o "$image"
        valid_image "$image" || { echo "DMG SHA-256이 일치하지 않습니다."; exit 1; }
        mkdir -p "$cache_dir"
        mv -f "$image" "$cache_dir/$filename"
        image="$cache_dir/$filename"
    else
        echo "저장된 원본 DMG를 사용합니다."
    fi
fi
valid_image "$image" || { echo "DMG SHA-256이 일치하지 않습니다."; exit 1; }
mkdir "$mountpoint"
hdiutil attach "$image" -readonly -nobrowse -mountpoint "$mountpoint" -quiet
shopt -s nullglob
apps=("$mountpoint"/*.app)
[[ ${#apps[@]} -eq 1 ]] || { echo "원본 앱을 식별하지 못했습니다."; exit 1; }
codesign --verify --deep --strict "${apps[0]}"
app="$work/Harness Miku.app"
ditto "${apps[0]}" "$app"
hdiutil detach "$mountpoint" -quiet
chmod -R u+w "$app"
echo "원본 한국어 패치와 캐릭터 코드 받는 중…"
commit=96544431322d3f2cde1ec42db156c8b8eee5e6fd
git init -q "$work/upstream"
git -C "$work/upstream" fetch -q --depth=1 https://github.com/noire113-dev/deepseek-harness-kr.git "$commit"
git -C "$work/upstream" checkout -q --detach FETCH_HEAD
[[ "$(git -C "$work/upstream" rev-parse HEAD)" == "$commit" ]]
codesign --display --entitlements - --xml "$app" > "$work/entitlements.plist"
python3 - "$work/entitlements.plist" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1])
data=p.read_bytes()
try:
    ent=plistlib.loads(data) if data.strip() else {}
    if not isinstance(ent, dict):
        raise ValueError("expected a dictionary")
except (ValueError, plistlib.InvalidFileException) as exc:
    sys.exit("원본 앱의 서명 권한을 XML로 읽지 못했습니다. 다운로드한 DMG는 다음 실행에서 재사용합니다.")
# An ad-hoc outer shell loads the still vendor-signed Electron framework.
ent["com.apple.security.cs.disable-library-validation"]=True
ent["com.apple.security.cs.allow-jit"]=True
ent["com.apple.security.device.audio-input"]=True
p.write_bytes(plistlib.dumps(ent))
PY
python3 port.py "$app" "$work/upstream/harness/overlay" "$model"
resources="$app/Contents/Resources"
mkdir -p "$resources/HarnessMikuNotices"
cp "$work/upstream/LICENSE" "$work/upstream/NOTICE.md" "$resources/HarnessMikuNotices/"
# Retain the macOS updater metadata, adjusting only its feed as in the overlay.
if [[ -f "$resources/app-update.yml" ]]; then
    sed -i '' 's@^url:.*@url: https://127.0.0.1:9/dsh-update-disabled/@' "$resources/app-update.yml"
fi
codesign --force --sign - --options runtime --entitlements "$work/entitlements.plist" "$app"
codesign --verify --deep --strict "$app"
[[ ! -e "$destination" ]]
mv "$app" "$destination"
echo "완료: $destination"
open -R "$destination"
