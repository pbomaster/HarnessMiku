#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project HarnessMiku.xcodeproj -scheme HarnessMiku -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
