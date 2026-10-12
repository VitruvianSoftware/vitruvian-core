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

// Reads pull request state through the GitHub CLI. `gh` is spawned with an
// argument array and no shell, and uses whatever account `gh auth` holds.

import { execFile } from "node:child_process";

import { normaliseChecks } from "./decide.mjs";
import { collectFeedback } from "./notices.mjs";
import { REVIEW_LIMIT } from "./reviews.mjs";

const FIELDS =
  "number,title,url,state,isDraft,headRefName,baseRefName,headRefOid,mergeable,mergeStateStatus,autoMergeRequest,mergeCommit,statusCheckRollup";
const PR_URL = /^https:\/\/github\.com\/([^/\s]+\/[^/\s]+)\/pull\/(\d+)/;

function gh(args, { cwd, timeoutMs = 20_000 } = {}) {
  return new Promise((resolve, reject) => {
    execFile(
      "gh",
      args,
      { cwd, timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024 },
      (err, stdout, stderr) => {
        if (err) {
          const detail = (stderr || err.message || "").trim().split("\n")[0];
          reject(
            new Error(
              err.code === "ENOENT"
                ? "GitHub CLI (gh) was not found on PATH"
                : detail || "gh failed",
            ),
          );
          return;
        }
        resolve(stdout);
      },
    );
  });
}

export function parsePrUrl(url) {
  const match = PR_URL.exec(url ?? "");
  return match ? { repo: match[1], number: Number(match[2]) } : null;
}

function toSnapshot(raw) {
  const where = parsePrUrl(raw.url);
  if (!where) throw new Error(`Unexpected pull request URL: ${raw.url}`);
  return {
    repo: where.repo,
    number: raw.number,
    title: raw.title ?? "",
    url: raw.url,
    state: (raw.state ?? "OPEN").toUpperCase(),
    isDraft: raw.isDraft === true,
    branch: raw.headRefName ?? "",
    base: raw.baseRefName ?? "",
    headSha: raw.headRefOid ?? "",
    mergeable: raw.mergeable ?? "UNKNOWN",
    mergeState: raw.mergeStateStatus ?? "UNKNOWN",
    autoMerge: raw.autoMergeRequest != null,
    mergeCommit: raw.mergeCommit?.oid ?? null,
    checks: normaliseChecks(raw.statusCheckRollup),
  };
}

// Reads one pull request by repository and number.
export async function fetchPr(repo, number) {
  const out = await gh([
    "pr",
    "view",
    String(number),
    "-R",
    repo,
    "--json",
    FIELDS,
  ]);
  return toSnapshot(JSON.parse(out));
}

