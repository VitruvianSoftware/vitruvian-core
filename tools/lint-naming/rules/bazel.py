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

"""Bazel target, rule, macro, and Starlark naming rules."""

import os
import re
from typing import List, Optional

try:
    from . import NamingViolation, ViolationSeverity
except (ImportError, ValueError):
    from rules import NamingViolation, ViolationSeverity

KEBAB_CASE_TARGET_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+)*$")
SNAKE_CASE_TARGET_RE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*$")
SHELL_TEST_TARGET_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*_test$")
STARLARK_FILE_RE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*\.bzl$")


BINARY_RULE_TYPES = {
    "sh_binary",
    "py_binary",
    "go_binary",
    "js_binary",
    "ts_binary",
    "rust_binary",
    "cc_binary",
    "java_binary",
    "swift_binary",
    "oci_image",
    "container_image",
    "macos_command_line_application",
}


def validate_starlark_file_name(file_path: str) -> List[NamingViolation]:
    """Validate .bzl Starlark file naming (must be snake_case)."""
    violations: List[NamingViolation] = []
    file_name = os.path.basename(file_path)
    if file_name.endswith(".bzl") and not STARLARK_FILE_RE.match(file_name):
        violations.append(
            NamingViolation(
                rule_id="BZL004",
                file_path=file_path,
                line_number=None,
                message=f"Starlark file '{file_name}' must use snake_case.",
                suggested_fix=file_name.replace("-", "_"),
                severity=ViolationSeverity.ERROR,
            )
        )
    return violations


def validate_bazel_target_name(
    file_path: str, target_name: str, rule_type: str, line_number: Optional[int] = None
) -> List[NamingViolation]:
    """Validate Bazel target name against target type casing rules."""
    violations: List[NamingViolation] = []

    # 1. Shell test target: <binary>_test
    if rule_type == "sh_test":
        if not SHELL_TEST_TARGET_RE.match(
            target_name
        ) and not SNAKE_CASE_TARGET_RE.match(target_name):
            violations.append(
                NamingViolation(
                    rule_id="BZL003",
                    file_path=file_path,
                    line_number=line_number,
                    message=f"Shell test target '{target_name}' should follow the '<binary>_test' convention.",
                    suggested_fix=f"{target_name}_test"
                    if not target_name.endswith("_test")
                    else None,
                    severity=ViolationSeverity.WARNING,
                )
            )
        return violations

    # 2. Go libraries and test targets (Gazelle generated): snake_case
    if rule_type in ("go_library", "go_test", "go_proto_library"):
        if not SNAKE_CASE_TARGET_RE.match(target_name):
            violations.append(
                NamingViolation(
                    rule_id="BZL002",
                    file_path=file_path,
                    line_number=line_number,
                    message=f"Go build target '{target_name}' must use snake_case per Gazelle standard.",
                    suggested_fix=target_name.replace("-", "_"),
                    severity=ViolationSeverity.ERROR,
                )
            )
        return violations

    # 3. Executable / CLI binary targets: kebab-case
    if (
        rule_type in BINARY_RULE_TYPES
        or rule_type.endswith("_binary")
        or rule_type.endswith("_image")
    ):
        if not KEBAB_CASE_TARGET_RE.match(target_name):
            violations.append(
                NamingViolation(
                    rule_id="BZL001",
                    file_path=file_path,
                    line_number=line_number,
                    message=f"CLI binary target '{target_name}' ({rule_type}) must use kebab-case.",
                    suggested_fix=target_name.replace("_", "-"),
                    severity=ViolationSeverity.ERROR,
                )
            )
        return violations

    return violations


def validate_build_file_content(file_path: str, content: str) -> List[NamingViolation]:
    """Parse BUILD/BUILD.bazel file content and validate declared target names."""
    violations: List[NamingViolation] = []
    if not content.strip():
        return violations

    import ast

    parsed_with_ast = False
    try:
        tree = ast.parse(content, filename=file_path)
        parsed_with_ast = True
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                rule_type = None
                if isinstance(node.func, ast.Name):
                    rule_type = node.func.id
                elif isinstance(node.func, ast.Attribute):
                    rule_type = node.func.attr

                if not rule_type or rule_type in (
                    "load",
                    "glob",
                    "select",
                    "package",
                    "licenses",
                ):
                    continue

                for kw in node.keywords:
                    if kw.arg == "name":
                        target_name = None
                        if isinstance(kw.value, ast.Constant) and isinstance(
                            kw.value.value, str
                        ):
                            target_name = kw.value.value
                        elif hasattr(ast, "Str") and isinstance(kw.value, ast.Str):
                            target_name = kw.value.s

                        if target_name:
                            line_no = getattr(kw, "lineno", node.lineno)
                            violations.extend(
                                validate_bazel_target_name(
                                    file_path, target_name, rule_type, line_no
                                )
                            )
    except Exception:
        parsed_with_ast = False

    if not parsed_with_ast:
        # Fallback multi-line regex block scanner for Starlark rule calls
        call_pattern = re.compile(r"([a-zA-Z0-9_]+)\s*\(([^)]*)\)", re.DOTALL)
        for match in call_pattern.finditer(content):
            rule_type = match.group(1)
            if rule_type in ("load", "glob", "select", "package", "licenses"):
                continue
            call_body = match.group(2)
            name_match = re.search(r'name\s*=\s*["\']([^"\']+)["\']', call_body)
            if name_match:
                target_name = name_match.group(1)
                line_no = content[: match.start() + name_match.start()].count("\n") + 1
                violations.extend(
                    validate_bazel_target_name(
                        file_path, target_name, rule_type, line_no
                    )
                )

    return violations
