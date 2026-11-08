#!/bin/bash
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo "macOS에서 실행하세요."; exit 1; }
apply_permissions() {
    local app="$1" ent="$2" identity="${MIKU_SIGN_IDENTITY:-}"
    if [[ -z "$identity" ]]; then
        local candidates
        candidates="$(/usr/bin/security find-identity -v -p codesigning | awk '/^[[:space:]]*[0-9]+\)/ {print $2}')"
        case "$candidates" in
            *$'\n'*) echo "서명 인증서가 여러 개입니다. MIKU_SIGN_IDENTITY로 하나를 선택하세요." >&2; return 1 ;;
            "") if [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" == local.harnessmiku.desktop ]]; then
                    echo "복구할 때는 설치 때와 같은 서명 인증서를 MIKU_SIGN_IDENTITY로 지정하세요." >&2; return 1
                fi
                identity="-" ;;
            *) identity="$candidates" ;;
        esac
    fi
    if [[ "$identity" == "-" ]]; then
        echo "임시 서명으로 설치합니다. 재설치 시 macOS 권한을 다시 승인해야 할 수 있습니다." >&2
    fi
    /usr/bin/codesign --display --entitlements - --xml "$app" > "$ent"
    python3 - "$ent" "$app/Contents/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
ep, ip = map(Path, sys.argv[1:])
data = ep.read_bytes()
ent = plistlib.loads(data) if data.strip() else {}
info = plistlib.loads(ip.read_bytes())
if info.get("CFBundleDisplayName") != "Harness Miku":
    sys.exit("Harness Miku 앱만 수정할 수 있습니다.")
ent.update({key: True for key in (
    "com.apple.security.cs.disable-library-validation",
    "com.apple.security.cs.allow-jit",
    "com.apple.security.device.audio-input",
    "com.apple.security.automation.apple-events",
)})
info.update(CFBundleIdentifier="local.harnessmiku.desktop",
            NSAppleEventsUsageDescription="요청한 작업을 수행하기 위해 다른 앱에 Apple 이벤트를 보냅니다.",
            NSAudioCaptureUsageDescription="요청한 화면 녹화에 Mac의 시스템 소리를 포함합니다.")
ep.write_bytes(plistlib.dumps(ent))
ip.write_bytes(plistlib.dumps(info))
PY
    /usr/bin/codesign --force --sign "$identity" --identifier local.harnessmiku.desktop --options runtime --entitlements "$ent" "$app"
    /usr/bin/codesign --verify --deep --strict "$app"
}

if [[ "${1:-}" == --sign-staged ]]; then
    apply_permissions "$2" "$3"
    exit
fi
app="${1:-$HOME/Applications/Harness Miku.app}"
[[ -d "$app/Contents" && ! -L "$app" ]] || { echo "Harness Miku.app 경로를 확인하세요."; exit 1; }
app="$(cd "$(dirname "$app")" && pwd -P)/$(basename "$app")"
if ps -ax -o command= | grep -F "$app/Contents/MacOS/" | grep -v 'grep -F' >/dev/null; then
    echo "Harness Miku를 완전히 종료한 뒤 다시 실행하세요."; exit 1
fi
work="$(mktemp -d "$(dirname "$app")/.miku-repair.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT
ditto "$app" "$work/repaired.app"
apply_permissions "$work/repaired.app" "$work/entitlements.plist"
backup="$(dirname "$app")/Harness Miku-before-repair-${work##*.}.backup"
[[ ! -e "$backup" ]]
mv "$work/repaired.app" "$backup"
# Same-volume atomic exchange. Even an interruption leaves the live app in place.
python3 - "$app" "$backup" <<'PYCODE'
import ctypes, os, sys
swap = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True).renamex_np
if swap(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 2):
    raise OSError(ctypes.get_errno(), "앱 교체 실패. 기존 앱은 원래 위치에 있습니다.")
PYCODE
echo "수정 완료: $app"
echo "원본 백업: $backup"
