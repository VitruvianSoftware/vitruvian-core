# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Pre-save Actions cache capacity guard for bazel-repo-cache.yaml.

Reads active Actions cache usage and entries, checks `usage + archive <= limit`
against `ACTIONS_CACHE_LIMIT_CONFIRMED_GB` (GB = 1,000,000,000 B), and when
over limit deletes ONLY as many same-platform replaceable entries as needed
BEFORE saving (legacy partial `-repository-<hex>` first, then superseded
`-repository-full-<hash>` largest first). If it still does not fit even after
deleting all replaceable same-platform entries, deletes nothing and skips save.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

BYTES_PER_GB = 1_000_000_000
_HEX_RE = re.compile(r"^[0-9a-fA-F]+$")
_NEXT_LINK_RE = re.compile(r'<([^>]+)>\s*;\s*rel="next"')
DEFAULT_API_READ_ATTEMPTS = 3
DEFAULT_API_READ_BACKOFF_SECONDS = (2.0, 4.0)


def full_repo_cache_prefix(platform):
    """Return the exact `-repository-full-` key prefix for `platform`."""
    return f"setup-bazel-1-{platform}-repository-full-"


def legacy_partial_repo_cache_prefix(platform):
    """Return the exact legacy partial `-repository-` key prefix for `platform`."""
    return f"setup-bazel-1-{platform}-repository-"


def is_legacy_partial_repo_cache_key(key, platform):
    """True for same-platform legacy partial `-repository-<hex>` keys (never `-repository-full-`)."""
    if not isinstance(key, str) or not isinstance(platform, str) or not platform:
        return False
    if "-repository-full-" in key:
        return False
    prefix = legacy_partial_repo_cache_prefix(platform)
    if not key.startswith(prefix):
        return False
    return bool(_HEX_RE.fullmatch(key[len(prefix) :]))


def is_superseded_full_repo_cache_key(key, platform, current_lock_hash):
    """True for same-platform `-repository-full-<hash>` keys with a different hash."""
    if not isinstance(key, str) or not platform or not current_lock_hash:
        return False
    prefix = full_repo_cache_prefix(platform)
    if not key.startswith(prefix):
        return False
    suffix = key[len(prefix) :]
    return bool(suffix) and suffix != current_lock_hash


def parse_limit_gb_var(raw):
    """Parse `ACTIONS_CACHE_LIMIT_CONFIRMED_GB` into `(limit_gb, error_detail)`."""
    if raw is None or not isinstance(raw, str) or raw.strip() == "":
        return None, "ACTIONS_CACHE_LIMIT_CONFIRMED_GB is missing or empty"
    text = raw.strip()
    if not re.fullmatch(r"[+-]?[0-9]+", text):
        return (
            None,
            f"ACTIONS_CACHE_LIMIT_CONFIRMED_GB is not an integer ({raw!r})",
        )
    val = int(text)
    if val <= 0:
        return (
            None,
            f"ACTIONS_CACHE_LIMIT_CONFIRMED_GB must be a positive integer, got {val}",
        )
    return val, None


def _require_non_negative_int(value, label):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"{label} must be a non-negative int, got {value!r}")
    return value


