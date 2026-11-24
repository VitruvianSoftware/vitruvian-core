# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Confirm a newly saved `-repository-full-` cache entry on refs/heads/main, then prune superseded and legacy ones."""

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cache_capacity_guard import (
    GitHubCacheApi,
    _write_lines,
    add_common_args,
    full_repo_cache_prefix,
    is_legacy_partial_repo_cache_key,
    is_superseded_full_repo_cache_key,
)


def confirm_and_prune_superseded_caches(
    api,
    platform,
    current_lock_hash,
    max_confirm_attempts=5,
    retry_delay_seconds=2.0,
    sleep_fn=time.sleep,
):
    """Confirm `new_key` exists on `refs/heads/main`, then delete superseded and legacy same-platform entries."""
    if not platform or not current_lock_hash:
        raise ValueError("platform and current_lock_hash must be non-empty")

    new_key = f"{full_repo_cache_prefix(platform)}{current_lock_hash}"
    confirmed = False
    last_error = None

    for attempt in range(1, max_confirm_attempts + 1):
        try:
            entries = api.list_caches(key=new_key)
        except Exception as exc:
            last_error = str(exc)
            entries = []
        if any(
            isinstance(e, dict)
            and e.get("key") == new_key
            and e.get("ref") == "refs/heads/main"
            for e in entries
        ):
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
                f"New cache key {new_key!r} on refs/heads/main was not confirmed by GET /actions/caches "
                f"after {max_confirm_attempts} attempt(s){detail}; deleting nothing."
            ),
        }

    try:
        all_entries = api.list_caches()
    except Exception as exc:
        return {
            "confirmed": True,
            "new_key": new_key,
            "deleted": [],
            "errors": [
                f"Failed to list caches for pruning after confirming {new_key!r}: {exc}"
            ],
            "warning": None,
        }
    deleted = []
    errors = []
    for entry in all_entries:
        if not isinstance(entry, dict):
            continue
        key = entry.get("key")
        if not (
            is_superseded_full_repo_cache_key(key, platform, current_lock_hash)
            or is_legacy_partial_repo_cache_key(key, platform)
        ):
            continue
        cache_id = entry.get("id")
        if isinstance(cache_id, bool) or not isinstance(cache_id, int):
            errors.append(
                f"Skipping prunable entry {key!r} with invalid id {cache_id!r}"
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


def _parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    add_common_args(p)
    p.add_argument("--max-confirm-attempts", type=int, default=5)
    p.add_argument("--retry-delay-seconds", type=float, default=2.0)
    return p.parse_args(argv)


def main(argv=None, sleep_fn=time.sleep):
    args = _parse_args(argv)

    if args.ref != "refs/heads/main":
        msg = f"Refusing to prune caches on non-main ref ({args.ref!r}); deleting nothing."
        print(f"::warning::{msg}", flush=True)
        _write_lines(args.summary_file, [msg])
        return 0

    err_msg = None
    if not args.repo or "/" not in args.repo:
        err_msg = f"GITHUB_REPOSITORY/--repo is missing or invalid ({args.repo!r})."
    elif not args.token:
        err_msg = "GH_TOKEN/--token is empty; cannot confirm or prune caches."
    elif not args.platform or not args.lock_hash:
        err_msg = f"platform ({args.platform!r}) and lock-hash ({args.lock_hash!r}) are required."
    if err_msg is not None:
        print(f"::error::{err_msg}", file=sys.stderr, flush=True)
        return 1

    api = GitHubCacheApi(args.api_url, args.repo, args.token)
    result = confirm_and_prune_superseded_caches(
        api=api,
        platform=args.platform,
        current_lock_hash=args.lock_hash,
        max_confirm_attempts=args.max_confirm_attempts,
        retry_delay_seconds=args.retry_delay_seconds,
        sleep_fn=sleep_fn,
    )

    if not result["confirmed"]:
        print(f"::warning::{result['warning']}", flush=True)
        _write_lines(args.summary_file, [result["warning"]])
        return 0

    for err in result["errors"]:
        print(f"::warning::{err}", flush=True)

    n_err = len(result["errors"])
    if result["deleted"]:
        items = ", ".join(f"{k} (id={cid})" for cid, k, _s in result["deleted"])
        msg = f"Confirmed {result['new_key']}; pruned {len(result['deleted'])} superseded/legacy {args.platform} cache(s): {items}."
        if n_err:
            msg += f" ({n_err} warning(s))"
    elif n_err:
        msg = (
            f"Confirmed {result['new_key']}; pruning finished with {n_err} warning(s)."
        )
    else:
        msg = f"Confirmed {result['new_key']}; no superseded or legacy {args.platform} caches to prune."

    print(msg, flush=True)
    _write_lines(args.summary_file, [msg])
    return 0


if __name__ == "__main__":
    sys.exit(main())
