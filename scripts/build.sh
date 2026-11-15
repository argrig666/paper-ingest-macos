#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$ROOT/bin" "$ROOT/third_party"

if [ ! -d "$ROOT/third_party/uvc-util/.git" ]; then
  git clone --depth 1 https://github.com/jtfrey/uvc-util.git "$ROOT/third_party/uvc-util"
fi

swiftc "$ROOT/Sources/camera_capture.swift" -o "$ROOT/bin/camera-capture" -framework AVFoundation -framework CoreImage
swiftc "$ROOT/Sources/image_text_score.swift" -o "$ROOT/bin/image-text-score" -framework CoreGraphics -framework ImageIO
swiftc "$ROOT/Sources/vision_ocr.swift" -o "$ROOT/bin/vision-ocr" -framework Vision -framework ImageIO
clang -o "$ROOT/bin/uvc-util" \
  "$ROOT/third_party/uvc-util/src/uvc-util.m" \
  "$ROOT/third_party/uvc-util/src/UVCController.m" \
  "$ROOT/third_party/uvc-util/src/UVCType.m" \
  "$ROOT/third_party/uvc-util/src/UVCValue.m" \
  -framework IOKit -framework Foundation

echo "Built tools in $ROOT/bin"
