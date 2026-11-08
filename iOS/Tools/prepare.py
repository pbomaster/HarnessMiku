"""Assemble only the verified local artwork and the Mac port's renderer."""
import argparse, hashlib, json, os, shutil, subprocess, sys, tempfile, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "RetrynowMiku/VTS Model File/"
REV = "96544431322d3f2cde1ec42db156c8b8eee5e6fd"
ARCHIVE_HASH = "e050dec33e0d7ef81e8efa3fcc349822742a60786740cfa18e69255a59eb85b2"
PATCHED_RENDERER_HASH = "142116486b7e025836a3a7cf3ea0c6c5a0cdd1e0869b219f2a0b8d7daf5918ae"
VENDOR = "deepseek-harness-kr-"+REV+"/harness/overlay/dsh/node_modules/@deepseek-ai/dsh-web-frontend/dist/assets/dsc/vendor/"

def build(model, overlay):
    hashes = json.loads((ROOT/"Tools/model-hashes.json").read_text())
    out = ROOT/"HarnessMiku/Stage/Private"
    with tempfile.TemporaryDirectory(dir=ROOT) as temp:
        stage = Path(temp)/"Private"
        stage.mkdir()
        if overlay is None:
            overlay = Path(temp)/"upstream.zip"
            subprocess.run(["curl","--fail","--location","--retry","2","--output",str(overlay),
                            "https://codeload.github.com/noire113-dev/deepseek-harness-kr/zip/"+REV],check=True)
        if hashlib.sha256(Path(overlay).read_bytes()).hexdigest()!=ARCHIVE_HASH:
            raise ValueError("렌더러 배포 파일의 SHA-256이 일치하지 않습니다.")
        with zipfile.ZipFile(overlay) as z:
            for name in ["pixi.min.js","live2dcubismcore.min.js","cubism4.patched.js"]:
                (stage/name).write_bytes(z.read(VENDOR+name))
            for name in ["LICENSE","NOTICE.md"]:
                (stage/name).write_bytes(z.read("deepseek-harness-kr-"+REV+"/"+name))
        # Apply PR7 inside the staging directory so a failed patch leaves the last build intact.
        subprocess.run(["patch", "-F", "0", "-p0", "-i", str(ROOT/"Tools/pr7-gpu.patch")],
                       cwd=stage, stdin=subprocess.DEVNULL, check=True)
        if hashlib.sha256((stage/"cubism4.patched.js").read_bytes()).hexdigest() != PATCHED_RENDERER_HASH:
            raise ValueError("PR7 적용 후 렌더러의 SHA-256이 일치하지 않습니다.")
        with zipfile.ZipFile(model) as z:
            for name,digest in hashes.items():
                entry = z.getinfo(PREFIX+name)
                if entry.file_size>16*1024**2:raise ValueError("모델 파일 크기 오류")
                data = z.read(entry)
                if hashlib.sha256(data).hexdigest()!=digest:raise ValueError("지원하지 않는 모델 파일: "+name)
                dest=stage/"miku"/name
                dest.parent.mkdir(parents=True,exist_ok=True)
                dest.write_bytes(data)
                if name.startswith("RetrynowMiku.4096/"):
                    # Keep the creator ZIP untouched. Reduce the local device's GPU allocation.
                    if sys.platform=="darwin":
                        subprocess.run(["/usr/bin/sips","-Z","1024",str(dest)],stdout=subprocess.DEVNULL,check=True)
                    else:
                        from PIL import Image
                        with Image.open(dest) as im:
                            im.resize((1024,1024),Image.Resampling.LANCZOS).save(dest)
        # Preserve the optional neutral frame rendered from this verified model.
        # Fresh source-only setups use the official artwork thumbnail as a fallback.
        preview = out / "miku-framing.png"
        if preview.is_file() and hashlib.sha256(preview.read_bytes()).hexdigest() == "f5bedf4d0e2be56e8d8942351012504b0e35b8b93fbb0685a9d90309af3204f2":
            shutil.copyfile(preview, stage / preview.name)
        backup=Path(temp)/"previous"
        if out.exists():out.rename(backup)
        try:stage.rename(out)
        except OSError:
            if backup.exists():backup.rename(out)
            raise

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("model",type=Path);p.add_argument("--overlay",type=Path)
    args=p.parse_args();build(args.model,args.overlay)
