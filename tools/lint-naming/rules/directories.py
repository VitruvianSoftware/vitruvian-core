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

"""Directory naming rules."""

import re
from typing import List, Optional
try:
    from . import NamingViolation, ViolationSeverity
except (ImportError, ValueError):
    from rules import NamingViolation, ViolationSeverity

# Patterns
KEBAB_CASE_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
SNAKE_CASE_RE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*$")
PASCAL_CASE_RE = re.compile(r"^[A-Z][a-zA-Z0-9]*$")
PRISMA_MIGRATION_RE = re.compile(r"^\d{14}_[a-z0-9_]+$")
DYNAMIC_ROUTE_RE = re.compile(r"^(\[[a-zA-Z0-9_-]+\]|\[\.\.\.[a-zA-Z0-9_-]+\]|\([a-zA-Z0-9_-]+\))$")
DUNDER_DIR_RE = re.compile(r"^__[a-zA-Z0-9_-]+__$")

# Permitted hidden directory prefixes
ALLOWED_DOT_DIRS = {
    ".aspect", ".claude", ".devcontainer", ".github", ".vscode",
    ".husky", ".remember", ".agents", ".agent", ".gemini", ".changeset",
    ".next", ".turbo", ".astro", ".superpowers", ".worktrees",
    ".claude-worktrees", ".ruff_cache", ".storybook", ".vitepress", ".swc",
}

# Subtrees with ecosystem-specific casing overrides
GO_PACKAGE_DIR_ROOTS = (
    "infrastructure/pulumi",
    "pulumi/library/go",
    "pulumi/examples",
    "devx",
    "homelab",
    "pkg",
)

SWIFT_DIR_ROOTS = (
    "nexus-agent/macos",
    "macos",
    "Sources",
    "Tests",
)


def validate_directory_name(dir_path: str, is_root: bool = False) -> List[NamingViolation]:
    """Validate directory name against monorepo naming conventions."""
    violations: List[NamingViolation] = []
    normalized = dir_path.strip("/").replace("\\", "/")
    if not normalized or normalized == ".":
        return violations

    parts = normalized.split("/")
    dir_name = parts[-1]

    # Ignore system / VCS directories
    if dir_name in (".git", ".hg", ".svn", "node_modules", "bazel-out", "bazel-bin", "bazel-testlogs"):
        return violations

    # Allowed dot-prefixed directories
    if dir_name.startswith("."):
        if dir_name in ALLOWED_DOT_DIRS or dir_name.startswith(".git"):
            return violations
        violations.append(
            NamingViolation(
                rule_id="DIR001",
                file_path=normalized,
                line_number=None,
                message=f"Disallowed dot-prefixed directory '{dir_name}'.",
                severity=ViolationSeverity.ERROR,
            )
        )
        return violations

    # React / Next.js dynamic routing or test fixtures
    if DYNAMIC_ROUTE_RE.match(dir_name) or DUNDER_DIR_RE.match(dir_name):
        return violations

    # Prisma migration directory
    if PRISMA_MIGRATION_RE.match(dir_name):
        return violations

    # Swift ecosystem check
    if any(normalized == sr or normalized.startswith(sr + "/") or dir_name == sr for sr in SWIFT_DIR_ROOTS):
        if PASCAL_CASE_RE.match(dir_name) or KEBAB_CASE_RE.match(dir_name) or SNAKE_CASE_RE.match(dir_name):
            return violations

    # Go package directory check (Go allows snake_case where package identifiers require it)
    if any(normalized == gr or normalized.startswith(gr + "/") for gr in GO_PACKAGE_DIR_ROOTS):
        if SNAKE_CASE_RE.match(dir_name) or KEBAB_CASE_RE.match(dir_name):
            return violations

    # Root directories must be kebab-case (single-word lowercase counts as valid kebab)
    if is_root or len(parts) == 1:
        if not KEBAB_CASE_RE.match(dir_name):
            violations.append(
                NamingViolation(
                    rule_id="DIR002",
                    file_path=normalized,
                    line_number=None,
                    message=f"Root directory '{dir_name}' must be kebab-case (lowercase alphanumeric with hyphens).",
                    suggested_fix=dir_name.lower().replace("_", "-"),
                    severity=ViolationSeverity.ERROR,
                )
            )
        return violations

    # Standard package and subtree directories: default is kebab-case
    if not KEBAB_CASE_RE.match(dir_name):
        violations.append(
            NamingViolation(
                rule_id="DIR003",
                file_path=normalized,
                line_number=None,
                message=f"Directory '{dir_name}' has invalid casing. Expected kebab-case.",
                suggested_fix=dir_name.lower().replace("_", "-"),
                severity=ViolationSeverity.ERROR,
            )
        )

    return violations
