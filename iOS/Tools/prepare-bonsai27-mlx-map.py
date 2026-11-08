#!/usr/bin/env python3
"""Regenerate the iOS language-only range map from Prism's original pinned 27B MLX weights.

Usage: python3 Tools/prepare-bonsai27-mlx-map.py /path/to/official/model.safetensors
Pass '-' to stream the official checkpoint over stdin. Nothing is written unless the
complete original checkpoint has the expected SHA-256.
"""
import argparse
import base64
from contextlib import nullcontext
import hashlib
from itertools import groupby
import json
from pathlib import Path
import struct
import sys
from tempfile import NamedTemporaryFile

ORIGINAL_SHA = "130de5925082c168b7866b2e91b52e44abbafc99017e3ca352b77b5b55a269ed"
ORIGINAL_SIZE = 8_595_477_990

def build(stream):
    prefix = stream.read(8)
    if len(prefix) != 8:
        raise ValueError("Missing safetensors header length")
    header_size, = struct.unpack("<Q", prefix)
    if header_size > 4 << 20:
        raise ValueError("Unexpected safetensors header size")
    original_header = stream.read(header_size)
    header = json.loads(original_header)
    tensors = sorted((*spec["data_offsets"], name) for name, spec in header.items() if name != "__metadata__")
    text = {"__metadata__": header["__metadata__"]}
    spans = []
    text_position = 0
    for keep, entries in groupby(tensors, key=lambda row: row[2].startswith("language_model.")):
        segment = list(entries)
        if not keep:
            continue
        spans.append({"start": 8 + header_size + segment[0][0], "length": segment[-1][1] - segment[0][0]})
        for begin, end, name in segment:
            text[name] = dict(header[name], data_offsets=[text_position, text_position + end - begin])
            text_position += end - begin
    encoded = json.dumps(text, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 8)
    output_header = struct.pack("<Q", len(encoded)) + encoded
    original_check = hashlib.sha256(prefix + original_header)
    output_check = hashlib.sha256(output_header)
    position = 8 + header_size
    index = 0
    while block := stream.read(4 << 20):
        original_check.update(block)
        end = position + len(block)
        while index < len(spans):
            start = spans[index]["start"]
            if start >= end:
                break
            stop = start + spans[index]["length"]
            output_check.update(memoryview(block)[max(start - position, 0):min(stop - position, len(block))])
            if stop > end:
                break
            index += 1
        position = end
    if position != ORIGINAL_SIZE or original_check.hexdigest() != ORIGINAL_SHA or index != len(spans):
        raise ValueError("Unexpected official model bytes")
    return {"header": base64.b64encode(output_header).decode(), "ranges": spans,
            "fileBytes": len(output_header) + text_position, "sha256": output_check.hexdigest()}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model")
    default = Path(__file__).resolve().parents[1] / "HarnessMiku/Stage/bonsai-27b-text.json"
    parser.add_argument("--output", type=Path, default=default)
    args = parser.parse_args()
    source = nullcontext(sys.stdin.buffer) if args.model == "-" else Path(args.model).open("rb")
    with source as stream:
        output = build(stream)
    with NamedTemporaryFile(mode="w", dir=args.output.parent, delete=False) as target:
        json.dump(output, target, separators=(",", ":"))
        target.write("\n")
    Path(target.name).replace(args.output)
    print(f'{output["fileBytes"]:,} bytes; SHA-256 {output["sha256"]}')

if __name__ == "__main__":
    main()
