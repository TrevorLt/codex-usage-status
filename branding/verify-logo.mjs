#!/usr/bin/env node

import { createRequire } from "node:module";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const sharp = require(
  "/Users/trevor_lin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp",
);

const brandingDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryDirectory = dirname(brandingDirectory);
const validationDirectory = join(brandingDirectory, "validation");
const geometry = JSON.parse(
  await readFile(join(brandingDirectory, "logo-1b-m-geometry.json"), "utf8"),
);
const referenceArgument = process.argv[2];
const referencePath = referenceArgument
  ? resolve(referenceArgument)
  : resolve(repositoryDirectory, geometry.reference.path);
const beforePath = process.argv[3] ?? join(brandingDirectory, "reference", "1b-m-before.png");
const darkSvgPath = join(brandingDirectory, "logo-1b-m-dark.svg");
const templateSvgPath = join(brandingDirectory, "logo-1b-m-template.svg");
const variantPaths = [
  templateSvgPath,
  darkSvgPath,
  join(brandingDirectory, "logo-1b-m-light.svg"),
  join(brandingDirectory, "logo-1b-m-app-icon.svg"),
];
const threshold = geometry.reference.luminanceThreshold;
const metricSize = 256;

await mkdir(validationDirectory, { recursive: true });

const referenceMetadata = await sharp(referencePath).metadata();
const referenceWidth = referenceMetadata.width;
const referenceHeight = referenceMetadata.height;
if (!referenceWidth || !referenceHeight) {
  throw new Error(`Could not read reference dimensions from ${referencePath}`);
}

const darkSvg = await readFile(darkSvgPath);
const fixedAtReferenceSize = await sharp(darkSvg)
  .resize(referenceWidth, referenceHeight, { fit: "fill" })
  .flatten({ background: "#FFFFFF" })
  .png()
  .toBuffer();
await writeFile(
  join(validationDirectory, "fixed-render-1254.png"),
  fixedAtReferenceSize,
);

async function grayscaleBuffer(input, width, height) {
  return sharp(input)
    .resize(width, height, { fit: "fill", kernel: "lanczos3" })
    .flatten({ background: "#FFFFFF" })
    .greyscale()
    .raw()
    .toBuffer();
}

function componentCount(mask, width, height) {
  const seen = new Uint8Array(mask.length);
  const components = [];
  for (let index = 0; index < mask.length; index += 1) {
    if (!mask[index] || seen[index]) continue;
    const queue = [index];
    let cursor = 0;
    let pixels = 0;
    let minX = width;
    let minY = height;
    let maxX = 0;
    let maxY = 0;
    seen[index] = 1;
    while (cursor < queue.length) {
      const current = queue[cursor];
      cursor += 1;
      const x = current % width;
      const y = Math.floor(current / width);
      pixels += 1;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
      const neighbors = [current - 1, current + 1, current - width, current + width];
      for (const neighbor of neighbors) {
        if (neighbor < 0 || neighbor >= mask.length || seen[neighbor] || !mask[neighbor]) {
          continue;
        }
        const neighborX = neighbor % width;
        if (Math.abs(neighborX - x) > 1) continue;
        seen[neighbor] = 1;
        queue.push(neighbor);
      }
    }
    if (pixels >= 4) {
      components.push({ pixels, bounds: [minX, minY, maxX, maxY] });
    }
  }
  return components.sort((left, right) => right.pixels - left.pixels);
}

