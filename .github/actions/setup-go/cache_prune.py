# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Confirm active setup-go caches on refs/heads/main, then prune superseded ones."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.request

_NEXT_LINK_RE = re.compile(r'<([^>]+)>;\s*rel="next"')
_GO_KEY_PREFIX = "setup-go-"
_MIB = 1024 * 1024


class GitHubCacheApi:
    """Thin GitHub Actions cache REST API client."""

    def __init__(self, api_url: str, repo: str, token: str) -> None:
        self.api_url = api_url.rstrip("/")
        self.repo = repo
        self.token = token

    def _request(self, method: str, url: str, read_json: bool = False):
        req = urllib.request.Request(
            url,
            method=method,
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self.token}",
                "User-Agent": "vitruvian-core-setup-go-cache-prune",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            if read_json:
                return resp.headers, json.loads(raw.decode("utf-8"))
            return resp.headers, None

    def list_caches(self) -> list[dict]:
        """Return all cache entries from `GET /repos/{repo}/actions/caches`."""
        url: str | None = (
            f"{self.api_url}/repos/{self.repo}/actions/caches?per_page=100"
        )
        entries: list[dict] = []
        page = 1
        while url:
            headers, payload = self._request("GET", url, read_json=True)
            if not isinstance(payload, dict) or not isinstance(
                payload.get("actions_caches"), list
            ):
                raise ValueError("actions/caches response missing actions_caches list")
            batch = payload["actions_caches"]
            entries.extend(batch)
            link_header = headers.get("Link") or headers.get("link") or ""
            m = _NEXT_LINK_RE.search(link_header)
            if m:
                url = m.group(1)
            else:
                total_count = payload.get("total_count")
                if (
                    len(batch) == 100
                    and isinstance(total_count, int)
                    and len(entries) < total_count
                ):
                    page += 1
                    url = (
                        f"{self.api_url}/repos/{self.repo}"
                        f"/actions/caches?per_page=100&page={page}"
                    )
                else:
                    url = None
        return entries

    def delete_cache(self, cache_id: int) -> None:
        """Delete a cache entry by numeric id via `DELETE /repos/{repo}/actions/caches/{id}`."""
        self._request(
            "DELETE", f"{self.api_url}/repos/{self.repo}/actions/caches/{cache_id}"
        )


def _validate_keep_keys(keep_keys: list[str]) -> list[str]:
    if not keep_keys:
        raise ValueError("at least one --keep-key is required")
    cleaned: list[str] = []
    for key in keep_keys:
        if not isinstance(key, str) or not key or not key.startswith(_GO_KEY_PREFIX):
            raise ValueError(
                f"invalid keep-key {key!r}: must be non-empty and start with {_GO_KEY_PREFIX!r}"
            )
        cleaned.append(key)
    return cleaned


def confirm_and_prune_superseded_go_caches(
    api: GitHubCacheApi,
    keep_keys: list[str],
    max_confirm_attempts: int = 5,
    retry_delay_seconds: float = 2.0,
    sleep_fn=time.sleep,
    dry_run: bool = False,
) -> dict:
    """Confirm every key in `keep_keys` exists on `refs/heads/main`, then delete other `setup-go-*` main caches."""
    validated_keys = _validate_keep_keys(keep_keys)
    keep_set = set(validated_keys)
    if max_confirm_attempts < 1:
        raise ValueError("max_confirm_attempts must be >= 1")

    confirmed = False
    all_entries: list[dict] = []
    missing_keys = list(validated_keys)
    last_error: str | None = None

    for attempt in range(1, max_confirm_attempts + 1):
        try:
            all_entries = api.list_caches()
            present_main_keys = {
                e.get("key")
                for e in all_entries
                if isinstance(e, dict)
                and e.get("ref") == "refs/heads/main"
                and isinstance(e.get("key"), str)
            }
            missing_keys = [k for k in validated_keys if k not in present_main_keys]
            last_error = None
            if not missing_keys:
                confirmed = True
                break
        except Exception as exc:
            last_error = str(exc)
            all_entries = []
            missing_keys = list(validated_keys)
        if attempt < max_confirm_attempts and retry_delay_seconds > 0:
            sleep_fn(retry_delay_seconds)

    if not confirmed:
        detail = f" (last error: {last_error})" if last_error else ""
        return {
            "confirmed": False,
            "kept_count": len(keep_set),
            "deleted": [],
            "freed_bytes": 0,
            "errors": [],
            "warning": (
                f"Expected setup-go key(s) on refs/heads/main were not confirmed after "
                f"{max_confirm_attempts} attempt(s): {', '.join(missing_keys)}{detail}; deleting nothing."
            ),
        }

    deleted: list[tuple[int, str, int]] = []
    freed_bytes = 0
    errors: list[str] = []

    for entry in all_entries:
        if not isinstance(entry, dict):
            continue
        if entry.get("ref") != "refs/heads/main":
            continue
        key = entry.get("key")
        if not isinstance(key, str) or not key.startswith(_GO_KEY_PREFIX):
            continue
        if key in keep_set:
            continue

        cache_id = entry.get("id")
        if isinstance(cache_id, bool) or not isinstance(cache_id, int):
            errors.append(
                f"Skipping prunable entry {key!r} with invalid id {cache_id!r}"
            )
            continue

        raw_size = entry.get("size_in_bytes")
        size = (
            raw_size
            if isinstance(raw_size, int)
            and not isinstance(raw_size, bool)
            and raw_size >= 0
            else 0
        )

        if dry_run:
            deleted.append((cache_id, key, size))
            freed_bytes += size
            continue

        try:
            api.delete_cache(cache_id)
            deleted.append((cache_id, key, size))
            freed_bytes += size
        except Exception as exc:
            errors.append(f"Failed to delete cache id={cache_id} key={key!r}: {exc}")

    return {
        "confirmed": True,
        "kept_count": len(keep_set),
        "deleted": deleted,
        "freed_bytes": freed_bytes,
        "errors": errors,
        "warning": None,
    }


