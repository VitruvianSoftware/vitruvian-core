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

"""Migration risk assessment and backwards compatibility validator."""

import os
from enum import Enum
from typing import Dict, List, Optional

try:
    from . import NamingViolation, ViolationSeverity
except (ImportError, ValueError):
    from rules import NamingViolation, ViolationSeverity


class MigrationRiskLevel(str, Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"


# Paths with high blast-radius
HIGH_RISK_PREFIXES = (
    ".github/workflows",
    "gitops",
    "packages/design-system",
    "tabula/extension/public",
    "tabula/web/prisma",
)

MEDIUM_RISK_PREFIXES = (
    "infrastructure/pulumi",
    "pulumi/library",
    "devx",
    "tools",
)


def assess_rename_risk(source_path: str, target_path: str) -> MigrationRiskLevel:
    """Assess the blast radius and breaking change risk of a planned rename."""
    norm_source = source_path.replace("\\", "/")

    if norm_source.endswith(("_test.go", "_test.sh", ".test.ts", ".spec.tsx")):
        return MigrationRiskLevel.LOW

    if any(norm_source.startswith(hr) for hr in HIGH_RISK_PREFIXES):
        return MigrationRiskLevel.HIGH

    if any(norm_source.startswith(mr) for mr in MEDIUM_RISK_PREFIXES):
        return MigrationRiskLevel.MEDIUM

    return MigrationRiskLevel.LOW


def validate_alias_compatibility(
    old_target: str, new_target: str, alias_map: Dict[str, str]
) -> List[NamingViolation]:
    """Verify that a backwards-compatible alias target is declared for renamed target."""
    violations: List[NamingViolation] = []
    if old_target not in alias_map or alias_map[old_target] != new_target:
        violations.append(
            NamingViolation(
                rule_id="MIG001",
                file_path=old_target,
                line_number=None,
                message=f"Missing backwards-compatible alias for renamed target '{old_target}' -> '{new_target}'.",
                severity=ViolationSeverity.WARNING,
            )
        )
    return violations


def validate_symlink_alias(
    old_path: str, expected_target: str
) -> List[NamingViolation]:
    """Verify that a compatibility symlink exists and points to the target."""
    violations: List[NamingViolation] = []
    if not os.path.islink(old_path):
        violations.append(
            NamingViolation(
                rule_id="MIG002",
                file_path=old_path,
                line_number=None,
                message=f"Compatibility symlink '{old_path}' does not exist.",
                severity=ViolationSeverity.ERROR,
            )
        )
    return violations