async function compareToReference(candidateInput) {
  const [referenceGray, candidateGray] = await Promise.all([
    grayscaleBuffer(referencePath, metricSize, metricSize),
    grayscaleBuffer(candidateInput, metricSize, metricSize),
  ]);
  let intersection = 0;
  let union = 0;
  let referenceArea = 0;
  let candidateArea = 0;
  let xor = 0;
  let absoluteDifference = 0;
  const referenceMask = new Uint8Array(referenceGray.length);
  const candidateMask = new Uint8Array(candidateGray.length);

  for (let index = 0; index < referenceGray.length; index += 1) {
    const referenceInside = referenceGray[index] < threshold;
    const candidateInside = candidateGray[index] < threshold;
    referenceMask[index] = Number(referenceInside);
    candidateMask[index] = Number(candidateInside);
    referenceArea += Number(referenceInside);
    candidateArea += Number(candidateInside);
    intersection += Number(referenceInside && candidateInside);
    union += Number(referenceInside || candidateInside);
    xor += Number(referenceInside !== candidateInside);
    absoluteDifference += Math.abs(referenceGray[index] - candidateGray[index]);
  }

  return {
    binarySilhouetteIoU: intersection / union,
    binarySilhouetteDifferenceOverUnion: xor / union,
    grayscaleMeanAbsoluteError: absoluteDifference / (255 * referenceGray.length),
    referenceForegroundPixels: referenceArea,
    candidateForegroundPixels: candidateArea,
    connectedComponents: componentCount(candidateMask, metricSize, metricSize),
  };
}

function extractGeometry(svgText) {
  const transform = svgText.match(/<g\s+transform="([^"]+)"\s+fill="[^"]+">/)?.[1];
  const paths = [...svgText.matchAll(/<path\s+d="([^"]+)"\s*\/>/g)].map(
    ([, pathData]) => pathData,
  );
  return { transform, paths };
}

const variantGeometry = {};
for (const variantPath of variantPaths) {
  const svgText = await readFile(variantPath, "utf8");
  variantGeometry[variantPath.split("/").at(-1)] = extractGeometry(svgText);
  await sharp(Buffer.from(svgText)).png().toBuffer();
  if (/stroke-dasharray|<circle\b|<image\b/.test(svgText)) {
    throw new Error(`${variantPath} contains forbidden dasharray, circle, or embedded image geometry`);
  }
}

const geometrySignatures = Object.values(variantGeometry).map((value) => JSON.stringify(value));
if (new Set(geometrySignatures).size !== 1) {
  throw new Error("The four SVG variants do not share identical path geometry");
}

const [templateAlpha, darkAlpha, lightAlpha] = await Promise.all(
  variantPaths.slice(0, 3).map(async (variantPath) => {
    const { data, info } = await sharp(await readFile(variantPath))
      .ensureAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });
    const alpha = Buffer.alloc(info.width * info.height);
    for (let pixel = 0; pixel < alpha.length; pixel += 1) alpha[pixel] = data[pixel * 4 + 3];
    return alpha;
  }),
);
if (!templateAlpha.equals(darkAlpha) || !templateAlpha.equals(lightAlpha)) {
  throw new Error("Transparent template, dark, and light variants do not render the same alpha mask");
}

const fixedMetrics = await compareToReference(fixedAtReferenceSize);
const beforeMetrics = await compareToReference(beforePath);
const [referenceSourceGray, fixedSourceGray] = await Promise.all([
  grayscaleBuffer(referencePath, referenceWidth, referenceHeight),
  grayscaleBuffer(fixedAtReferenceSize, referenceWidth, referenceHeight),
]);
let sourceIntersection = 0;
let sourceUnion = 0;
let sourceDifferentPixels = 0;
let sourceReferenceForegroundPixels = 0;
let sourceCandidateForegroundPixels = 0;
for (let index = 0; index < referenceSourceGray.length; index += 1) {
  const referenceInside = referenceSourceGray[index] < threshold;
  const candidateInside = fixedSourceGray[index] < threshold;
  sourceReferenceForegroundPixels += Number(referenceInside);
  sourceCandidateForegroundPixels += Number(candidateInside);
  sourceIntersection += Number(referenceInside && candidateInside);
  sourceUnion += Number(referenceInside || candidateInside);
  sourceDifferentPixels += Number(referenceInside !== candidateInside);
}
if (sourceDifferentPixels !== 0) {
  throw new Error(
    `Source-size thresholded silhouettes differ at ${sourceDifferentPixels} pixels`,
  );
}
const sourceSizeSilhouetteMetrics = {
  size: [referenceWidth, referenceHeight],
  luminanceThreshold: threshold,
  binarySilhouetteIoU: sourceIntersection / sourceUnion,
  differentMaskPixels: sourceDifferentPixels,
  referenceForegroundPixels: sourceReferenceForegroundPixels,
  candidateForegroundPixels: sourceCandidateForegroundPixels,
};

