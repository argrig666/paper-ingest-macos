#!/usr/bin/env python3
"""Capture paper and emit a lossless image plus structured OCR JSON."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_stem", type=Path)
    parser.add_argument("--camera", default="IPEVO V4K")
    parser.add_argument("--exposures", default="96,192,384,768,1280,2047")
    args = parser.parse_args()

    stem = args.output_stem.expanduser().resolve()
    stem.parent.mkdir(parents=True, exist_ok=True)
    image = stem.with_suffix(".png")
    document = stem.with_suffix(".json")

    subprocess.run([
        str(ROOT / "scripts" / "optimized_capture.py"), str(image),
        "--camera", args.camera, "--exposures", args.exposures,
    ], check=True)
    subprocess.run([
        str(ROOT / "bin" / "vision-ocr"), str(image), str(document),
    ], check=True)
    print(document)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
