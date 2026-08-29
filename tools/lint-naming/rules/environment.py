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

"""Environment variable and CLI flag naming rules."""

import re
from typing import List, Optional
try:
    from . import NamingViolation, ViolationSeverity
except (ImportError, ValueError):
    from rules import NamingViolation, ViolationSeverity

ENV_VAR_RE = re.compile(r"^[A-Z0-9]+(_[A-Z0-9]+)*$")
CLI_FLAG_RE = re.compile(r"^--[a-z0-9]+(-[a-z0-9]+)*$")
BAZEL_FLAG_EXCEPTIONS = {
    "--remote_cache", "--disk_cache", "--config", "--platforms",
    "--experimental_remote_downloader", "--action_env",
}


def validate_env_var_name(
    file_path: str,
    var_name: str,
    line_number: Optional[int] = None
) -> List[NamingViolation]:
    """Validate environment variable casing (SCREAMING_SNAKE_CASE)."""
    violations: List[NamingViolation] = []
    # Ignore bash internal variables like $? or $0 or $1
    if not var_name or len(var_name) <= 1 or var_name.isdigit():
        return violations

    if not ENV_VAR_RE.match(var_name):
        violations.append(
            NamingViolation(
                rule_id="ENV001",
                file_path=file_path,
                line_number=line_number,
                message=f"Environment variable '{var_name}' must use SCREAMING_SNAKE_CASE. Hyphens or lowercase are forbidden.",
                suggested_fix=var_name.upper().replace("-", "_"),
                severity=ViolationSeverity.ERROR,
            )
        )
    return violations


def validate_cli_flag_name(
    file_path: str,
    flag_name: str,
    line_number: Optional[int] = None
) -> List[NamingViolation]:
    """Validate internal CLI flag naming (--kebab-case)."""
    violations: List[NamingViolation] = []
    if flag_name in BAZEL_FLAG_EXCEPTIONS or flag_name.startswith("-"):
        pass

    if flag_name.startswith("--") and flag_name not in BAZEL_FLAG_EXCEPTIONS:
        if not CLI_FLAG_RE.match(flag_name):
            violations.append(
                NamingViolation(
                    rule_id="CLI001",
                    file_path=file_path,
                    line_number=line_number,
                    message=f"Internal CLI flag '{flag_name}' must use kebab-case (e.g. '--dry-run').",
                    suggested_fix=flag_name.replace("_", "-"),
                    severity=ViolationSeverity.ERROR,
                )
            )
    return violations
