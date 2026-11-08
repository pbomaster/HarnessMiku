#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)/$(uname -m)" != Darwin/arm64 ]]; then
    echo "Apple Silicon Mac에서 실행해 주세요."; exit 1
fi
app="$HOME/Applications/Harness Miku.app"
archive="$app/Contents/Resources/app.asar"
if [[ ! -f "$archive" || -L "$app" ]]; then
    echo "기존 설치를 찾지 못했어요. 새로 설치하려면 Install.command를 실행해 주세요."
    exit 1
fi
if /usr/bin/pgrep -f "^$app/Contents/MacOS/" >/dev/null; then
    echo "Harness Miku와 바탕화면 미쿠를 완전히 종료한 뒤 다시 실행해 주세요."
    exit 1
fi
tempdir="$(mktemp -d "${TMPDIR:-/tmp}/harness-miku-update.XXXXXXXX")"
trap 'rm -rf "$tempdir"' EXIT
model="$tempdir/New1007-RetrynowMiku.zip"
echo "기존 앱에서 미쿠 모델을 확인하는 중…"
python3 - "$archive" "$model" <<'PY'
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile

from port import FRONT, PREFIX, entry

archive, output = map(Path, sys.argv[1:])
expected = json.loads(Path("hashes.json").read_text())
try:
    with archive.open("rb") as source, zipfile.ZipFile(output, "x") as model:
        marker, size, payload, length = struct.unpack("<4I", source.read(16))
        if marker != 4 or size != payload + 4 or not 0 < length <= min(size - 8, 64 * 1024**2):
            raise ValueError("기존 앱의 ASAR 헤더를 확인할 수 없어요.")
        header = json.loads(source.read(length))
        for name, digest in expected.items():
            resource = FRONT / "miku" / name
            entries, key = entry(header, resource.as_posix())
            record = entries[key]
            count = record["size"]
            if not 0 < count <= 16 * 1024**2:
                raise ValueError(f"모델 파일 크기를 확인해 주세요: {name}")
            if record.get("unpacked"):
                with (Path(str(archive) + ".unpacked") / resource).open("rb") as item:
                    data = item.read(count + 1)
            else:
                source.seek(8 + size + int(record["offset"]))
                data = source.read(count)
            if len(data) != count or hashlib.sha256(data).hexdigest() != digest:
                raise ValueError(f"기존 모델이 원본과 일치하지 않아요: {name}")
            model.writestr(PREFIX + name, data)
except (OSError, KeyError, ValueError, struct.error) as error:
    sys.exit(f"모델을 가져오지 못했어요. 원본 모델 ZIP으로 Install.command를 실행해 주세요. ({error})")
PY
/bin/bash "$PWD/Install.command" "$model"
