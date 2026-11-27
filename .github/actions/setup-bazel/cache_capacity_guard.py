# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Pre-save Actions cache capacity guard for bazel-repo-cache.yaml.

Reads active Actions cache usage and entries, checks `usage + needed <= limit`
against `ACTIONS_CACHE_LIMIT_CONFIRMED_GB` (GB = 1,000,000,000 B), where
`needed = archive_bytes + gomod_bytes + debs_bytes`, and when over limit deletes
ONLY as many same-platform replaceable entries as needed BEFORE saving (legacy
partial `-repository-<hex>` first, then superseded `-repository-full-<hash>`,
then superseded `bazel-gomod-1-<platform>-<hash>`, then superseded
`ci-debs-1-<platform>-<hash>`, largest first within each tier). If it still does
not fit even after deleting all replaceable same-platform entries, deletes
nothing and skips save.
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


def gomod_cache_prefix(platform):
    """Return the exact `bazel-gomod-1-<platform>-` key prefix."""
    return f"bazel-gomod-1-{platform}-"


def debs_cache_prefix(platform):
    """Return the exact `ci-debs-1-<platform>-` key prefix."""
    return f"ci-debs-1-{platform}-"


def is_superseded_gomod_cache_key(key, platform, current_gomod_hash):
    """True for same-platform `bazel-gomod-1-<platform>-<hash>` keys with a different hash."""
    if not isinstance(key, str) or not platform or not current_gomod_hash:
        return False
    prefix = gomod_cache_prefix(platform)
    if not key.startswith(prefix):
        return False
    suffix = key[len(prefix) :]
    return bool(suffix) and suffix != current_gomod_hash


def is_superseded_debs_cache_key(key, platform, current_debs_hash):
    """True for same-platform `ci-debs-1-<platform>-<hash>` keys with a different hash."""
    if not isinstance(key, str) or not platform or not current_debs_hash:
        return False
    prefix = debs_cache_prefix(platform)
    if not key.startswith(prefix):
        return False
    suffix = key[len(prefix) :]
    return bool(suffix) and suffix != current_debs_hash


def is_superseded_prefixed_cache_key(entry, prefix, keep_key):
    """True for `refs/heads/main` entries matching delimited `prefix` with `key != keep_key`."""
    if (
        not isinstance(entry, dict)
        or not isinstance(prefix, str)
        or not prefix
        or not keep_key
    ):
        return False
    if entry.get("ref") != "refs/heads/main":
        return False
    key = entry.get("key")
    if not isinstance(key, str):
        return False
    delimited = prefix if prefix.endswith("-") else f"{prefix}-"
    if not key.startswith(delimited):
        return False
    suffix = key[len(delimited) :]
    return bool(suffix) and key != keep_key


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
    gomod_bytes=0,
    debs_bytes=0,
    current_gomod_hash="",
    current_debs_hash="",
    extra_bytes=0,
    extra_prefix="",
    extra_keep_key="",
):
    """Plan pre-save deletions: returns `(fits, planned_deletions, real_peak_bytes)`."""
    _require_non_negative_int(total_active_bytes, "total_active_bytes")
    _require_non_negative_int(archive_bytes, "archive_bytes")
    _require_non_negative_int(gomod_bytes, "gomod_bytes")
    _require_non_negative_int(debs_bytes, "debs_bytes")
    _require_non_negative_int(extra_bytes, "extra_bytes")
    _require_non_negative_int(limit_bytes, "limit_bytes")

    needed_bytes = archive_bytes + gomod_bytes + debs_bytes + extra_bytes
    direct_peak = total_active_bytes + needed_bytes
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
        elif is_superseded_gomod_cache_key(key, platform, current_gomod_hash):
            priority = 2
        elif is_superseded_debs_cache_key(key, platform, current_debs_hash):
            priority = 3
        elif is_superseded_prefixed_cache_key(entry, extra_prefix, extra_keep_key):
            priority = 4
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
    total_replaced = sum(item[4] for item in candidates)
    if total_active_bytes - total_replaced + needed_bytes > limit_bytes:
        return False, [], direct_peak

    planned = []
    deleted_bytes = 0
    for _prio, _neg_size, cid, key, size in candidates:
        planned.append({"id": cid, "key": key, "size_in_bytes": size})
        deleted_bytes += size
        if total_active_bytes - deleted_bytes + needed_bytes <= limit_bytes:
            break

    return True, planned, max(0, total_active_bytes - deleted_bytes) + needed_bytes