// Finds the pull request the user means. `ref` may be a PR URL, a number or
// blank; a number or blank is resolved against the git checkout in `cwd`
// (blank = the pull request for the checked-out branch).
export async function resolvePr(ref, cwd) {
  const text = String(ref ?? "")
    .trim()
    .replace(/^#/, "");
  const fromUrl = parsePrUrl(text);
  if (fromUrl) return fetchPr(fromUrl.repo, fromUrl.number);
  if (text !== "" && !/^\d+$/.test(text))
    throw new Error("Enter a pull request URL or number");
  if (!cwd)
    throw new Error(
      "This conversation has no workspace folder, so paste the full pull request URL",
    );
  const args = ["pr", "view"];
  if (text !== "") args.push(text);
  args.push("--json", FIELDS);
  return toSnapshot(JSON.parse(await gh(args, { cwd })));
}

// GitHub refuses a bare `--auto` on a repository without a merge queue: it
// wants to know how to merge.
const NEEDS_METHOD = /--merge, --rebase, or --squash|merge method/i;

// Turns GitHub's own auto-merge on or off for a pull request. Merging is
// GitHub's doing, once the required checks and reviews are in; nothing is
// merged here. `run` is injectable for tests.
export async function setAutoMerge(repo, number, enabled, method, run = gh) {
  const base = ["pr", "merge", String(number), "-R", repo];
  if (!enabled) {
    await run([...base, "--disable-auto"]);
    return;
  }
  try {
    // With a merge queue the repository decides how to merge.
    await run([...base, "--auto"]);
  } catch (err) {
    if (/is a draft/i.test(err.message)) {
      throw new Error(
        "A draft pull request cannot auto-merge. Mark it ready for review first.",
        { cause: err },
      );
    }
    if (!NEEDS_METHOD.test(err.message)) throw err;
    await run([...base, "--auto", `--${method}`]);
  }
}

let cachedLogin = null;

// The GitHub account `gh` is signed in as, read once.
export async function getLogin(run = gh) {
  if (cachedLogin === null) {
    cachedLogin = (await run(["api", "user", "--jq", ".login"])).trim();
  }
  return cachedLogin;
}

const PERSON =
  "databaseId url body authorAssociation author { login __typename }";
const FEEDBACK_QUERY = `
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      comments(last: 50) { nodes { ${PERSON} } }
      reviews(last: 30) { nodes { state ${PERSON} } }
      reviewThreads(last: 50) {
        nodes {
          isResolved
          isOutdated
          comments(first: 10) { nodes { path line ${PERSON} } }
        }
      }
    }
  }
}`;

// Reads the review feedback on a pull request that is worth showing the
// agent: see collectFeedback for what is kept.
export async function fetchFeedback(repo, number, run = gh) {
  const [owner, name] = repo.split("/");
  const out = await run([
    "api",
    "graphql",
    "-f",
    `query=${FEEDBACK_QUERY}`,
    "-F",
    `owner=${owner}`,
    "-F",
    `name=${name}`,
    "-F",
    `number=${number}`,
  ]);
  const pr = JSON.parse(out)?.data?.repository?.pullRequest;
  if (!pr)
    throw new Error("GitHub returned no pull request for the feedback read");
  return collectFeedback(pr, await getLogin(run));
}

const QUEUE_QUERY = `
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      isInMergeQueue
      mergeQueueEntry { position }
    }
  }
}`;

// Whether a pull request is in the merge queue, and where. `gh pr view`
// cannot say, so this is its own small read.
export async function fetchQueue(repo, number, run = gh) {
  const [owner, name] = repo.split("/");
  const out = await run([
    "api",
    "graphql",
    "-f",
    `query=${QUEUE_QUERY}`,
    "-F",
    `owner=${owner}`,
    "-F",
    `name=${name}`,
    "-F",
    `number=${number}`,
  ]);
  const pr = JSON.parse(out)?.data?.repository?.pullRequest;
  return {
    queued: pr?.isInMergeQueue === true,
    position: pr?.mergeQueueEntry?.position ?? null,
  };
}

// The checks that ran on one commit of the base branch, in the same shape
// as a pull request's checks.
export async function fetchCommitChecks(repo, sha, run = gh) {
  const out = await run([
    "api",
    `repos/${repo}/commits/${sha}/check-runs?per_page=100`,
  ]);
  const runs = JSON.parse(out)?.check_runs ?? [];
  return normaliseChecks(
    runs.map((r) => ({
      __typename: "CheckRun",
      name: r.name,
      status: r.status,
      conclusion: r.conclusion,
      detailsUrl: r.html_url,
    })),
  );
}

// Open pull requests, anywhere on GitHub, where a review has been asked of
// the signed-in account.
export async function fetchReviewRequests(run = gh, limit = REVIEW_LIMIT) {
  const out = await run([
    "search",
    "prs",
    "--review-requested=@me",
    "--state=open",
    "--json",
    "number,title,url,repository,author,updatedAt,isDraft",
    "--limit",
    String(limit),
  ]);
  return (JSON.parse(out) ?? [])
    .filter((pr) => pr.isDraft !== true)
    .map((pr) => ({
      repo: pr.repository?.nameWithOwner ?? "",
      number: pr.number,
      title: pr.title ?? "",
      url: pr.url,
      author: pr.author?.login ?? "",
      updatedAt: pr.updatedAt ?? null,
    }));
}
