// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

// Reads pull request state through the GitHub CLI. `gh` is spawned with an
// argument array and no shell, and uses whatever account `gh auth` holds.

import { execFile } from "node:child_process";

import { normaliseChecks } from "./decide.mjs";

const FIELDS =
  "number,title,url,state,isDraft,headRefName,headRefOid,mergeable,statusCheckRollup";
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
    headSha: raw.headRefOid ?? "",
    mergeable: raw.mergeable ?? "UNKNOWN",
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
