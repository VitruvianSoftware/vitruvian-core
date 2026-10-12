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

// The "Waiting on your review" list, as pure logic so it runs under
// `node --test`.
//
// The user chooses which repositories to list. What is saved is the ones they
// switched off, not the ones they left on, so a repository that asks for
// their review for the first time shows up instead of being silently hidden.

// How many review requests one read asks GitHub for. It is one page of the
// search API, so it still costs a single request.
export const REVIEW_LIMIT = 100;

export const MAX_HIDDEN_REPOS = 200;

const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

// Returns a clean list of "owner/name" strings: anything else is dropped,
// repeats are removed (GitHub ignores case in names) and the list is capped.
export function cleanRepoList(value) {
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  const out = [];
  for (const entry of value) {
    if (typeof entry !== "string" || !REPO.test(entry)) continue;
    const key = entry.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(entry);
    if (out.length >= MAX_HIDDEN_REPOS) break;
  }
  return out;
}

// Splits what GitHub returned into what the panel shows.
//
//   items   the review requests in repositories that are switched on
//   repos   every repository the panel knows about, with how many requests
//           it has and whether it is switched on; hidden ones are kept even
//           at zero so they can be switched back on
//   total   how many requests there are before filtering
//   capped  true when GitHub may have more than were read
export function summariseReviews(all, hidden = [], limit = REVIEW_LIMIT) {
  const off = new Set(hidden.map((repo) => repo.toLowerCase()));
  const isOff = (repo) => off.has(repo.toLowerCase());
  const counts = new Map();
  for (const pr of all) counts.set(pr.repo, (counts.get(pr.repo) ?? 0) + 1);
  for (const repo of hidden) {
    const known = [...counts.keys()].some(
      (name) => name.toLowerCase() === repo.toLowerCase(),
    );
    if (!known) counts.set(repo, 0);
  }
  const repos = [...counts.entries()]
    .map(([repo, count]) => ({ repo, count, shown: !isOff(repo) }))
    .sort((a, b) => a.repo.localeCompare(b.repo));
  return {
    items: all.filter((pr) => !isOff(pr.repo)),
    repos,
    total: all.length,
    capped: all.length >= limit,
  };
}
