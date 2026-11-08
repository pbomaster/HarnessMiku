"""Build the private iPhone voice pack. Requires Python 3, Node.js and npm."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

VOICE = "https://huggingface.co/aple/HatsuneMikuRVC/resolve/781194746498a5f997a7135541531a915358fdcd/miku_default_rvc.zip"
ENCODER = "https://huggingface.co/wok000/weights_gpl/resolve/main/content-vec/contentvec-f.onnx"
ARCHIVE_HASH = "0bcd99747c895e3bb5c22a78a106947f81aa1dcb91bea33df9274df1f11a2e1a"
ENCODER_HASH = "4b31ed3d95a568fab7952de923ff7f7d3d17128ea6fce69f665509d24c3156db"
VOICE_HASH = "224ac677dc8bb43dd066a2231c92415e829f402b729de44be845c0b2e4cf38e3"
CREDITS = """Voice conversion checkpoint by aple / 3939_dancer.
Original release and model card: https://huggingface.co/aple/HatsuneMikuRVC
miku_default_rvc converted to ONNX with rvc-onnx-web 1.0.0.
ContentVec ONNX supplied unchanged from https://huggingface.co/wok000/weights_gpl
See upstream repositories for sources, model terms, and attribution.
"""

def verify(path, expected):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise ValueError("Checksum mismatch: " + path.name)

def prepare(output, source, encoder):
    output = output.resolve()
    if output.exists():
        raise FileExistsError(output)
    with tempfile.TemporaryDirectory(dir=output.parent) as directory:
        work = Path(directory)
        def fetch(local, url, name, checksum):
            if local is None:
                local = work / name
                subprocess.run(["curl", "-fLsS", "--retry", "2", "-o", str(local), url], check=True)
            verify(local, checksum)
            return local
        source = fetch(source, VOICE, "source.zip", ARCHIVE_HASH)
        encoder = fetch(encoder, ENCODER, "contentvec.onnx", ENCODER_HASH)
        with zipfile.ZipFile(source) as archive, archive.open("miku_default_rvc/weights/miku_default_rvc.pth") as weights:
            with (work / "miku.pth").open("wb") as dest:
                shutil.copyfileobj(weights, dest)
        subprocess.run(["npm", "install", "--ignore-scripts", "--no-audit", "--no-fund", "rvc-onnx-web@1.0.0", "esbuild@0.25.12"], cwd=work, check=True)
        (work / "convert.mjs").write_text("""
import {pthToOnnx} from 'rvc-onnx-web';
import fs from 'node:fs';
async function run() {
    const result = await pthToOnnx(fs.readFileSync('miku.pth'), {opsetVersion:17});
    if (result.sampleRate !== 40000) throw Error('Unexpected sample rate');
    fs.writeFileSync('miku.onnx', Buffer.from(result.onnxBuffer));
}
run().catch(e => { console.error(e); process.exitCode = 1; });
""")
        subprocess.run([str(work/"node_modules/.bin/esbuild"),"convert.mjs","--bundle","--platform=node","--format=cjs","--outfile=convert.cjs"], cwd=work, check=True)
        subprocess.run(["node","convert.cjs"], cwd=work, check=True)
        verify(work/"miku.onnx", VOICE_HASH)
        pack = work/"voice.zip"
        with zipfile.ZipFile(pack,"w",zipfile.ZIP_DEFLATED,compresslevel=1) as archive:
            archive.write(work/"miku.onnx","miku.onnx")
            archive.write(encoder,"contentvec.onnx")
            archive.writestr("CREDITS.txt", CREDITS)
        pack.rename(output)

if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("output",type=Path)
    cli.add_argument("--source",type=Path)
    cli.add_argument("--encoder",type=Path)
    args = cli.parse_args()
    prepare(args.output, args.source, args.encoder)
