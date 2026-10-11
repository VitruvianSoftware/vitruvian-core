/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// Remembering flaky checks: ones that failed and then passed on a re-run of
// the same commit, with no code change in between. Pure logic, so it runs
// under `node --test`.

export const FLAKE_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;
// A check is called flaky once it has done this at least this many times
// inside the window.
export const FLAKE_THRESHOLD = 2;

const flakeKey = (repo, name) => `${repo.toLowerCase()}|${name}`;

// Tracks which checks have been seen failing on the current commit and
// spots the ones that have since passed.
//   seen: { headSha, failed: string[] } | null
// Returns { seen, flaked }: the updated record, and the names of checks that
// failed earlier on this same commit and pass now.
export function spotFlakes(seen, snap) {
  const sameHead = seen?.headSha === snap.headSha;
  const failed = new Set(sameHead ? seen.failed : []);
  const flaked = [];
  for (const check of snap.checks) {
    if (check.bucket === "fail") failed.add(check.name);
    else if (check.bucket === "pass" && failed.has(check.name)) {
      failed.delete(check.name);
      flaked.push(check.name);
    }
  }
  return { seen: { headSha: snap.headSha, failed: [...failed] }, flaked };
}

// Adds sightings to the table and drops ones that have aged out.
//   table: { "<repo>|<check>": number[] }  timestamps of sightings
export function recordFlakes(table, repo, names, now) {
  const next = {};
  for (const [key, times] of Object.entries(table ?? {})) {
    const kept = times.filter((t) => now - t < FLAKE_WINDOW_MS);
    if (kept.length > 0) next[key] = kept;
  }
  for (const name of names) {
    const key = flakeKey(repo, name);
    next[key] = [...(next[key] ?? []), now];
  }
  return next;
}

// How many times a check has flaked inside the window; 0 if it is not
// considered flaky.
export function flakeCount(table, repo, name, now) {
  const times = (table?.[flakeKey(repo, name)] ?? []).filter(
    (t) => now - t < FLAKE_WINDOW_MS,
  );
  return times.length >= FLAKE_THRESHOLD ? times.length : 0;
}

// Marks the failing checks that are known to be flaky.
export function tagFlaky(table, repo, failing, now) {
  return failing.map((check) => {
    const flaky = flakeCount(table, repo, check.name, now);
    return flaky > 0 ? { ...check, flaky } : check;
  });
}

// Every flaky check in the table for the panel, most frequent first.
export function listFlaky(table, now) {
  const rows = [];
  for (const key of Object.keys(table ?? {})) {
    const [repo, ...rest] = key.split("|");
    const name = rest.join("|");
    const count = flakeCount(table, repo, name, now);
    if (count > 0) rows.push({ repo, name, count });
  }
  return rows.sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
}
