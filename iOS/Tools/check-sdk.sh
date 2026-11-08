#!/bin/sh
set -eu
case "${SDK_VERSION:-}" in 27.2|27.2.*) ;; *) echo "error: iOS 27.2 SDK가 필요합니다. 현재 SDK: ${SDK_VERSION:-unknown}"; exit 1;; esac
for path in persona.txt august-persona.txt Private/miku/RetrynowMiku.model3.json Private/miku/RetrynowMiku.moc3 Private/pixi.min.js Private/cubism4.patched.js Private/live2dcubismcore.min.js; do
  test -s "$SRCROOT/HarnessMiku/Stage/$path" || { echo "error: 먼저 Prepare.command를 실행해 모델 및 렌더러를 준비해 주세요."; exit 1; }
done