const labelHeight = 54;
const labelSvg = Buffer.from(`
  <svg xmlns="http://www.w3.org/2000/svg" width="${referenceWidth * 2}" height="${labelHeight}">
    <rect width="100%" height="100%" fill="#F5F7FA" />
    <text x="24" y="35" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="24" font-weight="600" fill="#1F2329">Reference PNG</text>
    <text x="${referenceWidth + 24}" y="35" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="24" font-weight="600" fill="#1F2329">Fixed explicit-path SVG</text>
  </svg>
`);
await sharp({
  create: {
    width: referenceWidth * 2,
    height: referenceHeight + labelHeight,
    channels: 4,
    background: "#FFFFFF",
  },
})
  .composite([
    { input: labelSvg, left: 0, top: 0 },
    { input: referencePath, left: 0, top: labelHeight },
    { input: fixedAtReferenceSize, left: referenceWidth, top: labelHeight },
  ])
  .png()
  .toFile(join(validationDirectory, "reference-vs-fixed.png"));

const beforeAtReferenceSize = await sharp(beforePath)
  .resize(referenceWidth, referenceHeight, { fit: "fill", kernel: "lanczos3" })
  .png()
  .toBuffer();
const triptychLabel = Buffer.from(`
  <svg xmlns="http://www.w3.org/2000/svg" width="${referenceWidth * 3}" height="${labelHeight}">
    <rect width="100%" height="100%" fill="#F5F7FA" />
    <g font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="24" font-weight="600" fill="#1F2329">
      <text x="24" y="35">Reference</text>
      <text x="${referenceWidth + 24}" y="35">Before</text>
      <text x="${referenceWidth * 2 + 24}" y="35">Fixed</text>
    </g>
  </svg>
`);
await sharp({
  create: {
    width: referenceWidth * 3,
    height: referenceHeight + labelHeight,
    channels: 4,
    background: "#FFFFFF",
  },
})
  .composite([
    { input: triptychLabel, left: 0, top: 0 },
    { input: referencePath, left: 0, top: labelHeight },
    { input: beforeAtReferenceSize, left: referenceWidth, top: labelHeight },
    { input: fixedAtReferenceSize, left: referenceWidth * 2, top: labelHeight },
  ])
  .png()
  .toFile(join(validationDirectory, "reference-before-fixed.png"));

const [referenceLargeGray, fixedLargeGray] = await Promise.all([
  grayscaleBuffer(referencePath, referenceWidth, referenceHeight),
  grayscaleBuffer(fixedAtReferenceSize, referenceWidth, referenceHeight),
]);
const overlayPixels = Buffer.alloc(referenceWidth * referenceHeight * 4);
for (let index = 0; index < referenceLargeGray.length; index += 1) {
  const referenceInside = referenceLargeGray[index] < threshold;
  const fixedInside = fixedLargeGray[index] < threshold;
  const color = referenceInside && fixedInside
    ? [31, 35, 41]
    : referenceInside
      ? [226, 66, 102]
      : fixedInside
        ? [47, 156, 244]
        : [255, 255, 255];
  overlayPixels[index * 4] = color[0];
  overlayPixels[index * 4 + 1] = color[1];
  overlayPixels[index * 4 + 2] = color[2];
  overlayPixels[index * 4 + 3] = 255;
}
const legendHeight = 58;
const overlayLegend = Buffer.from(`
  <svg xmlns="http://www.w3.org/2000/svg" width="${referenceWidth}" height="${legendHeight}">
    <rect width="100%" height="100%" fill="#F5F7FA" />
    <g font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="21" fill="#1F2329">
      <rect x="24" y="18" width="22" height="22" rx="4" fill="#1F2329"/><text x="56" y="36">overlap</text>
      <rect x="190" y="18" width="22" height="22" rx="4" fill="#E24266"/><text x="222" y="36">reference only</text>
      <rect x="405" y="18" width="22" height="22" rx="4" fill="#2F9CF4"/><text x="437" y="36">fixed only</text>
    </g>
  </svg>
`);
const overlayBody = await sharp(overlayPixels, {
  raw: { width: referenceWidth, height: referenceHeight, channels: 4 },
})
  .png()
  .toBuffer();
