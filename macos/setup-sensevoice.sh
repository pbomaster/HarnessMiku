#!/bin/bash
set -euo pipefail
root="$HOME/Library/Application Support/Harness Miku/SenseVoice"
target="$root/1.12.14-20240717"
if [[ -x "$target/runtime/bin/sherpa-onnx-offline" && -s "$target/model/model.int8.onnx" && -s "$target/model/tokens.txt" && -f "$target/verified" ]]; then exit 0; fi
mkdir -p "$root"
stage="$(mktemp -d "$root/.install.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT
base="https://github.com/k2-fsa/sherpa-onnx/releases/download"
fetch_asset(){
    local tag="$1" name="$2" digest="$3"
    local cache="$HOME/Library/Caches/HarnessMiku" archive
    mkdir -p "$cache"
    archive="$cache/$name.tar.bz2"
    if [[ ! -f "$archive" ]] || [[ "$(shasum -a 256 "$archive" | cut -d' ' -f1)" != "$digest" ]]; then
        curl -fL --retry 3 "$base/$tag/$name.tar.bz2" -o "$stage/download"
        [[ "$(shasum -a 256 "$stage/download" | cut -d' ' -f1)" == "$digest" ]] || { echo "SenseVoice 파일 해시가 일치하지 않습니다."; exit 1; }
        mv -f "$stage/download" "$archive"
    fi
    tar -xjf "$archive" -C "$stage"
}
runtime=sherpa-onnx-v1.12.14-osx-universal2-shared-no-tts
model=sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17
echo "로컬 받아쓰기 엔진과 SenseVoice 모델 준비 중 (첫 설치 약 198 MB)…"
fetch_asset v1.12.14 "$runtime" 60fe212f37171107d4d8939cdfc4614e4591572d2c0b6e55e30edef5e9ed0c7f
fetch_asset asr-models "$model" 7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e
mkdir "$stage/install"
mv "$stage/$runtime" "$stage/install/runtime"
mv "$stage/$model" "$stage/install/model"
python3 - "$stage/install" "$stage/probe.wav" <<'PY'
import sys,wave,subprocess,json
from pathlib import Path
root=Path(sys.argv[1]);probe=sys.argv[2]
with wave.open(probe,"wb") as f:
    f.setparams((1,2,16000,0,"NONE","")); f.writeframes(bytes(32000))
result=subprocess.run([str(root/'runtime/bin/sherpa-onnx-offline'),
    '--sense-voice-model='+str(root/'model/model.int8.onnx'),'--tokens='+str(root/'model/tokens.txt'),
    '--sense-voice-language=ko',probe],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=120)
if result.returncode:
    sys.exit('SenseVoice 설치 검사 실패: '+result.stderr[-1200:])
body=result.stderr.split(probe+'\n')[-1].split('\n----')[0]
if not isinstance(json.loads(body).get('text'),str):sys.exit('SenseVoice 출력 형식 검사 실패')
PY
touch "$stage/install/verified"
python3 - "$stage/install" "$target" <<'PY'
import os,sys
try: os.rename(sys.argv[1],sys.argv[2])
except OSError:
    if not os.path.isfile(os.path.join(sys.argv[2],'verified')):raise
PY