def _write_summary(summary_file: str, lines: list[str]) -> None:
    if not summary_file:
        return
    with open(summary_file, "a", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo",
        default=os.environ.get("GITHUB_REPOSITORY", ""),
        help="GitHub repository in owner/name form",
    )
    parser.add_argument(
        "--api-url",
        default=os.environ.get("GITHUB_API_URL", "https://api.github.com"),
        help="GitHub REST API base URL",
    )
    parser.add_argument(
        "--ref",
        default=os.environ.get("GITHUB_REF", ""),
        help="Git ref of the running workflow",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("GH_TOKEN", ""),
        help="GitHub token with actions:write scope",
    )
    parser.add_argument(
        "--summary-file",
        default=os.environ.get("GITHUB_STEP_SUMMARY", ""),
        help="Optional step summary markdown file",
    )
    parser.add_argument(
        "--keep-key",
        action="append",
        default=[],
        dest="keep_keys",
        help="Active setup-go cache key to keep on refs/heads/main (repeatable)",
    )
    parser.add_argument("--max-confirm-attempts", type=int, default=5)
    parser.add_argument("--retry-delay-seconds", type=float, default=2.0)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None, sleep_fn=time.sleep) -> int:
    args = _parse_args(argv)

    if args.ref != "refs/heads/main":
        msg = f"Refusing to prune Go caches on non-main ref ({args.ref!r}); deleting nothing."
        print(f"::warning::{msg}", flush=True)
        _write_summary(args.summary_file, [msg])
        return 0

    err_msg: str | None = None
    if not args.repo or "/" not in args.repo:
        err_msg = f"GITHUB_REPOSITORY/--repo is missing or invalid ({args.repo!r})."
    elif not args.token:
        err_msg = "GH_TOKEN/--token is empty; cannot confirm or prune caches."
    else:
        try:
            _validate_keep_keys(args.keep_keys)
        except ValueError as exc:
            err_msg = str(exc)

    if err_msg is not None:
        print(f"::error::{err_msg}", file=sys.stderr, flush=True)
        return 1

    api = GitHubCacheApi(args.api_url, args.repo, args.token)
    result = confirm_and_prune_superseded_go_caches(
        api=api,
        keep_keys=args.keep_keys,
        max_confirm_attempts=args.max_confirm_attempts,
        retry_delay_seconds=args.retry_delay_seconds,
        sleep_fn=sleep_fn,
        dry_run=args.dry_run,
    )

    if not result["confirmed"]:
        print(f"::warning::{result['warning']}", flush=True)
        _write_summary(args.summary_file, [result["warning"]])
        return 0

    for warning in result["errors"]:
        print(f"::warning::{warning}", flush=True)

    freed_mib = result["freed_bytes"] // _MIB
    pruned_count = len(result["deleted"])
    kept_count = result["kept_count"]
    err_count = len(result["errors"])
    mode_tag = " (dry-run)" if args.dry_run else ""

    summary_lines = [
        f"### Go cache cleanup{mode_tag}",
        "",
        "| | |",
        "|---|---|",
        f"| active keys kept | {kept_count} |",
        f"| superseded entries pruned | {pruned_count} ({freed_mib} MiB) |",
        f"| warnings | {err_count} |",
    ]
    _write_summary(args.summary_file, summary_lines)
    print(
        f"Confirmed {kept_count} active setup-go key(s); pruned {pruned_count} superseded entry/ies ({freed_mib} MiB){mode_tag}.",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
