#!/usr/bin/env python3
"""Bracket IPEVO hardware exposure and keep the frame best suited to text extraction."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "bin"
UVC = BIN / "uvc-util"
CAPTURE = BIN / "camera-capture"
SCORER = BIN / "image-text-score"


def run(arguments: list[str], *, capture_output: bool = True) -> str:
    result = subprocess.run(
        arguments,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture_output else subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip() if capture_output else ""


def set_control(camera: str, name: str, value: str | int) -> None:
    run(
        [
            str(UVC),
            f"--select-by-name={camera}",
            f"--set={name}={value}",
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--camera", default="IPEVO V4K")
    parser.add_argument(
        "--exposures",
        default="96,192,384,768,1280,2047",
        help="Comma-separated UVC absolute exposure values",
    )
    args = parser.parse_args()

    exposures = [int(value) for value in args.exposures.split(",")]
    output = args.output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    # Neutral, repeatable camera state. White balance and focus remain automatic;
    # exposure is bracketed because macOS otherwise overexposes white pages.
    neutral_controls = {
        "backlight-compensation": 0,
        "brightness": 0,
        "contrast": 0,
        "gamma": 100,
        "saturation": 25,
        "sharpness": 2,
        "auto-white-balance-temp": "true",
        "auto-focus": "true",
        "auto-exposure-mode": 1,
    }
    for name, value in neutral_controls.items():
        set_control(args.camera, name, value)

    candidates: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="paper-ingest-") as temporary:
        temporary_path = Path(temporary)
        for exposure in exposures:
            set_control(args.camera, "exposure-time-abs", exposure)
            image_path = temporary_path / f"exposure-{exposure}.png"
            run([str(CAPTURE), str(image_path), "0.8", args.camera])
            metrics = json.loads(run([str(SCORER), str(image_path)]))
            candidates.append(
                {
                    "exposure": exposure,
                    "image": str(image_path),
                    "metrics": metrics,
                }
            )

        selected = max(candidates, key=lambda item: item["metrics"]["score"])
        shutil.copyfile(selected["image"], output)
        set_control(args.camera, "exposure-time-abs", selected["exposure"])

    metrics = selected["metrics"]
    quality_status = "usable"
    reasons: list[str] = []
    if metrics["highlightClip"] > 0.03:
        quality_status = "review"
        reasons.append("highlight_clipping")
    if metrics["meanGradient"] < 3.0:
        quality_status = "review"
        reasons.append("low_detail")

    manifest = {
        "schemaVersion": "paper-ingest-capture/0.1",
        "output": str(output),
        "camera": args.camera,
        "captureMode": {
            "width": 3264,
            "height": 2448,
            "pixelFormat": "YUV 4:2:2",
            "encoding": "lossless PNG",
        },
        "controls": neutral_controls,
        "selectedExposure": selected["exposure"],
        "quality": {
            "status": quality_status,
            "reasons": reasons,
            **metrics,
        },
        "candidates": [
            {"exposure": item["exposure"], "metrics": item["metrics"]}
            for item in candidates
        ],
    }
    manifest_path = output.with_suffix(".capture.json")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
