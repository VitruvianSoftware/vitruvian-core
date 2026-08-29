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

"""Repository scanner and naming convention orchestrator."""

import json
import os
import sys
from typing import Dict, List, Optional, Set, Tuple

try:
    from .rules import NamingViolation, ViolationSeverity
    from .rules.directories import validate_directory_name
    from .rules.source_files import validate_file_name
    from .rules.configs import validate_config_file_name, validate_workflow_yaml_content
    from .rules.bazel import validate_build_file_content, validate_starlark_file_name
except (ImportError, ValueError):
    from rules import NamingViolation, ViolationSeverity
    from rules.directories import validate_directory_name
    from rules.source_files import validate_file_name
    from rules.configs import validate_config_file_name, validate_workflow_yaml_content
    from rules.bazel import validate_build_file_content, validate_starlark_file_name


DEFAULT_IGNORES = {
    ".git",
    ".hg",
    ".svn",
    ".venv",
    "node_modules",
    "bazel-out",
    "bazel-bin",
    "bazel-testlogs",
    "bazel-vitruvian-core",
    ".remember",
    ".cache",
    "dist",
    "build",
    "coverage",
    "__pycache__",
    ".agents",
    ".next",
    ".turbo",
    ".astro",
    ".output",
    "out",
    ".ruff_cache",
    ".storybook",
    ".vitepress",
    ".worktrees",
    ".claude-worktrees",
    ".superpowers",
    ".swc",
    ".aspect",
    "sdk",
    "examples",
    "testdata",
}


class RepositoryNamingScanner:
    """Scans repository files and directories against naming convention rules."""

    def __init__(
        self,
        root_dir: str,
        ignores: Optional[Set[str]] = None,
        ignore_violation_fixtures: bool = True,
    ):
        self.root_dir = os.path.abspath(root_dir)
        self.ignores = ignores if ignores is not None else set(DEFAULT_IGNORES)
        self.ignore_violation_fixtures = ignore_violation_fixtures

    def should_ignore(self, rel_path: str) -> bool:
        """Check if relative path matches ignore patterns."""
        parts = rel_path.replace("\\", "/").split("/")
        for part in parts:
            if part in self.ignores:
                return True
        if self.ignore_violation_fixtures and "testdata/violations" in rel_path.replace(
            "\\", "/"
        ):
            return True
        return False

    def scan(self) -> List[NamingViolation]:
        """Perform a complete scan across directory trees, filenames, and configs."""
        violations: List[NamingViolation] = []

        for root, dirs, files in os.walk(self.root_dir):
            rel_root = os.path.relpath(root, self.root_dir)
            if rel_root == ".":
                rel_root = ""

            # Filter ignored directories in-place
            dirs[:] = [
                d for d in dirs if not self.should_ignore(os.path.join(rel_root, d))
            ]

            # 1. Validate directory name
            if rel_root:
                is_root = "/" not in rel_root.replace("\\", "/")
                violations.extend(validate_directory_name(rel_root, is_root=is_root))

            # 2. Validate files
            for file_name in files:
                rel_file = os.path.join(rel_root, file_name).replace("\\", "/")
                if self.should_ignore(rel_file):
                    continue

                abs_file = os.path.join(root, file_name)

                # Filename validation
                violations.extend(validate_file_name(rel_file))

                # Starlark file naming
                if file_name.endswith(".bzl"):
                    violations.extend(validate_starlark_file_name(rel_file))

                # Configuration and workflow content validation
                if file_name.endswith((".yaml", ".yml")):
                    violations.extend(validate_config_file_name(rel_file))
                    if ".github/workflows" in rel_file:
                        try:
                            with open(
                                abs_file, "r", encoding="utf-8", errors="ignore"
                            ) as f:
                                content = f.read()
                            violations.extend(
                                validate_workflow_yaml_content(rel_file, content)
                            )
                        except Exception:
                            pass

                # Bazel BUILD file target validation
                if file_name in ("BUILD", "BUILD.bazel"):
                    try:
                        with open(
                            abs_file, "r", encoding="utf-8", errors="ignore"
                        ) as f:
                            content = f.read()
                        violations.extend(
                            validate_build_file_content(rel_file, content)
                        )
                    except Exception:
                        pass

        return violations

    def format_report(
        self, violations: List[NamingViolation], output_format: str = "text"
    ) -> str:
        """Format scan results into text or JSON output."""
        if output_format == "json":
            data = {
                "total_violations": len(violations),
                "error_count": sum(
                    1 for v in violations if v.severity == ViolationSeverity.ERROR
                ),
                "warning_count": sum(
                    1 for v in violations if v.severity == ViolationSeverity.WARNING
                ),
                "violations": [v.to_dict() for v in violations],
            }
            return json.dumps(data, indent=2, ensure_ascii=False)

        lines: List[str] = []
        for v in sorted(violations, key=lambda x: (x.file_path, x.line_number or 0)):
            lines.append(v.format_line())

        error_cnt = sum(1 for v in violations if v.severity == ViolationSeverity.ERROR)
        warn_cnt = sum(1 for v in violations if v.severity == ViolationSeverity.WARNING)
        lines.append(
            f"\nNaming Audit Complete: {len(violations)} issues found ({error_cnt} errors, {warn_cnt} warnings)."
        )
        return "\n".join(lines)
