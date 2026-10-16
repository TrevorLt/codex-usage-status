#!/usr/bin/env node

import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const sharp = require(process.env.CODEX_SHARP_MODULE ?? "sharp");

const referencePath =
  process.argv[2] ??
  join(dirname(fileURLToPath(import.meta.url)), "reference", "1b-m.png");
const size = 256;
const threshold = 128;

const { data } = await sharp(referencePath)
  .resize(size, size, { fit: "fill", kernel: "lanczos3" })
  .removeAlpha()
  .greyscale()
  .raw()
  .toBuffer({ resolveWithObject: true });

const referenceMask = new Uint8Array(size * size);
let referenceArea = 0;
for (let index = 0; index < referenceMask.length; index += 1) {
  if (data[index] < threshold) {
    referenceMask[index] = 1;
    referenceArea += 1;
  }
}

const normalizeAngle = (angle) => ((angle % 360) + 360) % 360;
const clockwiseDelta = (start, end) => normalizeAngle(end - start);

function distanceToArc(x, y, cx, cy, radius, startAngle, endAngle) {
  const dx = x - cx;
  const dy = y - cy;
  const radialDistance = Math.hypot(dx, dy);
  const angle = normalizeAngle((Math.atan2(dy, dx) * 180) / Math.PI);
  const arcSweep = clockwiseDelta(startAngle, endAngle);
  const angleFromStart = clockwiseDelta(startAngle, angle);

  if (angleFromStart <= arcSweep) {
    return Math.abs(radialDistance - radius);
  }

  const startRadians = (startAngle * Math.PI) / 180;
  const endRadians = (endAngle * Math.PI) / 180;
  const startX = cx + radius * Math.cos(startRadians);
  const startY = cy + radius * Math.sin(startRadians);
  const endX = cx + radius * Math.cos(endRadians);
  const endY = cy + radius * Math.sin(endRadians);

  return Math.min(
    Math.hypot(x - startX, y - startY),
    Math.hypot(x - endX, y - endY),
  );
}

function score(parameters) {
  const outerArcs = [
    [parameters.outerLeftStart, parameters.outerLeftEnd],
    [parameters.outerTopStart, parameters.outerTopEnd],
    [parameters.outerBottomStart, parameters.outerBottomEnd],
  ];
  let intersection = 0;
  let candidateArea = 0;

  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const sampleX = x + 0.5;
      const sampleY = y + 0.5;
      let inside = false;

      for (const [startAngle, endAngle] of outerArcs) {
        if (
          distanceToArc(
            sampleX,
            sampleY,
            parameters.cx,
            parameters.cy,
            parameters.outerRadius,
            startAngle,
            endAngle,
          ) <=
          parameters.outerWidth / 2
        ) {
          inside = true;
          break;
        }
      }

      if (
        !inside &&
        distanceToArc(
          sampleX,
          sampleY,
          parameters.cx,
          parameters.cy,
          parameters.innerRadius,
          parameters.innerStart,
          parameters.innerEnd,
        ) <=
          parameters.innerWidth / 2
      ) {
        inside = true;
      }

      if (inside) {
        candidateArea += 1;
        if (referenceMask[y * size + x]) intersection += 1;
      }
    }
  }

  const union = referenceArea + candidateArea - intersection;
  return {
    iou: intersection / union,
    intersection,
    union,
    referenceArea,
    candidateArea,
  };
}

const parameters = {
  cx: 127.4,
  cy: 126.5,
  outerRadius: 82.8,
  outerWidth: 18.4,
  outerLeftStart: 98,
  outerLeftEnd: 273,
  outerTopStart: 298,
  outerTopEnd: 333,
  outerBottomStart: 357,
  outerBottomEnd: 75,
  innerRadius: 50.8,
  innerWidth: 16.4,
  innerStart: 6,
  innerEnd: 278,
};

const parameterOrder = Object.keys(parameters);
const stepSchedule = [2, 1, 0.5, 0.25, 0.125, 0.0625];
let bestScore = score(parameters);

for (const step of stepSchedule) {
  let improved = true;
  while (improved) {
    improved = false;
    for (const key of parameterOrder) {
      const original = parameters[key];
      let bestValue = original;
      for (const direction of [-1, 1]) {
        parameters[key] = original + direction * step;
        const trialScore = score(parameters);
        if (trialScore.iou > bestScore.iou) {
          bestScore = trialScore;
          bestValue = parameters[key];
          improved = true;
        }
      }
      parameters[key] = bestValue;
    }
  }
}

console.log(
  JSON.stringify(
    {
      reference: referencePath,
      normalizedSize: size,
      threshold,
      parameters,
      binaryMask: bestScore,
    },
    null,
    2,
  ),
);