def prepare_capacity_for_save(
    total_active_bytes,
    caches,
    archive_bytes,
    limit_gb_raw,
    platform="",
    current_lock_hash="",
    gomod_bytes=0,
    debs_bytes=0,
    current_gomod_hash="",
    current_debs_hash="",
    extra_bytes=0,
    extra_prefix="",
    extra_keep_key="",
    delete_fn=None,
):
    """Evaluate pre-save capacity and delete only the minimum needed replaceable entries."""
    plat_label = platform or "unknown"
    _require_non_negative_int(archive_bytes, "archive_bytes")
    _require_non_negative_int(gomod_bytes, "gomod_bytes")
    _require_non_negative_int(debs_bytes, "debs_bytes")
    _require_non_negative_int(extra_bytes, "extra_bytes")
    needed_bytes = archive_bytes + gomod_bytes + debs_bytes + extra_bytes
    limit_gb, limit_error = parse_limit_gb_var(limit_gb_raw)
    report = {
        "usage_before_bytes": total_active_bytes,
        "archive_bytes": archive_bytes,
        "gomod_bytes": gomod_bytes,
        "debs_bytes": debs_bytes,
        "extra_bytes": extra_bytes,
        "needed_bytes": needed_bytes,
        "limit_bytes": None,
        "deleted_bytes": 0,
        "delete_errors": [],
        "real_peak_bytes": total_active_bytes + needed_bytes,
        "message": "",
    }

    if limit_error is not None:
        report["message"] = (
            f"Cache save skipped ({plat_label}): {limit_error}; deleting nothing."
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
        gomod_bytes=gomod_bytes,
        debs_bytes=debs_bytes,
        current_gomod_hash=current_gomod_hash,
        current_debs_hash=current_debs_hash,
        extra_bytes=extra_bytes,
        extra_prefix=extra_prefix,
        extra_keep_key=extra_keep_key,
    )
    if not fits:
        extra_note = f", extra={extra_bytes}" if extra_bytes > 0 else ""
        report["message"] = (
            f"Cache save skipped ({plat_label}): usage {total_active_bytes} B + needed "
            f"{needed_bytes} B (archive={archive_bytes}, gomod={gomod_bytes}, debs={debs_bytes}{extra_note}) "
            f"exceeds limit {limit_bytes} B ({limit_gb} GB) even after all replaceable "
            f"{plat_label} entries; deleting nothing."
        )
        return False, report

    if planned and delete_fn is None:
        raise ValueError("delete_fn is required when pre-save deletions are needed")

    deleted = 0
    deleted_bytes = 0
    delete_errors = []
    for item in planned:
        try:
            delete_fn(item["id"])
            deleted += 1
            deleted_bytes += item["size_in_bytes"]
        except Exception as exc:
            delete_errors.append(
                f"Failed to delete cache id={item['id']} key={item['key']!r}: {exc}"
            )

    real_peak_bytes = max(0, total_active_bytes - deleted_bytes) + needed_bytes
    report["deleted_bytes"] = deleted_bytes
    report["delete_errors"] = delete_errors
    report["real_peak_bytes"] = real_peak_bytes

    if real_peak_bytes > limit_bytes:
        report["message"] = (
            f"Cache save skipped ({plat_label}): pre-save peak {real_peak_bytes} B "
            f"still exceeds limit {limit_bytes} B ({limit_gb} GB) after "
            f"{len(delete_errors)} deletion error(s)."
        )
        return False, report

    suffix = (
        f" after deleting {deleted} entry(s) (-{deleted_bytes} B)." if deleted else "."
    )
    report["message"] = (
        f"Pre-save check passed ({plat_label}): real peak {real_peak_bytes} B "
        f"({real_peak_bytes / BYTES_PER_GB:.2f} GB) <= limit {limit_bytes} B ({limit_gb} GB){suffix}"
    )
    return True, report


