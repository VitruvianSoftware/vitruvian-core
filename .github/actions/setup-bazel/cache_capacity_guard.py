# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Fail-safe Actions cache capacity guard for bazel-repo-cache.yaml.

Reads the repository's current Actions cache usage, lists active cache entries
to subtract legacy partial `setup-bazel-1-*-repository-<hex>` entries and
same-platform superseded `setup-bazel-1-<platform>-repository-full-<hex>` entries
(which are replaced once the new `-repository-full-` entry lands), reads the
confirmed cache limit from `ACTIONS_CACHE_LIMIT_CONFIRMED_GB`, and skips saving
with exit 0 (printing a warning and one-line summary) if the variable is
missing, invalid, or smaller than `needed`.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

BYTES_PER_GB = 1_000_000_000
LEGACY_PARTIAL_REPO_KEY_RE = re.compile(r"^setup-bazel-1-.+-repository-[0-9a-fA-F]+$")
_NEXT_LINK_RE = re.compile(r'<([^>]+)>\s*;\s*rel="next"')


def full_repo_cache_prefix(platform):
    """Return the exact `-repository-full-` key prefix for `platform`."""
    return f"setup-bazel-1-{platform}-repository-full-"


def is_legacy_partial_repo_cache_key(key):
    """True for legacy partial `-repository-<hex>` keys (not `-repository-full-`)."""
    if not isinstance(key, str):
        return False
    return (
        bool(LEGACY_PARTIAL_REPO_KEY_RE.match(key)) and "-repository-full-" not in key
    )


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


def compute_needed_bytes(
    total_active_bytes,
    caches,
    archive_bytes,
    platform="",
    current_lock_hash="",
):
    """Return `(needed_bytes, legacy_bytes, matched_legacy, superseded_bytes, matched_superseded)`."""
    if (
        isinstance(total_active_bytes, bool)
        or not isinstance(total_active_bytes, int)
        or total_active_bytes < 0
    ):
        raise ValueError(
            f"total_active_bytes must be a non-negative int, got {total_active_bytes!r}"
        )
    if (
        isinstance(archive_bytes, bool)
        or not isinstance(archive_bytes, int)
        or archive_bytes < 0
    ):
        raise ValueError(
            f"archive_bytes must be a non-negative int, got {archive_bytes!r}"
        )

    matched_legacy = []
    legacy_bytes = 0
    matched_superseded = []
    superseded_bytes = 0

    for entry in caches:
        if not isinstance(entry, dict):
            continue
        key = entry.get("key", "")
        if is_legacy_partial_repo_cache_key(key):
            size = entry.get("size_in_bytes")
            if isinstance(size, bool) or not isinstance(size, int) or size < 0:
                raise ValueError(
                    f"invalid size_in_bytes for legacy cache {key!r}: {size!r}"
                )
            matched_legacy.append((key, size))
            legacy_bytes += size
        elif is_superseded_full_repo_cache_key(key, platform, current_lock_hash):
            size = entry.get("size_in_bytes")
            if isinstance(size, bool) or not isinstance(size, int) or size < 0:
                raise ValueError(
                    f"invalid size_in_bytes for superseded cache {key!r}: {size!r}"
                )
            matched_superseded.append((key, size))
            superseded_bytes += size

    effective_active_bytes = max(
        0, total_active_bytes - legacy_bytes - superseded_bytes
    )
    needed_bytes = effective_active_bytes + archive_bytes
    return (
        needed_bytes,
        legacy_bytes,
        matched_legacy,
        superseded_bytes,
        matched_superseded,
    )


