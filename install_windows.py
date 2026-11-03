"""Build a user-local x64 copy of the pinned Windows release."""
import hashlib
import os
from pathlib import Path
import shutil
import zipfile
import sys
import tarfile
import tempfile
import urllib.request

import port

COMMIT = "96544431322d3f2cde1ec42db156c8b8eee5e6fd"
RUNTIME = "sherpa-onnx-v1.12.14-win-x64-shared"
MODEL = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"


def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def speech_setup():
    root = Path(os.environ["APPDATA"]) / "Harness Miku/SenseVoice"
    root.mkdir(parents=True, exist_ok=True)
    target = root / "1.12.14-20240717"
    if (target / "runtime/bin/sherpa-onnx-offline.exe").is_file() and (target / "model/model.int8.onnx").is_file():
        return
    with tempfile.TemporaryDirectory(dir=root) as tmp:
        stage = Path(tmp)
        assembled = stage / "install"
        assembled.mkdir()
        for name, tag, checksum, folder in [
            (RUNTIME, "v1.12.14", "78fa331bac4d20828a867b14283950727ce668fe751d1a792352b7e035b0ffe1", "runtime"),
            (MODEL, "asr-models", "7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e", "model"),
        ]:
            archive = stage / "download.tar.bz2"
            url = f"https://github.com/k2-fsa/sherpa-onnx/releases/download/{tag}/{name}.tar.bz2"
            urllib.request.urlretrieve(url, archive)
            if digest(archive) != checksum:
                raise ValueError("음성 엔진 또는 모델의 해시가 일치하지 않습니다.")
            with tarfile.open(archive) as tar:
                tar.extractall(stage, filter="data")
            (stage/name).rename(assembled/folder)
        exe = assembled/"runtime/bin/sherpa-onnx-offline.exe"
        if not exe.is_file() or not (assembled/"model/model.int8.onnx").is_file():
            raise ValueError("SenseVoice 모델 파일을 확인하세요.")
        assembled.rename(target)


def install(source, model):
    target = Path(os.environ["LOCALAPPDATA"]) / "Programs/Harness Miku"
    if target.exists():
        raise FileExistsError("기존 Harness Miku 폴더를 닫고 다른 이름으로 옮긴 뒤 실행하세요.")
    for rel, expected in [
        ("DeepSeek Harness.exe", "7ae939b5a82b220fbd8ad04dfbafaaedb5a49ab43dc884a5db6381f678dd0cc4"),
        ("resources/app.asar", "e1b6f25fa937da98086c3e77af77aa14791105963c4d337a1c42179d232c6915"),
    ]:
        if digest(source/rel) != expected:
            raise ValueError("수정되지 않은 공식 Windows x64 0.2.1-rc.5 설치본을 선택하세요.")
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=target.parent) as tmp:
        stage = Path(tmp)
        repo = stage/"upstream"
        archive = stage/"overlay.zip"
        urllib.request.urlretrieve("https://codeload.github.com/noire113-dev/deepseek-harness-kr/zip/"+COMMIT, archive)
        if digest(archive) != "e050dec33e0d7ef81e8efa3fcc349822742a60786740cfa18e69255a59eb85b2":
            raise ValueError("한국어 패치 ZIP의 해시가 일치하지 않습니다.")
        with zipfile.ZipFile(archive) as z:
            prefix = "deepseek-harness-kr-"+COMMIT+"/"
            for info in z.infolist():
                rel = info.filename.removeprefix(prefix)
                if info.is_dir() or not (rel.startswith("harness/overlay/") or rel in {"LICENSE","NOTICE.md","harness/tools/app-update.yml"}):
                    continue
                path = repo/rel
                path.parent.mkdir(parents=True, exist_ok=True)
                with z.open(info) as src, path.open("wb") as dst:
                    shutil.copyfileobj(src,dst)
        app = stage/"app"
        shutil.copytree(source, app, ignore=shutil.ignore_patterns("Uninstall*.exe","app.asar.orig*","app.asar.bak*","debug.log"))
        port.build(app, repo/"harness/overlay", model)
        shutil.copyfile(repo/"harness/tools/app-update.yml",app/"resources/app-update.yml")
        notices = app/"resources/HarnessMikuNotices"
        notices.mkdir(exist_ok=True)
        for filename in ["LICENSE","NOTICE.md"]:
            shutil.copy(repo/filename, notices)
        app.rename(target)
    print("설치 완료:", target/"DeepSeek Harness.exe")


if __name__ == "__main__":
    if sys.platform != "win32" or sys.version_info < (3,12):
        sys.exit("Windows x64에서 Python 3.12 이상으로 실행하세요.")
    if sys.argv[1:] == ["--speech"]:
        speech_setup()
    else:
        base = Path(os.environ["LOCALAPPDATA"])/"Programs/DeepSeek Harness"
        model = (Path(sys.argv[2]) if len(sys.argv)>2 else Path(__file__).with_name("New1007-RetrynowMiku.zip"))
        if not model.is_file():
            from tkinter.filedialog import askopenfilename
            selected = askopenfilename(title="RetrynowMiku 원본 ZIP 선택",filetypes=[("ZIP","*.zip")])
            if not selected: sys.exit("취소했습니다.")
            model = Path(selected)
        install(Path(sys.argv[1]) if len(sys.argv)>1 else base, model)
