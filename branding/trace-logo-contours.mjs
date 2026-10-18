#!/usr/bin/env node

import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const sharp = require(
  "/Users/trevor_lin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp",
);

const positionalArguments = process.argv.slice(2).filter((argument) => !argument.startsWith("--"));
const brandingDirectory = dirname(fileURLToPath(import.meta.url));
const referencePath =
  positionalArguments[0] ??
  join(brandingDirectory, "reference", "1b-m.png");
const threshold = 128;
const simplificationTolerance = 0.35;
const normalizedSize = 256;

const { data, info } = await sharp(referencePath)
  .removeAlpha()
  .greyscale()
  .raw()
  .toBuffer({ resolveWithObject: true });
const { width, height } = info;
const mask = new Uint8Array(width * height);
let referenceArea = 0;
for (let index = 0; index < mask.length; index += 1) {
  if (data[index] < threshold) {
    mask[index] = 1;
    referenceArea += 1;
  }
}

const key = (x, y) => `${x},${y}`;
const edgeMap = new Map();
function addEdge(startX, startY, endX, endY) {
  const startKey = key(startX, startY);
  const outgoing = edgeMap.get(startKey) ?? [];
  outgoing.push([endX, endY]);
  edgeMap.set(startKey, outgoing);
}
function isForeground(x, y) {
  return x >= 0 && x < width && y >= 0 && y < height && mask[y * width + x] === 1;
}

for (let y = 0; y < height; y += 1) {
  for (let x = 0; x < width; x += 1) {
    if (!isForeground(x, y)) continue;
    if (!isForeground(x, y - 1)) addEdge(x, y, x + 1, y);
    if (!isForeground(x + 1, y)) addEdge(x + 1, y, x + 1, y + 1);
    if (!isForeground(x, y + 1)) addEdge(x + 1, y + 1, x, y + 1);
    if (!isForeground(x - 1, y)) addEdge(x, y + 1, x, y);
  }
}

const loops = [];
while (edgeMap.size > 0) {
  const [startKey] = edgeMap.keys();
  const [startX, startY] = startKey.split(",").map(Number);
  const points = [[startX, startY]];
  let currentX = startX;
  let currentY = startY;
  do {
    const currentKey = key(currentX, currentY);
    const outgoing = edgeMap.get(currentKey);
    if (!outgoing?.length) {
      throw new Error(`Open contour at ${currentKey}`);
    }
    const [nextX, nextY] = outgoing.pop();
    if (outgoing.length === 0) edgeMap.delete(currentKey);
    currentX = nextX;
    currentY = nextY;
    points.push([currentX, currentY]);
  } while (currentX !== startX || currentY !== startY);
  loops.push(points);
}

function squaredDistance(left, right) {
  const dx = left[0] - right[0];
  const dy = left[1] - right[1];
  return dx * dx + dy * dy;
}

function perpendicularDistance(point, start, end) {
  const dx = end[0] - start[0];
  const dy = end[1] - start[1];
  if (dx === 0 && dy === 0) return Math.sqrt(squaredDistance(point, start));
  const numerator = Math.abs(
    dy * point[0] - dx * point[1] + end[0] * start[1] - end[1] * start[0],
  );
  return numerator / Math.hypot(dx, dy);
}

function simplifyOpen(points, tolerance) {
  if (points.length <= 2) return points;
  let maximumDistance = 0;
  let splitIndex = 0;
  for (let index = 1; index < points.length - 1; index += 1) {
    const distance = perpendicularDistance(points[index], points[0], points.at(-1));
    if (distance > maximumDistance) {
      maximumDistance = distance;
      splitIndex = index;
    }
  }
  if (maximumDistance <= tolerance) return [points[0], points.at(-1)];
  const left = simplifyOpen(points.slice(0, splitIndex + 1), tolerance);
  const right = simplifyOpen(points.slice(splitIndex), tolerance);
  return [...left.slice(0, -1), ...right];
}

