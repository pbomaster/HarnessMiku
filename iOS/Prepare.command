#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
sdk="$(xcrun --sdk iphoneos --show-sdk-version)"
case "$sdk" in 27.2|27.2.*) ;; *) echo "현재 iOS SDK는 $sdk 입니다. iOS 27.2 SDK가 든 Xcode를 선택해 주세요."; exit 1;; esac
model="${1:-$PWD/New1007-RetrynowMiku.zip}"
if [[ ! -f "$model" ]]; then
  model="$(osascript -e 'POSIX path of (choose file with prompt "제작자 원본 New1007-RetrynowMiku.zip 선택" of type {"zip"})')"
fi
python3 Tools/prepare.py "$model"
open -a "$(xcode-select -p)/../.." HarnessMiku.xcodeproj
