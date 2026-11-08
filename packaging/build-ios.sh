#!/bin/bash
# Produce a device binary without uploading a provisioning profile or signing identity.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
dest=${1:?Specify an absolute output IPA path}
[[ "$dest" = /* && ! -e "$dest" ]]
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$repo/iOS"
python3 Tools/prepare.py
xcodebuild -project HarnessMiku.xcodeproj -scheme HarnessMiku -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$work/build" \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO build
app="$work/build/Build/Products/Release-iphoneos/HarnessMiku.app"
test -x "$app/HarnessMiku"
xcrun lipo -verify_arch arm64 "$app/HarnessMiku"
/usr/libexec/PlistBuddy -c 'Print CFBundleSupportedPlatforms:0' "$app/Info.plist" | grep -qx iPhoneOS
python3 - "$app" <<'PY'
import hashlib, json, sys
from pathlib import Path
app = Path(sys.argv[1])
stage = app / "Stage"
allowed = {"pixi.min.js", "live2dcubismcore.min.js", "cubism4.patched.js", "LICENSE", "NOTICE.md"}
assert {p.name for p in (stage / "Private").iterdir()} == allowed
hashes = set(json.loads((stage / "model-hashes.json").read_text()).values())
for p in app.rglob('*'):
    if p.is_file():
        assert p.suffix.lower() not in {'.moc3', '.gguf', '.safetensors', '.mobileprovision'}, p
        assert hashlib.sha256(p.read_bytes()).hexdigest() not in hashes, p
PY
mkdir "$work/Payload"
mv "$app" "$work/Payload/"
(cd "$work" && /usr/bin/ditto -c -k --keepParent Payload app.ipa)
mkdir -p "$(dirname "$dest")"
mv "$work/app.ipa" "$dest"