def evaluate_capacity(
    total_active_bytes,
    caches,
    archive_bytes,
    limit_gb_raw,
    platform="",
    current_lock_hash="",
):
    """Decide whether saving `archive_bytes` fits within `limit_gb_raw`."""
    (
        needed_bytes,
        legacy_bytes,
        matched_legacy,
        superseded_bytes,
        matched_superseded,
    ) = compute_needed_bytes(
        total_active_bytes,
        caches,
        archive_bytes,
        platform=platform,
        current_lock_hash=current_lock_hash,
    )
    effective_active_bytes = max(
        0, total_active_bytes - legacy_bytes - superseded_bytes
    )
    limit_gb, limit_error = parse_limit_gb_var(limit_gb_raw)
    plat_label = platform or "unknown"

    report = {
        "total_active_bytes": total_active_bytes,
        "legacy_bytes": legacy_bytes,
        "matched_legacy": matched_legacy,
        "superseded_bytes": superseded_bytes,
        "matched_superseded": matched_superseded,
        "effective_active_bytes": effective_active_bytes,
        "archive_bytes": archive_bytes,
        "needed_bytes": needed_bytes,
        "limit_gb": limit_gb,
        "limit_bytes": None,
        "limit_error": limit_error,
        "reason": "",
        "message": "",
    }

    if limit_error is not None or limit_gb is None:
        detail = limit_error or "ACTIONS_CACHE_LIMIT_CONFIRMED_GB is not set"
        report["reason"] = "invalid_limit_var"
        report["message"] = (
            f"Cache save skipped ({plat_label}): {detail} "
            f"(needed {needed_bytes} bytes)."
        )
        return False, report

    limit_bytes = limit_gb * BYTES_PER_GB
    report["limit_bytes"] = limit_bytes

    if limit_bytes < needed_bytes:
        report["reason"] = "insufficient_capacity"
        report["message"] = (
            f"Cache save skipped ({plat_label}): configured limit "
            f"{limit_bytes} bytes ({limit_gb} GB) is below needed "
            f"{needed_bytes} bytes ({needed_bytes / BYTES_PER_GB:.2f} GB)."
        )
        return False, report

    report["reason"] = "ok"
    report["message"] = (
        f"Actions cache limit {limit_bytes} bytes ({limit_gb} GB) covers "
        f"needed {needed_bytes} bytes ({needed_bytes / BYTES_PER_GB:.2f} GB)."
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
        raw = resp.read().decode("utf-8")
        return resp.headers, json.loads(raw)


def fetch_usage(api_url, repo, token):
    """Read `active_caches_size_in_bytes` from `GET /repos/{owner}/{repo}/actions/cache/usage`."""
    base = api_url.rstrip("/")
    url = f"{base}/repos/{repo}/actions/cache/usage"
    _, payload = _github_get_json(url, token)
    if not isinstance(payload, dict):
        raise ValueError("cache/usage response must be a JSON object")
    val = payload.get("active_caches_size_in_bytes")
    if isinstance(val, bool) or not isinstance(val, int) or val < 0:
        raise ValueError(
            f"cache/usage response missing non-negative integer active_caches_size_in_bytes: {val!r}"
        )
    return val


def fetch_all_caches(api_url, repo, token):
    """Read all cache entries from `GET /repos/{owner}/{repo}/actions/caches?per_page=100`."""
    base = api_url.rstrip("/")
    url = f"{base}/repos/{repo}/actions/caches?per_page=100"
    entries = []
    while url:
        headers, payload = _github_get_json(url, token)
        if not isinstance(payload, dict) or not isinstance(
            payload.get("actions_caches"), list
        ):
            raise ValueError("actions/caches response missing actions_caches list")
        entries.extend(payload["actions_caches"])
        link_header = headers.get("Link") or headers.get("link") or ""
        m = _NEXT_LINK_RE.search(link_header)
        url = m.group(1) if m else None
    return entries


def _fmt_gb(num_bytes):
    return f"{num_bytes / BYTES_PER_GB:.2f} GB"


def _format_report_lines(platform, ok, report):
    limit_str = (
        f"{report['limit_bytes']:,} bytes ({report['limit_gb']} GB)"
        if report["limit_bytes"] is not None
        else f"unconfigured ({report['limit_error']})"
    )
    legacy_detail = (
        ", ".join(f"{k}: {s:,} B" for k, s in report["matched_legacy"])
        if report["matched_legacy"]
        else "none"
    )
    superseded_detail = (
        ", ".join(f"{k}: {s:,} B" for k, s in report["matched_superseded"])
        if report["matched_superseded"]
        else "none"
    )
    status = "ALLOWED" if ok else "SKIPPED"
    stdout_lines = [
        f"Actions cache capacity check ({platform}): {status}",
        f"  Current active usage (actions/cache/usage): {report['total_active_bytes']:,} bytes ({_fmt_gb(report['total_active_bytes'])})",
        f"  Legacy partial repository caches subtracted: {report['legacy_bytes']:,} bytes ({legacy_detail})",
        f"  Superseded same-platform full caches subtracted: {report['superseded_bytes']:,} bytes ({superseded_detail})",
        f"  Effective active usage after eviction/replacement: {report['effective_active_bytes']:,} bytes ({_fmt_gb(report['effective_active_bytes'])})",
        f"  This platform archive size (ARCHIVE_BYTES): {report['archive_bytes']:,} bytes ({_fmt_gb(report['archive_bytes'])})",
        f"  Needed capacity: {report['needed_bytes']:,} bytes ({_fmt_gb(report['needed_bytes'])})",
        f"  Confirmed repo cache limit (ACTIONS_CACHE_LIMIT_CONFIRMED_GB): {limit_str}",
        f"  Result: {report['message']}",
    ]
    md_lines = [
        "",
        f"#### Actions cache capacity check ({platform}): {status}",
        "",
        "| Metric | Bytes | Size (SI GB) |",
        "|---|---:|---:|",
        f"| Current active usage (`actions/cache/usage`) | {report['total_active_bytes']:,} | {_fmt_gb(report['total_active_bytes'])} |",
        f"| Legacy partial repo caches subtracted | -{report['legacy_bytes']:,} | -{_fmt_gb(report['legacy_bytes'])} |",
        f"| Superseded same-platform full caches subtracted | -{report['superseded_bytes']:,} | -{_fmt_gb(report['superseded_bytes'])} |",
        f"| Effective active usage | {report['effective_active_bytes']:,} | {_fmt_gb(report['effective_active_bytes'])} |",
        f"| This platform archives (`ARCHIVE_BYTES`) | {report['archive_bytes']:,} | {_fmt_gb(report['archive_bytes'])} |",
        f"| **Needed total** | **{report['needed_bytes']:,}** | **{_fmt_gb(report['needed_bytes'])}** |",
        f"| **Confirmed repo cache limit** | **{report['limit_bytes']:,}** | **{report['limit_gb']} GB** |",
        "",
        f"**Verdict:** {report['message']}",
        "",
    ]
    return stdout_lines, md_lines


def _write_summary(summary_file, lines):
    if not summary_file:
        return
    with open(summary_file, "a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def _write_output(output_file, key, value):
    if not output_file:
        return
    with open(output_file, "a", encoding="utf-8") as f:
        f.write(f"{key}={value}\n")


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


def main(argv=None):
    args = _parse_args(argv)
    summary_file = args.summary_file

    def fail_early(msg):
        _write_output(args.output_file, "allow_save", "false")
        print(f"::error::{msg}", file=sys.stderr, flush=True)
        _write_summary(
            summary_file,
            [
                "",
                f"#### Actions cache capacity check ({args.platform}): ERROR",
                "",
                f"**Error:** {msg}",
                "",
            ],
        )
        return 1

    _, limit_error = parse_limit_gb_var(args.limit_gb)
    if limit_error is not None:
        _write_output(args.output_file, "allow_save", "false")
        skip_msg = f"Cache save skipped ({args.platform}): {limit_error}."
        print(f"::warning::{skip_msg}", flush=True)
        _write_summary(summary_file, [skip_msg])
        return 0

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

    try:
        total_active_bytes = fetch_usage(args.api_url, args.repo, args.token)
    except Exception as exc:
        return fail_early(
            f"Failed to read Actions cache usage from GET /repos/{args.repo}/actions/cache/usage ({exc}); save is aborted."
        )

    try:
        caches = fetch_all_caches(args.api_url, args.repo, args.token)
    except Exception as exc:
        return fail_early(
            f"Failed to list Actions caches from GET /repos/{args.repo}/actions/caches ({exc}); save is aborted."
        )

    ok, report = evaluate_capacity(
        total_active_bytes=total_active_bytes,
        caches=caches,
        archive_bytes=archive_bytes,
        limit_gb_raw=args.limit_gb,
        platform=args.platform,
        current_lock_hash=args.lock_hash,
    )
    stdout_lines, md_lines = _format_report_lines(args.platform, ok, report)
    print("\n".join(stdout_lines), flush=True)

    if not ok:
        _write_output(args.output_file, "allow_save", "false")
        print(f"::warning::{report['message']}", flush=True)
        _write_summary(summary_file, [report["message"]])
        return 0

    _write_output(args.output_file, "allow_save", "true")
    _write_summary(summary_file, md_lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
