# Paper Ingest for macOS

A silent command-line pipeline that turns a USB document-camera view into:

1. a maximum-resolution, lossless PNG;
2. a capture manifest with exposure candidates and quality measurements; and
3. structured OCR JSON with regions, bounding boxes, alternative readings, and confidence.

It was developed and tested with an IPEVO V4K (3264×2448 YUV 4:2:2), but the camera name is configurable. It uses native macOS AVFoundation, Core Image, and Vision APIs. No Photo Booth or other visible capture application is opened.

## Why exposure is bracketed

Automatic exposure commonly washes out white pages and faint pencil. The capture stage applies neutral UVC image controls, captures a bracket of hardware exposures, scores each frame for a bright-but-unclipped page and retained stroke detail, and preserves the best full-resolution frame. Automatic focus and white balance remain enabled.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools
- Python 3.10+
- a UVC-compatible USB camera
- camera permission for the calling terminal or agent

## Build

```sh
./scripts/build.sh
```

The build downloads [jtfrey/uvc-util](https://github.com/jtfrey/uvc-util), an MIT-licensed macOS UVC control utility, and builds all native helpers locally.

## Run

```sh
./scripts/paper_ingest.py ~/Desktop/page
```

For another camera:

```sh
./scripts/paper_ingest.py ~/Desktop/page --camera "USB Camera Name"
```

Outputs:

- `page.png` — selected lossless source image
- `page.capture.json` — capture settings, quality metrics, and bracket scores
- `page.json` — OCR regions with normalized bounding boxes and up to three candidates

The OCR document is deliberately model-neutral. A downstream agent can consult the source image, preserve uncertainty, interpret layout, or normalize language without losing the raw readings.

## Current limits

- UVC control names and the default exposure bracket are tuned for the IPEVO V4K. Other cameras may expose different controls or ranges.
- Vision confidence is evidence, not ground truth, especially for handwriting.
- Page detection, perspective rectification, and orientation inference are not yet automatic.
- This is a macOS implementation. The output schemas are portable; capture and OCR backends are not.

## Privacy

Capture, scoring, and OCR run locally. The pipeline does not upload images or recognized text.

## License

MIT. The separately downloaded `uvc-util` dependency retains its own MIT license and copyright.
