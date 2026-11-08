#!/bin/bash
# Restore the exact binary runtime used by both August 8B and Ternary Bonsai 2 27B.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
vendor="$root/Vendor"
mkdir -p "$vendor"
stage=$(mktemp -d "$vendor/.prism-runtime.XXXXXX")
dest="$vendor/llama.xcframework"
cleanup() {
    if [[ ! -e "$dest" && -d "$stage/old" ]]; then mv "$stage/old" "$dest"; fi
    rm -rf "$stage"
}
trap cleanup EXIT
tag=prism-b10828-a153697
name="llama-${tag}-xcframework.zip"
archive=${1:-"$stage/$name"}
if [[ $# -eq 0 ]]; then
    curl --fail --location --retry 3 --output "$archive" "https://github.com/PrismML-Eng/llama.cpp/releases/download/$tag/$name"
fi
expected=29025230c2d0e9acd0755cbd467d02b6d8617fa42247454a22a0264a2a42a53f
actual=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
if [[ "$actual" != "$expected" ]]; then echo "Unexpected Prism XCFramework SHA-256" >&2; exit 1; fi
prefix=build-apple/llama.xcframework
unzip -q "$archive" "$prefix/Info.plist" "$prefix/ios-arm64/*" "$prefix/ios-arm64_x86_64-simulator/*" "$prefix/macos-arm64_x86_64/*" -d "$stage"
framework="$stage/$prefix"
python3 - "$framework" <<'PY'
import pathlib, plistlib, sys
folder = pathlib.Path(sys.argv[1])
manifest = folder / "Info.plist"
with manifest.open("rb") as file:
    info = plistlib.load(file)
slices = [lib for lib in info["AvailableLibraries"] if lib["SupportedPlatform"] in {"ios", "macos"}]
assert len(slices) == 3
for lib in slices:
    binary = folder / lib["LibraryIdentifier"] / lib["BinaryPath"]
    assert binary.is_file(), binary
info["AvailableLibraries"] = slices
with manifest.open("wb") as file:
    plistlib.dump(info, file)
PY
if [[ -e "$dest" ]]; then mv "$dest" "$stage/old"; fi
mv "$framework" "$dest"
echo "Installed Prism $tag (iOS device, iOS simulator, macOS)"