def select_pre_save_deletions(
    total_active_bytes,
    caches,
    archive_bytes,
    limit_bytes,
    platform="",
    current_lock_hash="",
):
    """Plan pre-save deletions: returns `(fits, planned_deletions, real_peak_bytes)`."""
    _require_non_negative_int(total_active_bytes, "total_active_bytes")
    _require_non_negative_int(archive_bytes, "archive_bytes")
    _require_non_negative_int(limit_bytes, "limit_bytes")

    direct_peak = total_active_bytes + archive_bytes
    if direct_peak <= limit_bytes:
        return True, [], direct_peak

    candidates = []
    for entry in caches:
        if not isinstance(entry, dict):
            continue
        key = entry.get("key", "")
        if is_legacy_partial_repo_cache_key(key, platform):
            priority = 0
        elif is_superseded_full_repo_cache_key(key, platform, current_lock_hash):
            priority = 1
        else:
            continue
        size = _require_non_negative_int(
            entry.get("size_in_bytes"), f"size_in_bytes for cache {key!r}"
        )
        cache_id = entry.get("id")
        if isinstance(cache_id, bool) or not isinstance(cache_id, int):
            raise ValueError(f"invalid id for replaceable cache {key!r}: {cache_id!r}")
        candidates.append((priority, -size, cache_id, key, size))

    candidates.sort()
    ordered_replaced = [
        {"id": cid, "key": key, "size_in_bytes": size}
        for _prio, _neg_size, cid, key, size in candidates
    ]

    total_replaced = sum(item["size_in_bytes"] for item in ordered_replaced)
    if total_active_bytes - total_replaced + archive_bytes > limit_bytes:
        return False, [], direct_peak

    planned = []
    deleted_bytes = 0
    for item in ordered_replaced:
        planned.append(item)
        deleted_bytes += item["size_in_bytes"]
        if total_active_bytes - deleted_bytes + archive_bytes <= limit_bytes:
            break

    return True, planned, max(0, total_active_bytes - deleted_bytes) + archive_bytes


def prepare_capacity_for_save(
    total_active_bytes,
    caches,
    archive_bytes,
    limit_gb_raw,
    platform="",
    current_lock_hash="",
    delete_fn=None,
):
    """Evaluate pre-save capacity and delete only the minimum needed replaceable entries."""
    _require_non_negative_int(total_active_bytes, "total_active_bytes")
    _require_non_negative_int(archive_bytes, "archive_bytes")

    plat_label = platform or "unknown"
    limit_gb, limit_error = parse_limit_gb_var(limit_gb_raw)
    report = {
        "usage_before_bytes": total_active_bytes,
        "archive_bytes": archive_bytes,
        "limit_gb": limit_gb,
        "limit_bytes": None,
        "limit_error": limit_error,
        "deleted": [],
        "deleted_bytes": 0,
        "delete_errors": [],
        "real_peak_bytes": total_active_bytes + archive_bytes,
        "reason": "",
        "message": "",
    }

    if limit_error is not None or limit_gb is None:
        detail = limit_error or "ACTIONS_CACHE_LIMIT_CONFIRMED_GB is not set"
        report["reason"] = "invalid_limit_var"
        report["message"] = (
            f"Cache save skipped ({plat_label}): {detail}; deleting nothing."
        )
        return False, report

    limit_bytes = limit_gb * BYTES_PER_GB
    report["limit_bytes"] = limit_bytes

    fits, planned, _ = select_pre_save_deletions(
        total_active_bytes=total_active_bytes,
        caches=caches,
        archive_bytes=archive_bytes,
        limit_bytes=limit_bytes,
        platform=platform,
        current_lock_hash=current_lock_hash,
    )
    if not fits:
        report["reason"] = "insufficient_capacity"
        report["message"] = (
            f"Cache save skipped ({plat_label}): usage {total_active_bytes} B + archive "
            f"{archive_bytes} B exceeds limit {limit_bytes} B ({limit_gb} GB) even after "
            f"all replaceable {plat_label} entries; deleting nothing."
        )
        return False, report

    if planned and delete_fn is None:
        raise ValueError("delete_fn is required when pre-save deletions are needed")

    deleted = []
    deleted_bytes = 0
    delete_errors = []
    for item in planned:
        try:
            delete_fn(item["id"])
            deleted.append((item["id"], item["key"], item["size_in_bytes"]))
            deleted_bytes += item["size_in_bytes"]
        except Exception as exc:
            delete_errors.append(
                f"Failed to delete cache id={item['id']} key={item['key']!r}: {exc}"
            )

    real_peak_bytes = max(0, total_active_bytes - deleted_bytes) + archive_bytes
    report["deleted"] = deleted
    report["deleted_bytes"] = deleted_bytes
    report["delete_errors"] = delete_errors
    report["real_peak_bytes"] = real_peak_bytes

    if real_peak_bytes > limit_bytes:
        report["reason"] = "delete_failed_insufficient_capacity"
        report["message"] = (
            f"Cache save skipped ({plat_label}): pre-save peak {real_peak_bytes} B "
            f"still exceeds limit {limit_bytes} B ({limit_gb} GB) after "
            f"{len(delete_errors)} deletion error(s)."
        )
        return False, report

    report["reason"] = "ok"
    report["message"] = (
        f"Pre-save check passed ({plat_label}): real peak {real_peak_bytes} B "
        f"({real_peak_bytes / BYTES_PER_GB:.2f} GB) <= limit {limit_bytes} B ({limit_gb} GB)"
        + (
            f" after deleting {len(deleted)} entry(s) (-{deleted_bytes} B)."
            if deleted
            else "."
        )
    )
    return True, report


