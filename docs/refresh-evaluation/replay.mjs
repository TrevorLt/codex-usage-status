// Offline scheduling experiment. No account access or network requests.
// The current-policy transcription is checked against the real Swift harness
// documented in ../refresh-current-audit.md. Candidate numbers are hypotheses.
// This file is intentionally pinned to the pre-30/60/120 production baseline.
// Do not read current Swift constants here: the replay is a historical
// explanation, while scripts/test-wake-recovery.sh covers current behavior.
const settings = {
  base: 120,
  fast: 30,
  maximum: 300,
  significant: 5,
  stable: 60,
  failure: 300,
};

class CurrentPolicy {
  interval = settings.base;
  significantAt = null;
  success(previous, current, now) {
    if (previous && Math.max(...previous.map((x, i) => x - current[i])) >= settings.significant) {
      this.significantAt = now;
      return this.interval = settings.fast;
    }
    if (this.significantAt === null) return this.interval = settings.base;
    if (now - this.significantAt < settings.stable) return this.interval = settings.fast;
    return this.interval = Math.min(Math.max(settings.maximum, settings.base), Math.max(settings.base, this.interval * 2));
  }
  failure() { return this.interval = settings.failure; }
}

class CandidatePolicy {
  lastChange = 0;
  errors = 0;
  success(previous, current, now) {
    this.errors = 0;
    // In this experiment an increase is a reset signal, never negative usage.
    // Production needs window identity/reset metadata as well as raw precision.
    if (!previous || current.some((x, i) => x !== previous[i])) this.lastChange = now;
    const quiet = now - this.lastChange;
    if (quiet >= 900) return 300;
    if (quiet >= 300) return 120;
    if (quiet >= 90) return 60;
    return 30;
  }
  failure() { return Math.min(300, 30 * 2 ** this.errors++); }
}

class Fixed30Policy {
  success() { return 30; }
  failure() { return settings.failure; }
}

class Candidate120Policy extends CandidatePolicy {
  success(previous, current, now) {
    return Math.min(120, super.success(previous, current, now));
  }
}

class Fixed60Policy {
  success() { return 60; }
  failure() { return settings.failure; }
}

const clamp = x => Math.max(0, Math.min(100, Math.round(x)));
// Non-aligned change times avoid a misleading zero-delay result when the
// synthetic workload accidentally shares the timer's 30/60-second phase.
const steps = (t, period, phase = 17) => t < phase ? 0 : Math.floor((t - phase) / period) + 1;
const scenarios = [
  { name: 'idle', truth: t => [100, 100] },
  { name: 'steady-small-steps', truth: t => [100 - steps(t, 60), 100 - steps(t, 600)] },
  { name: 'large-drop-then-small-steps', truth: t => [t < 137 ? 100 : 94 - Math.floor((t - 137) / 60), 100] },
  { name: 'burst-after-long-idle', truth: t => [t < 1801 ? 100 : 100 - Math.min(60, Math.floor((t - 1801) / 10) + 1), 100] },
  { name: 'burst-just-after-idle-poll', truth: t => [t < 1531 ? 100 : 100 - Math.min(60, Math.floor((t - 1531) / 10) + 1), 100] },
  { name: 'reset-then-usage', truth: t => [t < 1217 ? 40 - steps(t, 120) : 100 - Math.floor((t - 1217) / 60), 85] },
  { name: 'transient-failure', truth: t => [100 - steps(t, 60), 100], fails: t => t >= 600 && t < 900 },
];

function percentile(values, fraction) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.ceil(sorted.length * fraction) - 1];
}

function run(Policy, scenario, publicationLag = 0) {
  const duration = 3600;
  const policy = new Policy();
  let previous = null, displayed = null, next = 0, attempts = 0, failures = 0;
  let errorSum = 0, staleSeconds = 0;
  const successfulSamples = [], publishedChanges = [];
  let lastPublished = null;
  for (let t = 0; t < duration; t++) {
    const published = scenario.truth(Math.max(0, t - publicationLag)).map(clamp);
    if (lastPublished && published.some((x, i) => x !== lastPublished[i])) publishedChanges.push(t);
    lastPublished = published;
    if (t >= next) {
      attempts++;
      if (scenario.fails?.(t)) {
        failures++;
        next = t + policy.failure();
      } else {
        displayed = published;
        successfulSamples.push(t);
        next = t + policy.success(previous, published, t);
        previous = published;
      }
    }
    if (displayed) {
      const error = Math.max(...displayed.map((x, i) => Math.abs(x - published[i])));
      errorSum += error;
      if (error > 0) staleSeconds++;
    }
  }
  // This measures the next opportunity to see a published change. It does not
  // assert every intermediate value appeared on screen. End-censored events
  // are omitted from percentiles and reported explicitly.
  const delays = [], censored = [];
  for (const change of publishedChanges) {
    const nextSample = successfulSamples.find(t => t >= change);
    if (nextSample === undefined) censored.push(change);
    else delays.push(nextSample - change);
  }
  return {
    scenario: scenario.name,
    policy: new Map([[CurrentPolicy, 'historical-current'], [CandidatePolicy, 'candidate-30s'], [Candidate120Policy, 'candidate-cap120'], [Fixed30Policy, 'fixed-30s'], [Fixed60Policy, 'fixed-60s']]).get(Policy),
    publicationLagSeconds: publicationLag,
    attempts, failures,
    processStartsIfOneShot: attempts,
    nextSampleDelayP50Seconds: percentile(delays, .5),
    nextSampleDelayP95Seconds: percentile(delays, .95),
    nextSampleDelayMaxSeconds: delays.length ? Math.max(...delays) : null,
    censoredChanges: censored.length,
    meanDisplayedErrorPercentagePoints: Number((errorSum / duration).toFixed(3)),
    staleSeconds,
  };
}

const policies = process.argv.includes('--baselines')
  ? [CurrentPolicy, CandidatePolicy, Fixed30Policy, Fixed60Policy]
  : [CurrentPolicy, CandidatePolicy];
if (process.argv.includes('--cap120')) policies.push(Candidate120Policy);
const results = scenarios.flatMap(scenario => policies.map(Policy => run(Policy, scenario)));
if (process.argv.includes('--json')) {
  console.log(JSON.stringify({ settings, durationSeconds: 3600, source: 'historical pre-30/60/120 baseline', assumptions: 'Synthetic integer quotas; zero request duration, no timer jitter, no push events; no CPU or energy measurement.', results }, null, 2));
} else {
  console.log('Offline synthetic one-hour replay. Not an energy benchmark. No push events.');
  console.table(results.map(({ publicationLagSeconds, processStartsIfOneShot, ...row }) => row));
}