class GitHubCacheApi:
    """Thin GitHub Actions cache REST API client shared by guard and prune."""

    def __init__(self, api_url, repo, token):
        self.api_url = api_url.rstrip("/")
        self.repo = repo
        self.token = token

    def _request(self, method, url, read_json=False):
        req = urllib.request.Request(
            url,
            method=method,
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self.token}",
                "User-Agent": "vitruvian-core-cache-capacity-guard",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            if read_json:
                return resp.headers, json.loads(raw.decode("utf-8"))
            return resp.headers, None

    def get_usage(self):
        """Read `active_caches_size_in_bytes` from `GET /repos/{repo}/actions/cache/usage`."""
        _, payload = self._request(
            "GET",
            f"{self.api_url}/repos/{self.repo}/actions/cache/usage",
            read_json=True,
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
            headers, payload = self._request("GET", url, read_json=True)
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
        self._request(
            "DELETE", f"{self.api_url}/repos/{self.repo}/actions/caches/{cache_id}"
        )


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
                delay = backoff_seconds[min(attempt - 1, len(backoff_seconds) - 1)]
                if delay > 0:
                    sleep_fn(delay)
    raise last_exc


def add_common_args(parser, default_platform_fallback=""):
    """Add shared GitHub Actions cache CLI arguments for guard and prune."""
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    default_platform = (
        "-".join(
            part
            for part in (
                os.environ.get("PLATFORM_OS", ""),
                os.environ.get("PLATFORM_ARCH", ""),
            )
            if part
        )
        or default_platform_fallback
    )
    parser.add_argument("--platform", default=default_platform)
    parser.add_argument("--lock-hash", default=os.environ.get("LOCK_HASH", ""))
    parser.add_argument("--ref", default=os.environ.get("GITHUB_REF", ""))
    parser.add_argument(
        "--api-url",
        default=os.environ.get("GITHUB_API_URL", "https://api.github.com"),
    )
    parser.add_argument("--token", default=os.environ.get("GH_TOKEN", ""))
    parser.add_argument(
        "--summary-file", default=os.environ.get("GITHUB_STEP_SUMMARY", "")
    )


def _parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    add_common_args(p, default_platform_fallback="unknown")
    p.add_argument("--archive-bytes", default=os.environ.get("ARCHIVE_BYTES", ""))
    p.add_argument("--gomod-bytes", default=os.environ.get("GOMOD_SAVE_BYTES", "0"))
    p.add_argument("--gomod-hash", default=os.environ.get("GOMOD_HASH", ""))
    p.add_argument("--debs-bytes", default=os.environ.get("DEBS_SAVE_BYTES", "0"))
    p.add_argument("--debs-hash", default=os.environ.get("DEBS_SHA_KEY", ""))
    p.add_argument("--extra-bytes", default=os.environ.get("EXTRA_SAVE_BYTES", "0"))
    p.add_argument("--extra-prefix", default=os.environ.get("EXTRA_CACHE_PREFIX", ""))
    p.add_argument("--extra-keep-key", default=os.environ.get("EXTRA_KEEP_KEY", ""))
    p.add_argument(
        "--limit-gb",
        default=os.environ.get("ACTIONS_CACHE_LIMIT_CONFIRMED_GB", ""),
    )
    p.add_argument("--output-file", default=os.environ.get("GITHUB_OUTPUT", ""))
    return p.parse_args(argv)


def _parse_non_negative_bytes(raw, label):
    val = int(raw)
    if val < 0:
        raise ValueError(f"{label} is negative")
    return val


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
        archive_bytes = _parse_non_negative_bytes(args.archive_bytes, "ARCHIVE_BYTES")
    except (TypeError, ValueError):
        return fail_early(
            f"ARCHIVE_BYTES/--archive-bytes is missing or invalid ({args.archive_bytes!r}); save is aborted."
        )
    try:
        gomod_bytes = _parse_non_negative_bytes(args.gomod_bytes, "GOMOD_SAVE_BYTES")
    except (TypeError, ValueError):
        return fail_early(
            f"GOMOD_SAVE_BYTES/--gomod-bytes is invalid ({args.gomod_bytes!r}); save is aborted."
        )
    try:
        debs_bytes = _parse_non_negative_bytes(args.debs_bytes, "DEBS_SAVE_BYTES")
    except (TypeError, ValueError):
        return fail_early(
            f"DEBS_SAVE_BYTES/--debs-bytes is invalid ({args.debs_bytes!r}); save is aborted."
        )
    try:
        extra_bytes = _parse_non_negative_bytes(args.extra_bytes, "EXTRA_SAVE_BYTES")
    except (TypeError, ValueError):
        return fail_early(
            f"EXTRA_SAVE_BYTES/--extra-bytes is invalid ({args.extra_bytes!r}); save is aborted."
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
        gomod_bytes=gomod_bytes,
        debs_bytes=debs_bytes,
        current_gomod_hash=args.gomod_hash,
        current_debs_hash=args.debs_hash,
        extra_bytes=extra_bytes,
        extra_prefix=args.extra_prefix,
        extra_keep_key=args.extra_keep_key,
        delete_fn=api.delete_cache,
    )
    for err in report["delete_errors"]:
        print(f"::warning::{err}", flush=True)

    extra_part = f" extra={report['extra_bytes']}" if report["extra_bytes"] > 0 else ""
    print(
        f"Actions cache capacity check ({args.platform}): {'ALLOWED' if ok else 'SKIPPED'} "
        f"| usage={report['usage_before_bytes']} deleted={report['deleted_bytes']} "
        f"archive={report['archive_bytes']} gomod={report['gomod_bytes']} "
        f"debs={report['debs_bytes']}{extra_part} needed={report['needed_bytes']} "
        f"real_peak={report['real_peak_bytes']} limit={report['limit_bytes']}",
        flush=True,
    )

    if not ok:
        return skip_save(report["message"])

    _write_lines(args.output_file, ["allow_save=true"])
    _write_lines(args.summary_file, [report["message"]])
    return 0


if __name__ == "__main__":
    sys.exit(main())
