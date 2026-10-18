const FIVE_HOURS_MINS = 5 * 60;
const WEEK_MINS = 7 * 24 * 60;

export function normalizeUsage(rateLimitResponse, now = new Date()) {
  const response = isRecord(rateLimitResponse) ? rateLimitResponse : null;
  const snapshot =
    (isRecord(response?.rateLimitsByLimitId?.codex) && response.rateLimitsByLimitId.codex) ||
    (isRecord(response?.rateLimits) && response.rateLimits) ||
    null;

  if (!snapshot || !hasWindow(snapshot.primary) && !hasWindow(snapshot.secondary)) {
    throw new Error("Codex rate-limit response did not include a usable snapshot.");
  }

  const windows = [snapshot.primary, snapshot.secondary]
    .filter(isRecord)
    .map((window) => normalizeWindow(window, now));

  const fiveHour = windows.find((window) => approximately(window.windowDurationMins, FIVE_HOURS_MINS));
  const weekly = windows.find((window) => approximately(window.windowDurationMins, WEEK_MINS));

  return {
    limitId: snapshot.limitId ?? "codex",
    planType: snapshot.planType ?? null,
    fiveHour: fiveHour ?? null,
    weekly: weekly ?? null,
    windows,
  };
}

export function formatMenuTitle(usage) {
  const parts = [];
  if (usage.fiveHour) {
    parts.push(`5h ${formatRemaining(usage.fiveHour)}`);
  }
  if (usage.weekly) {
    parts.push(`7d ${formatRemaining(usage.weekly)}`);
  }
  return parts.length > 0 ? `Codex ${parts.join(" ")}` : "Codex usage";
}

export function formatTextStatus(usage) {
  const lines = [formatMenuTitle(usage)];
  if (usage.fiveHour) {
    lines.push(`5-hour remaining: ${formatRemaining(usage.fiveHour)}`);
    lines.push(`5-hour reset: ${formatReset(usage.fiveHour.resetsAt)}`);
  }
  if (usage.weekly) {
    lines.push(`Weekly remaining: ${formatRemaining(usage.weekly)}`);
    lines.push(`Weekly reset: ${formatReset(usage.weekly.resetsAt)}`);
  }
  return lines.join("\n");
}

function normalizeWindow(window, now) {
  const rawUsedPercent = toValidPercent(window.usedPercent);
  const usedPercent = rawUsedPercent === null ? null : Math.round(rawUsedPercent);
  const remainingPercent = rawUsedPercent === null ? null : Math.round(100 - rawUsedPercent);
  const resetSeconds = toNumber(window.resetsAt);
  const resetDate = resetSeconds === null ? null : new Date(resetSeconds * 1000);
  const resetsAt = resetDate && Number.isFinite(resetDate.getTime()) ? resetDate : null;
  const rawDuration = toNumber(window.windowDurationMins);
  return {
    usedPercent,
    remainingPercent,
    windowDurationMins: rawDuration !== null && rawDuration > 0 ? rawDuration : null,
    resetsAt,
    staleAt: new Date(now.getTime()),
  };
}

function toNumber(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function toValidPercent(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 100
    ? value
    : null;
}

function approximately(value, target) {
  return typeof value === "number" && Math.abs(value - target) <= 1;
}

function hasWindow(value) {
  return isRecord(value);
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function formatReset(date) {
  if (!date) {
    return "unknown";
  }
  return date.toLocaleString(undefined, { hour12: false });
}

function formatRemaining(window) {
  return typeof window.remainingPercent === "number" && Number.isFinite(window.remainingPercent)
    ? `${window.remainingPercent}%`
    : "--";
}
