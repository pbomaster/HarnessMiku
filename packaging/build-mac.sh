#!/bin/bash
set -euo pipefail
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
contents="$stage/volume/Harness Miku Installer.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
unzip -q "$1" -d "$contents/Resources"
xcrun swiftc -target arm64-apple-macos13.0 -O packaging/mac-installer.swift -o "$contents/MacOS/HarnessMikuInstaller"
cat >"$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.harnessmiku.setup</string>
<key>CFBundleExecutable</key><string>HarnessMikuInstaller</string>
<key>CFBundleName</key><string>Harness Miku Installer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>25</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$stage/volume/Harness Miku Installer.app"
codesign --verify --strict "$stage/volume/Harness Miku Installer.app"
hdiutil create -quiet -volname 'Harness Miku Installer' -srcfolder "$stage/volume" -format UDZO "$2"
hdiutil attach -readonly -nobrowse -mountpoint "$stage/mounted" "$2" -quiet
python3 packaging/verify.py dmg "$stage/mounted" "$1"
hdiutil detach "$stage/mounted" -quiet
