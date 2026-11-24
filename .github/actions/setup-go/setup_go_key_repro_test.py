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

"""Stdlib-only test reproducing setup-go cache keys against the repository tree."""

from __future__ import annotations

import os
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cache_key

LIVE_SENTRY_APPLY_HASH = (
    "da94469fa4ddf701df9f3126949c31ce800cd8e7e5e4638d9395313c4e32886a"
)
LIVE_SENTRY_APPLY_KEY = (
    f"setup-go-Linux-x64-ubuntu26-go-1.26.10-{LIVE_SENTRY_APPLY_HASH}"
)

JOB_KEY_SPECS = [
    (
        "go-lint-devx",
        "apps/cli/vitruvian-devx/go.mod",
        "apps/cli/vitruvian-devx/go.sum",
    ),
    (
        "go-test-infra",
        "go.mod",
        "infrastructure/pulumi/**/go.sum\n"
        "apps/*/*/infra/**/go.sum\n"
        "packages/pulumi/examples/**/go.sum",
    ),
    (
        "example-build",
        "go.mod",
        cache_key.DEFAULT_DEPENDENCY_PATH,
    ),
    (
        "pagerduty-production",
        "infrastructure/pulumi/platform/pagerduty/go.mod",
        "infrastructure/pulumi/platform/pagerduty/go.sum",
    ),
    (
        "stripe-sandbox / stripe-production",
        "infrastructure/pulumi/platform/stripe/go.mod",
        "infrastructure/pulumi/platform/stripe/go.sum",
    ),
    (
        "sentry-apply (apply)",
        "infrastructure/pulumi/platform/sentry/go.mod",
        "infrastructure/pulumi/platform/sentry/go.sum\n"
        "infrastructure/pulumi/platform/sentry-pagerduty/go.sum",
    ),
]


def _find_repo_root() -> Path:
    env_ws = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if env_ws:
        p = Path(env_ws).resolve()
        if (p / "go.mod").is_file() and (p / "infrastructure" / "pulumi").is_dir():
            return p
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "go.mod").is_file() and (
            parent / "infrastructure" / "pulumi"
        ).is_dir():
            return parent
    raise RuntimeError(f"Could not locate repository root from {here}")


def _read_go_version(go_mod_path: Path) -> str:
    for line in go_mod_path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^go\s+([^\s]+)$", line.strip())
        if m:
            return m.group(1)
    raise ValueError(f"No go directive found in {go_mod_path}")


class SetupGoKeyReproTest(unittest.TestCase):
    def test_reproduce_all_converted_job_keys(self) -> None:
        """Compute setup-go cache keys for all six converted jobs against the worktree.

        Asserts that sentry-apply (apply) matches the live refs/heads/main cache entry
        (2 files -> LIVE_SENTRY_APPLY_KEY). For the other five converted jobs, prints
        the computed hash and file count without pinning them because they have no
        live main entry and move whenever their go.sum or go.mod files change.
        """
        repo_root = _find_repo_root()
        checked_live_sentry = False
        for job_name, go_version_file, dep_pattern in JOB_KEY_SPECS:
            go_version = _read_go_version(repo_root / go_version_file)
            digest, count = cache_key.glob_hash_files(dep_pattern, repo_root)
            self.assertGreater(count, 0, f"{job_name} matched 0 files")
            self.assertEqual(len(digest), 64, f"{job_name} invalid digest {digest!r}")
            self.assertRegex(
                digest, r"^[0-9a-f]{64}$", f"{job_name} non-hex digest {digest!r}"
            )
            full_key = cache_key.build_cache_key(
                runner_os="Linux",
                arch="x64",
                image_os="ubuntu26",
                go_version=go_version,
                file_hash=digest,
            )
            if job_name == "sentry-apply (apply)":
                self.assertEqual(count, 2)
                self.assertEqual(digest, LIVE_SENTRY_APPLY_HASH)
                self.assertEqual(full_key, LIVE_SENTRY_APPLY_KEY)
                checked_live_sentry = True
                print(
                    f"[MATCHED LIVE] {job_name}: count={count} hash={digest} key={full_key}"
                )
            else:
                print(
                    f"[UNPINNED] {job_name}: count={count} hash={digest} key={full_key}"
                )
        self.assertTrue(
            checked_live_sentry, "sentry-apply live assertion did not execute"
        )


if __name__ == "__main__":
    unittest.main()
