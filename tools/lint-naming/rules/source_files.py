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

"""Source and asset file naming rules."""

import os
import re
from typing import List
try:
    from . import NamingViolation, ViolationSeverity
except (ImportError, ValueError):
    from rules import NamingViolation, ViolationSeverity

# Patterns
GO_FILE_RE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*(_test)?\.go$")
PY_FILE_RE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*\.py$")
SHELL_FILE_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*(_test)?\.sh$")
PASCAL_CASE_FILE_RE = re.compile(r"^[A-Z][a-zA-Z0-9]*(\.[A-Z][a-zA-Z0-9]*)*(\.test|\.spec|\.d)?\.(tsx|jsx|swift|ts|js)$")
TS_SEGMENT_RE = r"([a-z0-9]+(-[a-z0-9]+)*|[a-z0-9]+([A-Z][a-z0-9]*)*|[A-Z][a-zA-Z0-9]*)"
TS_LIB_RE = re.compile(rf"^{TS_SEGMENT_RE}(\.{TS_SEGMENT_RE})*(\.test|\.spec|\.d)?\.(ts|tsx|js|jsx|mjs|cjs)$")
UPPER_DOC_RE = re.compile(r"^[A-Z0-9_-]+\.md$")
KEBAB_DOC_RE = re.compile(r"^[a-z0-9.]+(-[a-z0-9.]+)*\.md$")
DATED_DOC_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9-.]+(\.md|\.yaml|\.json)$")

NEXTJS_APP_ROUTER_FILES = {
    "page.tsx", "layout.tsx", "loading.tsx", "error.tsx", "not-found.tsx",
    "route.ts", "template.tsx", "default.tsx", "global-error.tsx",
    "middleware.ts", "instrumentation.ts", "opengraph-image.tsx", "twitter-image.tsx",
    "sitemap.ts", "robots.ts", "icon.tsx", "apple-icon.tsx",
}

CANONICAL_UPPER_DOCS = {
    "README.md", "AGENTS.md", "PROJECT.md", "SCOPE.md", "DISPATCH.md",
    "BRIEFING.md", "TEST_INFRA.md", "TEST_READY.md", "CONTRIBUTING.md",
    "LICENSE.md", "CHANGELOG.md", "SECURITY.md", "MAINTAINERS.md",
    "BUILD.bazel", "WORKSPACE.bazel", "MODULE.bazel", "BUILD", "WORKSPACE",
}


def validate_file_name(file_path: str) -> List[NamingViolation]:
    """Validate a file path against naming convention standards."""
    violations: List[NamingViolation] = []
    normalized = file_path.strip("/").replace("\\", "/")
    file_name = os.path.basename(normalized)

    # Ignore system/tool files
    if file_name.startswith(".DS_Store") or file_name in CANONICAL_UPPER_DOCS:
        return violations

    # Multi-dot handling: split base name and extension
    _, ext = os.path.splitext(file_name)
    ext = ext.lower()

    # 1. Go source files: snake_case only, NO hyphens
    if ext == ".go":
        if not GO_FILE_RE.match(file_name):
            violations.append(
                NamingViolation(
                    rule_id="GO001",
                    file_path=normalized,
                    line_number=None,
                    message=f"Go source file '{file_name}' must use snake_case. Hyphens are forbidden in Go source files.",
                    suggested_fix=file_name.replace("-", "_"),
                    severity=ViolationSeverity.ERROR,
                )
            )

    # 2. Python files: snake_case only, NO hyphens (except dunder)
    elif ext == ".py":
        if file_name.startswith("__") and file_name.endswith("__.py"):
            return violations
        if not PY_FILE_RE.match(file_name):
            violations.append(
                NamingViolation(
                    rule_id="PY001",
                    file_path=normalized,
                    line_number=None,
                    message=f"Python module '{file_name}' must use snake_case. Hyphens break Python import statements.",
                    suggested_fix=file_name.replace("-", "_"),
                    severity=ViolationSeverity.ERROR,
                )
            )

    # 3. Shell scripts: kebab-case with optional _test.sh
    elif ext in (".sh", ".bash", ".zsh"):
        if not SHELL_FILE_RE.match(file_name):
            # Check if using snake_case instead of kebab-case
            violations.append(
                NamingViolation(
                    rule_id="SH001",
                    file_path=normalized,
                    line_number=None,
                    message=f"Shell script '{file_name}' must use kebab-case (with optional _test.sh suffix).",
                    suggested_fix=file_name.replace("_test.sh", "@@TEST@@").replace("_", "-").replace("@@TEST@@", "_test.sh"),
                    severity=ViolationSeverity.ERROR,
                )
            )

    # 4. React / UI files (.tsx, .jsx)
    elif ext in (".tsx", ".jsx"):
        if file_name in NEXTJS_APP_ROUTER_FILES or file_name.startswith("__"):
            return violations
        if not PASCAL_CASE_FILE_RE.match(file_name) and not TS_LIB_RE.match(file_name):
            violations.append(
                NamingViolation(
                    rule_id="TSX001",
                    file_path=normalized,
                    line_number=None,
                    message=f"React component/view '{file_name}' must use PascalCase (or kebab-case for pages/layouts).",
                    suggested_fix=file_name.replace("_", "-"),
                    severity=ViolationSeverity.WARNING,
                )
            )

    # 5. TypeScript / JavaScript library files (.ts, .js, .mjs, .cjs)
    elif ext in (".ts", ".js", ".mjs", ".cjs"):
        if file_name.startswith("__") or file_name.endswith(".d.ts") or file_name in NEXTJS_APP_ROUTER_FILES:
            return violations
        if not TS_LIB_RE.match(file_name):
            violations.append(
                NamingViolation(
                    rule_id="TS001",
                    file_path=normalized,
                    line_number=None,
                    message=f"TypeScript/JavaScript file '{file_name}' should use kebab-case or camelCase.",
                    suggested_fix=file_name.replace("_", "-"),
                    severity=ViolationSeverity.ERROR,
                )
            )

    # 6. Swift files (.swift)
    elif ext == ".swift":
        if not PASCAL_CASE_FILE_RE.match(file_name):
            violations.append(
                NamingViolation(
                    rule_id="SWIFT001",
                    file_path=normalized,
                    line_number=None,
                    message=f"Swift file '{file_name}' must use PascalCase.",
                    severity=ViolationSeverity.ERROR,
                )
            )

    # 7. Markdown Documentation (.md)
    elif ext == ".md":
        if not KEBAB_DOC_RE.match(file_name) and not UPPER_DOC_RE.match(file_name) and not DATED_DOC_RE.match(file_name):
            violations.append(
                NamingViolation(
                    rule_id="DOC001",
                    file_path=normalized,
                    line_number=None,
                    message=f"Documentation file '{file_name}' must use kebab-case or UPPERCASE.",
                    suggested_fix=file_name.lower().replace("_", "-"),
                    severity=ViolationSeverity.ERROR,
                )
            )

    return violations