function simplifyClosed(points, tolerance) {
  const ring = points.slice(0, -1);
  let oppositeIndex = 1;
  let maximumDistance = 0;
  for (let index = 1; index < ring.length; index += 1) {
    const distance = squaredDistance(ring[0], ring[index]);
    if (distance > maximumDistance) {
      maximumDistance = distance;
      oppositeIndex = index;
    }
  }
  const firstHalf = simplifyOpen(ring.slice(0, oppositeIndex + 1), tolerance);
  const secondHalf = simplifyOpen([...ring.slice(oppositeIndex), ring[0]], tolerance);
  return [...firstHalf.slice(0, -1), ...secondHalf.slice(0, -1)];
}

const significantLoops = loops
  .filter((loop) => loop.length >= 100)
  .sort((left, right) => right.length - left.length);
if (significantLoops.length !== 4) {
  throw new Error(`Expected four significant contours, found ${significantLoops.length}`);
}

function sourcePath(points) {
  return `M ${points.map(([x, y]) => `${x} ${y}`).join(" ")} Z`;
}
function normalizedPath(points) {
  const scaleX = normalizedSize / width;
  const scaleY = normalizedSize / height;
  const format = (value) => Number(value.toFixed(3)).toString();
  return `M ${points
    .map(([x, y]) => `${format(x * scaleX)} ${format(y * scaleY)}`)
    .join(" ")} Z`;
}
function compactRelativeSourcePath(points) {
  const [firstPoint, ...remainingPoints] = points;
  let previousPoint = firstPoint;
  const deltas = remainingPoints.map((point) => {
    const delta = `${point[0] - previousPoint[0]} ${point[1] - previousPoint[1]}`;
    previousPoint = point;
    return delta;
  });
  return `M ${firstPoint[0]} ${firstPoint[1]} l ${deltas.join(" ")} Z`;
}

const simplifiedLoops = significantLoops.map((loop) =>
  simplifyClosed(loop, simplificationTolerance),
);
const sourcePaths = simplifiedLoops.map(sourcePath);
const tracedSvg = Buffer.from(`
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}">
    <g fill="#000">${sourcePaths.map((pathData) => `<path d="${pathData}"/>`).join("")}</g>
  </svg>
`);
const tracedGray = await sharp(tracedSvg)
  .flatten({ background: "#FFFFFF" })
  .greyscale()
  .raw()
  .toBuffer();

let candidateArea = 0;
let intersection = 0;
let union = 0;
let xor = 0;
for (let index = 0; index < mask.length; index += 1) {
  const referenceInside = mask[index] === 1;
  const candidateInside = tracedGray[index] < threshold;
  candidateArea += Number(candidateInside);
  intersection += Number(referenceInside && candidateInside);
  union += Number(referenceInside || candidateInside);
  xor += Number(referenceInside !== candidateInside);
}

const result = {
  reference: referencePath,
  sourceSize: [width, height],
  normalizedSize,
  luminanceThreshold: threshold,
  simplificationToleranceSourcePixels: simplificationTolerance,
  contourCount: simplifiedLoops.length,
  pointsBeforeSimplification: significantLoops.map((loop) => loop.length - 1),
  pointsAfterSimplification: simplifiedLoops.map((loop) => loop.length),
  totalPointsAfterSimplification: simplifiedLoops.reduce((sum, loop) => sum + loop.length, 0),
  binarySilhouetteIoUAtSourceSize: intersection / union,
  binarySilhouetteDifferenceOverUnion: xor / union,
  referenceForegroundPixels: referenceArea,
  tracedForegroundPixels: candidateArea,
  normalizedPaths: simplifiedLoops.map(normalizedPath),
  compactRelativeSourcePath: simplifiedLoops.map(compactRelativeSourcePath).join(" "),
};

const output = process.argv.includes("--summary")
  ? {
      ...result,
      normalizedPaths: result.normalizedPaths.map((pathData) => `[${pathData.length} characters]`),
      compactRelativeSourcePath: `[${result.compactRelativeSourcePath.length} characters]`,
    }
  : process.argv.includes("--compact")
    ? { ...result, normalizedPaths: undefined }
    : result;
console.log(JSON.stringify(output, null, 2));