await sharp({
  create: {
    width: referenceWidth,
    height: referenceHeight + legendHeight,
    channels: 4,
    background: "#FFFFFF",
  },
})
  .composite([
    { input: overlayLegend, left: 0, top: 0 },
    { input: overlayBody, left: 0, top: legendHeight },
  ])
  .png()
  .toFile(join(validationDirectory, "overlay.png"));

const previewSizes = [16, 22, 32, 128];
const templateSvg = await readFile(templateSvgPath);
const previewBuffers = new Map();
for (const previewSize of previewSizes) {
  const preview = await sharp(templateSvg)
    .resize(previewSize, previewSize, { fit: "fill" })
    .png()
    .toBuffer();
  previewBuffers.set(previewSize, preview);
  await writeFile(join(validationDirectory, `preview-${previewSize}.png`), preview);
}

const previewCellWidth = 210;
const previewSheetHeight = 250;
const previewLabels = Buffer.from(`
  <svg xmlns="http://www.w3.org/2000/svg" width="${previewCellWidth * previewSizes.length}" height="${previewSheetHeight}">
    <rect width="100%" height="100%" fill="#FFFFFF" />
    <g font-family="-apple-system, BlinkMacSystemFont, sans-serif" text-anchor="middle" fill="#1F2329">
      ${previewSizes
        .map(
          (previewSize, index) =>
            `<text x="${index * previewCellWidth + previewCellWidth / 2}" y="226" font-size="20" font-weight="600">${previewSize} px native</text>`,
        )
        .join("")}
    </g>
  </svg>
`);
await sharp(previewLabels)
  .composite(
    previewSizes.map((previewSize, index) => ({
      input: previewBuffers.get(previewSize),
      left: Math.round(index * previewCellWidth + (previewCellWidth - previewSize) / 2),
      top: Math.round((200 - previewSize) / 2),
    })),
  )
  .png()
  .toFile(join(validationDirectory, "small-size-previews.png"));

await sharp(await readFile(join(brandingDirectory, "logo-1b-m-app-icon.svg")))
  .resize(256, 256, { fit: "fill" })
  .png()
  .toFile(join(validationDirectory, "app-icon-256.png"));

const metrics = {
  generatedAt: new Date().toISOString(),
  reference: referenceArgument ?? geometry.reference.path,
  before: beforePath,
  comparisonSize: [metricSize, metricSize],
  luminanceThreshold: threshold,
  sourceSizeSilhouette: sourceSizeSilhouetteMetrics,
  fixed: fixedMetrics,
  beforeMetrics,
  improvement: {
    absoluteIoUGain:
      fixedMetrics.binarySilhouetteIoU - beforeMetrics.binarySilhouetteIoU,
    relativeGrayscaleMaeReduction:
      1 - fixedMetrics.grayscaleMeanAbsoluteError / beforeMetrics.grayscaleMeanAbsoluteError,
  },
  checks: {
    sharpRenderedAllVariants: true,
    explicitPathsOnly: true,
    identicalGeometryAcrossFourVariants: true,
    matchingTransparentAlphaAcrossTemplateDarkLight: true,
    pathCountPerVariant: variantGeometry["logo-1b-m-template.svg"].paths.length,
  },
};
await writeFile(
  join(validationDirectory, "metrics.json"),
  `${JSON.stringify(metrics, null, 2)}\n`,
);

console.log(JSON.stringify(metrics, null, 2));