def _github_get_json(url, token):
    """Execute a read-only GitHub REST GET request and return `(headers, json)`."""
    req = urllib.request.Request(
        url,
        method="GET",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "vitruvian-core-cache-capacity-guard",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.headers, json.loads(resp.read().decode("utf-8"))


class GitHubCacheApi:
    """Thin GitHub Actions cache REST API client shared by guard and prune."""

    def __init__(self, api_url, repo, token):
        self.api_url = api_url.rstrip("/")
        self.repo = repo
        self.token = token

    def get_usage(self):
        """Read `active_caches_size_in_bytes` from `GET /repos/{repo}/actions/cache/usage`."""
        _, payload = _github_get_json(
            f"{self.api_url}/repos/{self.repo}/actions/cache/usage", self.token
        )
        if not isinstance(payload, dict):
            raise ValueError("cache/usage response must be a JSON object")
        val = payload.get("active_caches_size_in_bytes")
        if isinstance(val, bool) or not isinstance(val, int) or val < 0:
            raise ValueError(
                f"cache/usage response missing non-negative integer active_caches_size_in_bytes: {val!r}"
            )
        return val

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
        req = urllib.request.Request(
            f"{self.api_url}/repos/{self.repo}/actions/caches/{cache_id}",
            method="DELETE",
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self.token}",
                "User-Agent": "vitruvian-core-cache-capacity-guard",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            resp.read()


def _write_lines(path, lines):
    if not path:
        return
    with open(path, "a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def _retry_api_read(
    fn,
    attempts=DEFAULT_API_READ_ATTEMPTS,
    backoff_seconds=DEFAULT_API_READ_BACKOFF_SECONDS,
    sleep_fn=time.sleep,
):
    """Run a read-only API call with retries and backoff on transient errors."""
    last_exc = None
    for attempt in range(1, attempts + 1):
        try:
            return fn()
        except Exception as exc:
            last_exc = exc
            if attempt < attempts:
                delay = (
                    backoff_seconds[attempt - 1]
                    if attempt - 1 < len(backoff_seconds)
                    else backoff_seconds[-1]
                )
                if delay > 0:
                    sleep_fn(delay)
    raise last_exc


def _parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    p.add_argument("--archive-bytes", default=os.environ.get("ARCHIVE_BYTES", ""))
    default_platform = (
        "-".join(
            part
            for part in (
                os.environ.get("PLATFORM_OS", ""),
                os.environ.get("PLATFORM_ARCH", ""),
            )
            if part
        )
        or "unknown"
    )
    p.add_argument("--platform", default=default_platform)
    p.add_argument("--lock-hash", default=os.environ.get("LOCK_HASH", ""))
    p.add_argument("--ref", default=os.environ.get("GITHUB_REF", ""))
    p.add_argument(
        "--limit-gb",
        default=os.environ.get("ACTIONS_CACHE_LIMIT_CONFIRMED_GB", ""),
    )
    p.add_argument(
        "--api-url",
        default=os.environ.get("GITHUB_API_URL", "https://api.github.com"),
    )
    p.add_argument("--token", default=os.environ.get("GH_TOKEN", ""))
    p.add_argument("--summary-file", default=os.environ.get("GITHUB_STEP_SUMMARY", ""))
    p.add_argument("--output-file", default=os.environ.get("GITHUB_OUTPUT", ""))
    return p.parse_args(argv)


def main(argv=None, sleep_fn=time.sleep):
    args = _parse_args(argv)

    def fail_early(msg):
        _write_lines(args.output_file, ["allow_save=false"])
        print(f"::error::{msg}", file=sys.stderr, flush=True)
        _write_lines(
            args.summary_file,
            [f"Actions cache capacity check ({args.platform}): ERROR - {msg}"],
        )
        return 1

    def skip_save(msg):
        _write_lines(args.output_file, ["allow_save=false"])
        print(f"::warning::{msg}", flush=True)
        _write_lines(args.summary_file, [msg])
        return 0

    if args.ref != "refs/heads/main":
        return skip_save(
            f"Cache save skipped ({args.platform}): non-main ref ({args.ref!r}); deleting nothing."
        )

    _, limit_error = parse_limit_gb_var(args.limit_gb)
    if limit_error is not None:
        return skip_save(
            f"Cache save skipped ({args.platform}): {limit_error}; deleting nothing."
        )

    if not args.repo or "/" not in args.repo:
        return fail_early(
            f"GITHUB_REPOSITORY/--repo is missing or invalid ({args.repo!r}); save is aborted."
        )
    if not args.token:
        return fail_early(
            "GH_TOKEN/--token is empty; cannot read Actions cache usage; save is aborted."
        )
    try:
        archive_bytes = int(args.archive_bytes)
        if archive_bytes < 0:
            raise ValueError("negative")
    except (TypeError, ValueError):
        return fail_early(
            f"ARCHIVE_BYTES/--archive-bytes is missing or invalid ({args.archive_bytes!r}); save is aborted."
        )

    api = GitHubCacheApi(args.api_url, args.repo, args.token)
    try:
        total_active_bytes = _retry_api_read(api.get_usage, sleep_fn=sleep_fn)
    except Exception as exc:
        return skip_save(
            f"Cache save skipped ({args.platform}): failed to read Actions cache usage "
            f"after {DEFAULT_API_READ_ATTEMPTS} attempts ({exc}); deleting nothing."
        )

    try:
        caches = _retry_api_read(api.list_caches, sleep_fn=sleep_fn)
    except Exception as exc:
        return skip_save(
            f"Cache save skipped ({args.platform}): failed to list Actions caches "
            f"after {DEFAULT_API_READ_ATTEMPTS} attempts ({exc}); deleting nothing."
        )

    ok, report = prepare_capacity_for_save(
        total_active_bytes=total_active_bytes,
        caches=caches,
        archive_bytes=archive_bytes,
        limit_gb_raw=args.limit_gb,
        platform=args.platform,
        current_lock_hash=args.lock_hash,
        delete_fn=api.delete_cache,
    )
    for err in report["delete_errors"]:
        print(f"::warning::{err}", flush=True)

    print(
        f"Actions cache capacity check ({args.platform}): {'ALLOWED' if ok else 'SKIPPED'} "
        f"| usage={report['usage_before_bytes']} deleted={report['deleted_bytes']} "
        f"archive={report['archive_bytes']} real_peak={report['real_peak_bytes']} "
        f"limit={report['limit_bytes']}",
        flush=True,
    )

    if not ok:
        return skip_save(report["message"])

    _write_lines(args.output_file, ["allow_save=true"])
    _write_lines(args.summary_file, [report["message"]])
    return 0


if __name__ == "__main__":
    sys.exit(main())
