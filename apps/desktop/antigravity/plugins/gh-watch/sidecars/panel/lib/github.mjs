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
import {
  REVIEW_LIMIT,
  cleanRepoList,
  conflictBadge,
  readyForAction,
  reviewCheckStatus,
} from "./reviews.mjs";

const FIELDS =
  "number,title,url,state,isDraft,headRefName,baseRefName,headRefOid,mergeable,mergeStateStatus,autoMergeRequest,mergeCommit,statusCheckRollup,reviewDecision,latestReviews,reviewRequests";
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
    reviewDecision: raw.reviewDecision ?? "",
    latestReviews: raw.latestReviews ?? [],
    reviewRequests: raw.reviewRequests ?? [],
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

// Approves a pull request as the signed-in account. `run` is injectable for
// tests.
export async function approvePr(repo, number, run = gh) {
  await run(["pr", "review", String(number), "-R", repo, "--approve"]);
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
// as a pull request's checks. Dynamic repository-wide Dependabot updater runs
// attach to whatever commit happens to be HEAD of the default branch when they
// run, so they are filtered out here; and when a check is re-run on the same
// commit, the newest run (highest id) for each check name wins.
export async function fetchCommitChecks(repo, sha, run = gh) {
  const out = await run([
    "api",
    `repos/${repo}/commits/${sha}/check-runs?per_page=100`,
  ]);
  const rawRuns = (JSON.parse(out)?.check_runs ?? []).filter(
    (r) => r.app?.slug !== "dependabot" && r.name !== "Dependabot",
  );
  const latestByName = new Map();
  for (const r of rawRuns) {
    if (!r?.name) continue;
    const prev = latestByName.get(r.name);
    if (!prev || (r.id ?? 0) >= (prev.id ?? 0)) {
      latestByName.set(r.name, r);
    }
  }
  const runs = latestByName.size > 0 ? [...latestByName.values()] : rawRuns;
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

const SEARCH_QUERY = `
query($q: String!, $limit: Int!) {
  search(query: $q, type: ISSUE, first: $limit) {
    nodes {
      ... on PullRequest {
        number
        title
        url
        isDraft
        updatedAt
        repository { nameWithOwner }
        author { __typename login }
        isInMergeQueue
        mergeQueueEntry { position }
        mergeable
        commits(last: 1) {
          nodes {
            commit {
              statusCheckRollup {
                state
                contexts(first: 1) {
                  checkRunCountsByState { state count }
                  statusContextCountsByState { state count }
                }
              }
            }
          }
        }
      }
    }
  }
}`;

function formatAuthor(author) {
  const login = author?.login ?? "";
  if (!login) return "";
  return author?.__typename === "Bot" && !login.endsWith("[bot]")
    ? `${login}[bot]`
    : login;
}

// Open pull requests found by a GitHub search, each with its CI badge, its
// conflict badge, and whether it is green enough to act on. One page, so one
// request. `run` is injectable for tests.
export async function searchPrs(q, { run = gh, limit = REVIEW_LIMIT } = {}) {
  const out = await run([
    "api",
    "graphql",
    "-f",
    `query=${SEARCH_QUERY}`,
    "-f",
    `q=${q}`,
    "-F",
    `limit=${limit}`,
  ]);
  const nodes = JSON.parse(out)?.data?.search?.nodes ?? [];
  return nodes
    .filter((pr) => pr && pr.number)
    .map((pr) => {
      const rollup = pr.commits?.nodes?.[0]?.commit?.statusCheckRollup ?? null;
      return {
        repo: pr.repository?.nameWithOwner ?? "",
        number: pr.number,
        title: pr.title ?? "",
        url: pr.url,
        author: formatAuthor(pr.author),
        updatedAt: pr.updatedAt ?? null,
        isDraft: pr.isDraft === true,
        status: reviewCheckStatus({
          queued: pr.isInMergeQueue === true,
          queuePosition: pr.mergeQueueEntry?.position ?? null,
          rollup,
        }),
        conflict: conflictBadge(pr.mergeable),
        // Fully green: the panel offers Approve and Approve & merge.
        ready: readyForAction({
          queued: pr.isInMergeQueue === true,
          isDraft: pr.isDraft === true,
          mergeable: pr.mergeable,
          rollup,
        }),
      };
    });
}

// Open pull requests, anywhere on GitHub, where a review has been asked of
// the signed-in account. Drafts are left out: nobody is waiting on those.
export async function fetchReviewRequests(run = gh, limit = REVIEW_LIMIT) {
  const items = await searchPrs("is:pr is:open review-requested:@me", {
    run,
    limit,
  });
  return items.filter((pr) => !pr.isDraft);
}

// Open pull requests the signed-in account opened, anywhere on GitHub,
// drafts included.
export async function fetchMyPrs(run = gh, limit = REVIEW_LIMIT) {
  return searchPrs("is:pr is:open author:@me archived:false", { run, limit });
}

// Every open pull request in the given repositories, whoever opened it.
// Nothing is read for an empty list.
export async function fetchRepoPrs(repos, run = gh, limit = REVIEW_LIMIT) {
  const clean = cleanRepoList(repos);
  if (clean.length === 0) return [];
  const scope = clean.map((repo) => `repo:${repo}`).join(" ");
  return searchPrs(`is:pr is:open archived:false ${scope}`, { run, limit });
}

// Fetches the failed log for a workflow run.
export async function fetchFailureLog(repo, runId, run = gh) {
  return run(["run", "view", String(runId), "--log-failed", "-R", repo]);
}

// Reruns all failed jobs in a workflow run.
export async function rerunFailedJobs(repo, runId, run = gh) {
  return run(["run", "rerun", String(runId), "--failed", "-R", repo]);
}
