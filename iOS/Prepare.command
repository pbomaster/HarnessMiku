#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
sdk="$(xcrun --sdk iphoneos --show-sdk-version)"
case "$sdk" in 27.2|27.2.*) ;; *) echo "현재 iOS SDK는 $sdk 입니다. iOS 27.2 SDK가 든 Xcode를 선택해 주세요."; exit 1;; esac
python3 Tools/prepare.py
open -a "$(xcode-select -p)/../.." HarnessMiku.xcodeproj
