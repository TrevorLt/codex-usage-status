import assert from "node:assert/strict";
import test from "node:test";

import { formatMenuTitle, formatTextStatus, normalizeUsage } from "../src/usage-format.js";

test("normalizes Codex 5-hour and weekly windows", () => {
  const usage = normalizeUsage({
    rateLimitsByLimitId: {
      codex: {
        limitId: "codex",
        planType: "plus",
        primary: {
          usedPercent: 34,
          windowDurationMins: 300,
          resetsAt: 1780000000,
        },
        secondary: {
          usedPercent: 37,
          windowDurationMins: 10080,
          resetsAt: 1780500000,
        },
      },
    },
  });

  assert.equal(usage.limitId, "codex");
  assert.equal(usage.planType, "plus");
  assert.equal(usage.fiveHour.remainingPercent, 66);
  assert.equal(usage.weekly.remainingPercent, 63);
  assert.equal(formatMenuTitle(usage), "Codex 5h 66% 7d 63%");
});

test("keeps missing or invalid usage unknown instead of showing a full quota", () => {
  for (const usedPercent of [undefined, null, "35", Number.NaN, Number.POSITIVE_INFINITY]) {
    const usage = normalizeUsage({
      rateLimits: {
        primary: { usedPercent, windowDurationMins: 300 },
        secondary: { usedPercent: 12, windowDurationMins: 10080 },
      },
    });

    assert.equal(usage.fiveHour.usedPercent, null);
    assert.equal(usage.fiveHour.remainingPercent, null);
    assert.equal(usage.weekly.remainingPercent, 88);
  }
});

test("renders a partial quota as an explicit unknown in both text formats", () => {
  const usage = normalizeUsage({
    rateLimits: {
      primary: { windowDurationMins: 300 },
      secondary: { usedPercent: 12, windowDurationMins: 10080 },
    },
  });

  assert.equal(formatMenuTitle(usage), "Codex 5h -- 7d 88%");
  assert.match(formatTextStatus(usage), /5-hour remaining: --/);
  assert.doesNotMatch(formatTextStatus(usage), /null%|undefined%/);
});

test("falls back to backward-compatible single snapshot", () => {
  const usage = normalizeUsage({
    rateLimits: {
      limitId: "codex",
      primary: {
        usedPercent: 0,
        windowDurationMins: 300,
      },
      secondary: {
        usedPercent: 101,
        windowDurationMins: 10080,
      },
    },
  });

  assert.equal(usage.fiveHour.remainingPercent, 100);
  assert.equal(usage.weekly.remainingPercent, null);
});

test("matches quotas by duration and leaves an absent five-hour window null", () => {
  const usage = normalizeUsage({
    rateLimits: {
      primary: { usedPercent: 12, windowDurationMins: 10080 },
    },
  });

  assert.equal(usage.fiveHour, null);
  assert.equal(usage.weekly.remainingPercent, 88);
  assert.equal(formatMenuTitle(usage), "Codex 7d 88%");
  assert.equal(usage.windows.length, 1);
});

test("does not treat an unrelated provider bucket as Codex", () => {
  assert.throws(
    () => normalizeUsage({
      rateLimitsByLimitId: {
        anotherProvider: {
          primary: { usedPercent: 12, windowDurationMins: 300 },
        },
      },
    }),
    /usable snapshot/,
  );

  const legacy = normalizeUsage({
    rateLimitsByLimitId: {
      anotherProvider: {
        primary: { usedPercent: 12, windowDurationMins: 300 },
      },
    },
    rateLimits: {
      primary: { usedPercent: 20, windowDurationMins: 300 },
    },
  });
  assert.equal(legacy.fiveHour.remainingPercent, 80);
});

test("keeps unclassified partial windows visible without assigning them to a quota", () => {
  const usage = normalizeUsage({
    rateLimits: {
      primary: { usedPercent: 35, windowDurationMins: 60 },
    },
  });

  assert.equal(usage.fiveHour, null);
  assert.equal(usage.weekly, null);
  assert.equal(usage.windows.length, 1);
  assert.equal(usage.windows[0].windowDurationMins, 60);
  assert.equal(formatMenuTitle(usage), "Codex usage");
});

test("calculates remaining usage from the raw percentage before rounding", () => {
  const usage = normalizeUsage({
    rateLimits: {
      primary: { usedPercent: 35.5, windowDurationMins: 300 },
      secondary: { usedPercent: 12, windowDurationMins: 10080 },
    },
  });

  assert.equal(usage.fiveHour.usedPercent, 36);
  assert.equal(usage.fiveHour.remainingPercent, 65);
});
