#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)/$(uname -m)" != Darwin/arm64 ]]; then
    echo "Apple Silicon Mac용입니다."; exit 1
fi
# On a clean Mac the commands in /usr/bin may be developer-tool shims.
# Avoid invoking either shim before macOS has installed its developer tools.
tools_ready() {
    local tool path
    for tool in python3 git; do
        path="$(command -v "$tool")" || return 1
        if [[ "$path" == "/usr/bin/$tool" ]]; then
            /usr/bin/xcode-select -p >/dev/null 2>&1 || return 1
            /usr/bin/xcrun --find "$tool" >/dev/null 2>&1 || return 1
        fi
        "$path" --version >/dev/null 2>&1 || return 1
    done
}
if ! tools_ready; then
    echo "필요한 도구를 설치합니다. macOS 설치 창에서 설치를 선택하고 이 터미널을 열어 두세요."
    /usr/bin/xcode-select --install || {
        echo "Apple 개발자 도구 설치를 시작하지 못했습니다. 시스템 설정의 소프트웨어 업데이트를 확인해 주세요."
        exit 1
    }
    deadline=$((SECONDS + 3600))
    until tools_ready; do
        if (( SECONDS >= deadline )); then
            echo "도구 설치가 아직 완료되지 않았습니다. 설치가 끝난 뒤 다시 실행해 주세요."
            exit 1
        fi
        sleep 5
    done
fi
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
python3 port.py "$app" "$work/upstream/harness/overlay" "$model"
resources="$app/Contents/Resources"
mkdir -p "$resources/HarnessMikuNotices"
cp "$work/upstream/LICENSE" "$work/upstream/NOTICE.md" "$resources/HarnessMikuNotices/"
# Retain the macOS updater metadata, adjusting only its feed as in the overlay.
if [[ -f "$resources/app-update.yml" ]]; then
    sed -i '' 's@^url:.*@url: https://127.0.0.1:9/dsh-update-disabled/@' "$resources/app-update.yml"
fi
bash "$PWD/Repair-Permissions.command" --sign-staged "$app" "$work/entitlements.plist"
[[ ! -e "$destination" ]]
mv "$app" "$destination"
echo "완료: $destination"
open -R "$destination"
