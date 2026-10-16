# CodexUsageStatus 1B-M logo

The selected 1B-M mark is restored from the approved 1254×1254 reference PNG. The outer channel has exactly three components—a long left arc, a short upper-right arc, and a lower-right arc—and the inner channel is one long arc with its opening on the upper-right side.

## Source and measurement

- Reference: `branding/reference/1b-m.png` (approved 1254×1254 source PNG).
- Before-fix render: `branding/reference/1b-m-before.png` (preserved 768×768 baseline). The default comparison no longer depends on a temporary file.
- The scripts use this repository-contained image by default. Pass a different image as the first positional argument to use an external reference.
- Reference size: 1254×1254 pixels.
- Silhouette extraction: luminance `< 128`.
- Contour simplification: Ramer-Douglas-Peucker at 0.35 source pixel.
- Final geometry: four closed contours, 5,982 points after simplification, stored as one compact relative-coordinate SVG path with four subpaths.
- Normalization: source-coordinate contours are scaled by `256 / 1254` inside a shared `viewBox="0 0 256 256"`.

The earlier concentric-circle fit reached only 95.295% silhouette IoU at 256px and is retained in `logo-1b-m-geometry.json` as a measurement draft only. The shipped SVGs use the traced contour, including the reference's slight line-width and curvature irregularities.

## Measured fidelity

`verify-logo.mjs` independently rasterizes the SVG through Sharp and compares its silhouette with the reference using luminance `< 128`:

- At the original 1254×1254 size, both binary masks contain 312,645 foreground pixels; the intersection and union are both 312,645, so the masks differ at 0 pixels and have IoU **1.0**. The SVG is flattened onto white before thresholding.
- At 256×256, the normalized/resampled comparison gives binary silhouette IoU **0.997682** (99.768%) and normalized grayscale mean absolute error **0.007999** (0.800%).
- Old baseline at 256×256: binary silhouette IoU **0.222533** (22.253%) and normalized grayscale mean absolute error **0.355095** (35.509%); connected components: final 4, old baseline 3.

The 1254px result is an exact match of the thresholded binary silhouette only. It does not claim RGB pixel identity: the reference has soft shading and raster antialiasing, while the SVG uses flat fills. The 256px comparison remains useful for judging normalized rendering quality; the exact native-size mask match is reported separately.

## Variants

- `logo-1b-m-template.svg`: black mark on a transparent canvas for macOS template-image rendering.
- `logo-1b-m-dark.svg`: `#1F2329` mark on a transparent canvas for light backgrounds.
- `logo-1b-m-light.svg`: white mark on a transparent canvas for dark backgrounds.
- `logo-1b-m-app-icon.svg`: the identical white contour over a `#1F2329` rounded square (`x=14`, `y=14`, `width=228`, `height=228`, `rx=54`). The area outside the rounded square remains transparent.
- `CodexUsageStatus.icns`: the packaged macOS app icon generated from the app-icon artwork at the standard 16–1024 px retina sizes. The build script copies it into `Contents/Resources` and declares it through `CFBundleIconFile`.

All four files use the same path data and source-to-viewBox transform. No variant contains `stroke-dasharray`, `<circle>`, an embedded bitmap, or variant-specific geometry. The template, dark, and light variants also render to the same alpha mask.

The menu-bar implementation should use the template variant and let AppKit tint it for the surrounding status-bar appearance. At 16px, the four-component structure remains visible, but the smallest raster naturally loses some of the source's subpixel edge irregularity.

## Reproducible validation

The scripts use the already-provided Sharp runtime and install no dependencies:

```sh
node branding/trace-logo-contours.mjs --summary
node branding/verify-logo.mjs
```

Generated evidence is under `branding/validation/`:

- `metrics.json`: before/final metrics and structural checks.
- `reference-vs-fixed.png`: full reference and fixed render side by side.
- `reference-before-fixed.png`: reference, old baseline, and fixed render.
- `overlay.png`: overlap in charcoal, reference-only pixels in magenta, fixed-only pixels in blue.
- `preview-16.png`, `preview-22.png`, `preview-32.png`, and `preview-128.png`: native-size transparent previews.
- `small-size-previews.png`: labeled preview sheet.
- `app-icon-256.png`: app-icon render with the documented background.

This is a project-specific mark for CodexUsageStatus. It is not an OpenAI logo or an OpenAI mark.
