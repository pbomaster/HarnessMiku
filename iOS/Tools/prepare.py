"""Prepare the pinned renderer without any character artwork."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REV = "96544431322d3f2cde1ec42db156c8b8eee5e6fd"
ARCHIVES = {"e050dec33e0d7ef81e8efa3fcc349822742a60786740cfa18e69255a59eb85b2",
            "10957565f608a2db6af6902b255b1b10c327ceedc31fbb6a2c6930c92c39ce7e"}
VENDOR = "harness/overlay/dsh/node_modules/@deepseek-ai/dsh-web-frontend/dist/assets/dsc/vendor/"
def build(overlay):
    out = ROOT / "HarnessMiku/Stage/Private"
    with tempfile.TemporaryDirectory(dir=ROOT) as temp:
        stage = Path(temp) / "renderer"
        stage.mkdir()
        if overlay is None:
            overlay = Path(temp) / "upstream.zip"
            subprocess.run(["curl", "-fLsS", "--retry", "2", "-o", str(overlay),
                            "https://codeload.github.com/noire113-dev/deepseek-harness-kr/zip/" + REV], check=True)
        if hashlib.sha256(overlay.read_bytes()).hexdigest() not in ARCHIVES:
            raise ValueError("Renderer archive checksum mismatch")
        with zipfile.ZipFile(overlay) as archive:
            prefix = archive.namelist()[0]
            for name in ["pixi.min.js", "live2dcubismcore.min.js", "cubism4.patched.js", "LICENSE", "NOTICE.md"]:
                path = (VENDOR if name.endswith(".js") else "") + name
                (stage / name).write_bytes(archive.read(prefix + path))
        subprocess.run(["patch", "-F", "0", "-p0", "-i", str(ROOT / "Tools/pr7-gpu.patch")], cwd=stage, check=True)
        if hashlib.sha256((stage / "cubism4.patched.js").read_bytes()).hexdigest() != "142116486b7e025836a3a7cf3ea0c6c5a0cdd1e0869b219f2a0b8d7daf5918ae":
            raise ValueError("Patched renderer checksum mismatch")
        old = Path(temp) / "previous"
        if out.exists(): out.rename(old)
        try: stage.rename(out)
        except OSError:
            if old.exists(): old.rename(out)
            raise

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--overlay", type=Path)
    build(parser.parse_args().overlay)
