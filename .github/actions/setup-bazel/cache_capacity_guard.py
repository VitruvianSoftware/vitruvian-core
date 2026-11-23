# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Fail-safe Actions cache capacity guard for bazel-repo-cache.yaml.

Reads the repository's current Actions cache usage, lists active cache entries
to subtract legacy partial `setup-bazel-1-*-repository-<hex>` entries (which are
no longer read once `-repository-full-` lands), reads the repository's Actions
cache storage limit (`GET /repos/{owner}/{repo}/actions/cache/storage-limit`),
and refuses to save if the limit cannot be read or is smaller than `needed`.
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


def is_legacy_partial_repo_cache_key(key):
    """True for legacy partial `-repository-<hex>` keys (not `-repository-full-`)."""
    if not isinstance(key, str):
        return False
    return (
        bool(LEGACY_PARTIAL_REPO_KEY_RE.match(key)) and "-repository-full-" not in key
    )


def compute_needed_bytes(total_active_bytes, caches, archive_bytes):
    """Return `(needed_bytes, legacy_bytes, matched_legacy)` in exact bytes."""
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
    for entry in caches:
        if not isinstance(entry, dict):
            continue
        key = entry.get("key", "")
        if not is_legacy_partial_repo_cache_key(key):
            continue
        size = entry.get("size_in_bytes")
        if isinstance(size, bool) or not isinstance(size, int) or size < 0:
            raise ValueError(
                f"invalid size_in_bytes for legacy cache {key!r}: {size!r}"
            )
        matched_legacy.append((key, size))
        legacy_bytes += size

    effective_active_bytes = max(0, total_active_bytes - legacy_bytes)
    needed_bytes = effective_active_bytes + archive_bytes
    return needed_bytes, legacy_bytes, matched_legacy


def parse_limit_bytes(payload):
    """Parse `max_cache_size_gb` from the storage-limit JSON payload to bytes."""
    if not isinstance(payload, dict):
        raise ValueError("storage-limit response must be a JSON object")
    val = payload.get("max_cache_size_gb")
    if isinstance(val, bool) or not isinstance(val, int) or val <= 0:
        raise ValueError(
            f"storage-limit response missing positive integer max_cache_size_gb: {val!r}"
        )
    return val * BYTES_PER_GB


