# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Confirm a newly saved `-repository-full-` cache entry, then prune superseded ones.

Only deletes same-platform `setup-bazel-1-<platform>-repository-full-<hash>`
entries with a different lock hash, and ONLY after `GET /actions/caches?key=<new>`
confirms the newly saved entry exists. Never deletes on non-main refs.
"""

import argparse
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cache_capacity_guard import (
    _NEXT_LINK_RE,
    _github_get_json,
    full_repo_cache_prefix,
    is_superseded_full_repo_cache_key,
)


class GitHubCacheApi:
    """Thin GitHub Actions cache REST API client for list/confirm/delete."""

    def __init__(self, api_url, repo, token):
        self.api_url = api_url.rstrip("/")
        self.repo = repo
        self.token = token

    def list_caches(self, key=None):
        """Return cache entries from `GET /repos/{repo}/actions/caches`."""
        url = f"{self.api_url}/repos/{self.repo}/actions/caches?per_page=100"
        if key is not None:
            url += f"&key={urllib.parse.quote(key, safe='')}"
        entries = []
        while url:
            headers, payload = _github_get_json(url, self.token)
            if not isinstance(payload, dict) or not isinstance(
                payload.get("actions_caches"), list
            ):
                raise ValueError("actions/caches response missing actions_caches list")
            entries.extend(payload["actions_caches"])
            link_header = headers.get("Link") or headers.get("link") or ""
            m = _NEXT_LINK_RE.search(link_header)
            url = m.group(1) if m else None
        return entries

    def delete_cache(self, cache_id):
        """Delete a cache entry by numeric id via `DELETE /repos/{repo}/actions/caches/{id}`."""
        url = f"{self.api_url}/repos/{self.repo}/actions/caches/{cache_id}"
        req = urllib.request.Request(
            url,
            method="DELETE",
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self.token}",
                "User-Agent": "vitruvian-core-cache-prune",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            resp.read()


def confirm_and_prune_superseded_caches(
    api,
    platform,
    current_lock_hash,
    max_confirm_attempts=5,
    retry_delay_seconds=2.0,
    sleep_fn=time.sleep,
):
    """Confirm `new_key` exists, then delete superseded same-platform full entries."""
    if not platform or not current_lock_hash:
        raise ValueError("platform and current_lock_hash must be non-empty")

    new_key = f"{full_repo_cache_prefix(platform)}{current_lock_hash}"
    confirmed = False
    last_error = None

    for attempt in range(1, max_confirm_attempts + 1):
        try:
            entries = api.list_caches(key=new_key)
        except (urllib.error.URLError, OSError, ValueError, RuntimeError) as exc:
            last_error = str(exc)
            entries = []
        if any(isinstance(e, dict) and e.get("key") == new_key for e in entries):
            confirmed = True
            break
        if attempt < max_confirm_attempts and retry_delay_seconds > 0:
            sleep_fn(retry_delay_seconds)

    if not confirmed:
        detail = f" (last error: {last_error})" if last_error else ""
        return {
            "confirmed": False,
            "new_key": new_key,
            "deleted": [],
            "errors": [],
            "warning": (
                f"New cache key {new_key!r} was not confirmed by GET /actions/caches "
                f"after {max_confirm_attempts} attempt(s){detail}; deleting nothing."
            ),
        }

    all_entries = api.list_caches()
    deleted = []
    errors = []
    for entry in all_entries:
        if not isinstance(entry, dict):
            continue
        key = entry.get("key")
        if key == new_key:
            continue
        if not is_superseded_full_repo_cache_key(key, platform, current_lock_hash):
            continue
        cache_id = entry.get("id")
        if isinstance(cache_id, bool) or not isinstance(cache_id, int):
            errors.append(
                f"Skipping superseded entry {key!r} with invalid id {cache_id!r}"
            )
            continue
        try:
            api.delete_cache(cache_id)
            deleted.append((cache_id, key, entry.get("size_in_bytes")))
        except Exception as exc:
            errors.append(f"Failed to delete cache id={cache_id} key={key!r}: {exc}")

    return {
        "confirmed": True,
        "new_key": new_key,
        "deleted": deleted,
        "errors": errors,
        "warning": None,
    }


def _write_summary(summary_file, line):
    if not summary_file:
        return
    with open(summary_file, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def _parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    default_platform = (
        "-".join(
            part
            for part in (
                os.environ.get("PLATFORM_OS", ""),
                os.environ.get("PLATFORM_ARCH", ""),
            )
            if part
        )
        or ""
    )
    p.add_argument("--platform", default=default_platform)
    p.add_argument("--lock-hash", default=os.environ.get("LOCK_HASH", ""))
    p.add_argument("--ref", default=os.environ.get("GITHUB_REF", ""))
    p.add_argument(
        "--api-url",
        default=os.environ.get("GITHUB_API_URL", "https://api.github.com"),
    )
    p.add_argument("--token", default=os.environ.get("GH_TOKEN", ""))
    p.add_argument("--summary-file", default=os.environ.get("GITHUB_STEP_SUMMARY", ""))
    p.add_argument("--max-confirm-attempts", type=int, default=5)
    p.add_argument("--retry-delay-seconds", type=float, default=2.0)
    return p.parse_args(argv)


def main(argv=None):
    args = _parse_args(argv)

    if args.ref != "refs/heads/main":
        msg = f"Refusing to prune caches on non-main ref ({args.ref!r}); deleting nothing."
        print(f"::warning::{msg}", flush=True)
        _write_summary(args.summary_file, msg)
        return 0

    if not args.repo or "/" not in args.repo:
        print(
            f"::error::GITHUB_REPOSITORY/--repo is missing or invalid ({args.repo!r}).",
            file=sys.stderr,
            flush=True,
        )
        return 1
    if not args.token:
        print(
            "::error::GH_TOKEN/--token is empty; cannot confirm or prune caches.",
            file=sys.stderr,
            flush=True,
        )
        return 1
    if not args.platform or not args.lock_hash:
        print(
            f"::error::platform ({args.platform!r}) and lock-hash ({args.lock_hash!r}) are required.",
            file=sys.stderr,
            flush=True,
        )
        return 1

    api = GitHubCacheApi(args.api_url, args.repo, args.token)
    result = confirm_and_prune_superseded_caches(
        api=api,
        platform=args.platform,
        current_lock_hash=args.lock_hash,
        max_confirm_attempts=args.max_confirm_attempts,
        retry_delay_seconds=args.retry_delay_seconds,
    )

    if not result["confirmed"]:
        print(f"::warning::{result['warning']}", flush=True)
        _write_summary(args.summary_file, result["warning"])
        return 0

    for err in result["errors"]:
        print(f"::warning::{err}", flush=True)

    if result["deleted"]:
        summary_items = ", ".join(
            f"{key} (id={cid})" for cid, key, _size in result["deleted"]
        )
        msg = (
            f"Confirmed {result['new_key']}; pruned {len(result['deleted'])} "
            f"superseded {args.platform} cache(s): {summary_items}."
        )
    else:
        msg = (
            f"Confirmed {result['new_key']}; no superseded {args.platform} "
            f"full caches to prune."
        )

    print(msg, flush=True)
    _write_summary(args.summary_file, msg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