def evaluate_capacity(
    total_active_bytes,
    caches,
    archive_bytes,
    limit_gb,
    limit_error=None,
):
    """Decide whether saving `archive_bytes` fits within the repo cache limit."""
    needed_bytes, legacy_bytes, matched_legacy = compute_needed_bytes(
        total_active_bytes, caches, archive_bytes
    )
    effective_active_bytes = max(0, total_active_bytes - legacy_bytes)

    report = {
        "total_active_bytes": total_active_bytes,
        "legacy_bytes": legacy_bytes,
        "matched_legacy": matched_legacy,
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
        detail = limit_error or "storage-limit endpoint returned no limit"
        report["reason"] = "limit_unknown"
        report["message"] = (
            f"Actions cache size limit is unknown ({detail}); save is refused "
            f"(needed {needed_bytes} bytes)."
        )
        return False, report

    limit_bytes = parse_limit_bytes({"max_cache_size_gb": limit_gb})
    report["limit_bytes"] = limit_bytes

    if limit_bytes < needed_bytes:
        report["reason"] = "insufficient_capacity"
        report["message"] = (
            f"Actions cache limit {limit_bytes} bytes ({limit_gb} GB) is below "
            f"needed {needed_bytes} bytes ({needed_bytes / BYTES_PER_GB:.2f} GB); "
            f"save is refused."
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


def fetch_storage_limit(api_url, repo, token):
    """Read `max_cache_size_gb` from `GET /repos/{owner}/{repo}/actions/cache/storage-limit`.

    Returns `(limit_gb, None)` on success or `(None, error_detail)` on any failure.
    Never defaults or guesses a limit.
    """
    base = api_url.rstrip("/")
    url = f"{base}/repos/{repo}/actions/cache/storage-limit"
    try:
        _, payload = _github_get_json(url, token)
    except urllib.error.HTTPError as exc:
        body_msg = ""
        try:
            body_raw = exc.read().decode("utf-8", errors="replace")
            body_json = json.loads(body_raw)
            if isinstance(body_json, dict) and body_json.get("message"):
                body_msg = str(body_json["message"])
            else:
                body_msg = body_raw.strip()
        except Exception:
            body_msg = str(exc.reason)
        return (
            None,
            f"GET /repos/{repo}/actions/cache/storage-limit returned HTTP {exc.code}: {body_msg}",
        )
    except (urllib.error.URLError, OSError, json.JSONDecodeError, ValueError) as exc:
        return None, f"GET /repos/{repo}/actions/cache/storage-limit failed: {exc}"

    try:
        limit_bytes = parse_limit_bytes(payload)
    except ValueError as exc:
        return (
            None,
            f"GET /repos/{repo}/actions/cache/storage-limit returned invalid payload: {exc}",
        )
    return limit_bytes // BYTES_PER_GB, None


def _fmt_gb(num_bytes):
    return f"{num_bytes / BYTES_PER_GB:.2f} GB"


def _format_report_lines(platform, ok, report):
    limit_str = (
        f"{report['limit_bytes']:,} bytes ({report['limit_gb']} GB)"
        if report["limit_bytes"] is not None
        else f"unknown ({report['limit_error']})"
    )
    legacy_detail = (
        ", ".join(f"{k}: {s:,} B" for k, s in report["matched_legacy"])
        if report["matched_legacy"]
        else "none"
    )
    status = "ALLOWED" if ok else "REFUSED"
    stdout_lines = [
        f"Actions cache capacity check ({platform}): {status}",
        f"  Current active usage (actions/cache/usage): {report['total_active_bytes']:,} bytes ({_fmt_gb(report['total_active_bytes'])})",
        f"  Legacy partial repository caches subtracted: {report['legacy_bytes']:,} bytes ({legacy_detail})",
        f"  Effective active usage after legacy eviction: {report['effective_active_bytes']:,} bytes ({_fmt_gb(report['effective_active_bytes'])})",
        f"  This platform archive size (ARCHIVE_BYTES): {report['archive_bytes']:,} bytes ({_fmt_gb(report['archive_bytes'])})",
        f"  Needed capacity: {report['needed_bytes']:,} bytes ({_fmt_gb(report['needed_bytes'])})",
        f"  Configured repo cache limit: {limit_str}",
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
        f"| Effective active usage | {report['effective_active_bytes']:,} | {_fmt_gb(report['effective_active_bytes'])} |",
        f"| This platform archives (`ARCHIVE_BYTES`) | {report['archive_bytes']:,} | {_fmt_gb(report['archive_bytes'])} |",
        f"| **Needed total** | **{report['needed_bytes']:,}** | **{_fmt_gb(report['needed_bytes'])}** |",
        (
            f"| **Repo cache limit** | **{report['limit_bytes']:,}** | **{report['limit_gb']} GB** |"
            if report["limit_bytes"] is not None
            else f"| **Repo cache limit** | **unknown** | **{report['limit_error']}** |"
        ),
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
    p.add_argument(
        "--api-url",
        default=os.environ.get("GITHUB_API_URL", "https://api.github.com"),
    )
    p.add_argument("--token", default=os.environ.get("GH_TOKEN", ""))
    p.add_argument("--summary-file", default=os.environ.get("GITHUB_STEP_SUMMARY", ""))
    return p.parse_args(argv)


def main(argv=None):
    args = _parse_args(argv)
    summary_file = args.summary_file

    def fail_early(msg):
        print(f"::error::{msg}", file=sys.stderr, flush=True)
        _write_summary(
            summary_file,
            [
                "",
                f"#### Actions cache capacity check ({args.platform}): REFUSED",
                "",
                f"**Error:** {msg}",
                "",
            ],
        )
        return 1

    if not args.repo or "/" not in args.repo:
        return fail_early(
            f"GITHUB_REPOSITORY/--repo is missing or invalid ({args.repo!r}); save is refused."
        )
    if not args.token:
        return fail_early(
            "GH_TOKEN/--token is empty; cannot read Actions cache usage or limit; save is refused."
        )
    try:
        archive_bytes = int(args.archive_bytes)
        if archive_bytes < 0:
            raise ValueError("negative")
    except (TypeError, ValueError):
        return fail_early(
            f"ARCHIVE_BYTES/--archive-bytes is missing or invalid ({args.archive_bytes!r}); save is refused."
        )

    try:
        total_active_bytes = fetch_usage(args.api_url, args.repo, args.token)
    except Exception as exc:
        return fail_early(
            f"Failed to read Actions cache usage from GET /repos/{args.repo}/actions/cache/usage ({exc}); save is refused."
        )

    try:
        caches = fetch_all_caches(args.api_url, args.repo, args.token)
    except Exception as exc:
        return fail_early(
            f"Failed to list Actions caches from GET /repos/{args.repo}/actions/caches ({exc}); save is refused."
        )

    limit_gb, limit_error = fetch_storage_limit(args.api_url, args.repo, args.token)

    ok, report = evaluate_capacity(
        total_active_bytes=total_active_bytes,
        caches=caches,
        archive_bytes=archive_bytes,
        limit_gb=limit_gb,
        limit_error=limit_error,
    )
    stdout_lines, md_lines = _format_report_lines(args.platform, ok, report)
    print("\n".join(stdout_lines), flush=True)
    _write_summary(summary_file, md_lines)

    if not ok:
        print(f"::error::{report['message']}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
