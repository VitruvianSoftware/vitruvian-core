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

"""Configuration file and schema key naming rules."""

import os
import re
from typing import List, Dict, Any

try:
    from . import NamingViolation, ViolationSeverity
except (ImportError, ValueError):
    from rules import NamingViolation, ViolationSeverity

KEBAB_CASE_KEY_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
WORKFLOW_FILE_RE = re.compile(r"^_?[a-z0-9]+(-[a-z0-9]+)*$")
CAMEL_CASE_KEY_RE = re.compile(r"^[a-z0-9]+([A-Z][a-z0-9]*)*$")
SNAKE_CASE_KEY_RE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*$")
PULUMI_CONFIG_KEY_RE = re.compile(
    r"^([a-z0-9]+(-[a-z0-9]+)*:)?([a-z0-9]+(-[a-z0-9]+)*|[a-z0-9]+(_[a-z0-9]+)*)$"
)
RFC1123_NAME_RE = re.compile(r"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$")

WORKFLOW_STANDARD_KEYS = {
    "name",
    "on",
    "permissions",
    "concurrency",
    "env",
    "jobs",
    "runs-on",
    "steps",
    "uses",
    "with",
    "run",
    "id",
    "if",
    "needs",
    "strategy",
    "matrix",
    "outputs",
    "inputs",
    "defaults",
    "timeout-minutes",
    "continue-on-error",
    "environment",
    "services",
    "container",
}


def validate_config_file_name(file_path: str) -> List[NamingViolation]:
    """Validate configuration file name casing."""
    violations: List[NamingViolation] = []
    normalized = file_path.strip("/").replace("\\", "/")
    file_name = os.path.basename(normalized)

    # Pulumi stack configs: Pulumi.<env>.yaml or Pulumi.yaml
    if file_name.startswith("Pulumi.") and file_name.endswith((".yaml", ".yml")):
        return violations

    # GitHub Actions workflow file: must be kebab-case (with optional leading underscore for reusable workflows)
    if ".github/workflows" in normalized and file_name.endswith((".yaml", ".yml")):
        base_name = file_name.rsplit(".", 1)[0]
        if not WORKFLOW_FILE_RE.match(base_name):
            violations.append(
                NamingViolation(
                    rule_id="CFG001",
                    file_path=normalized,
                    line_number=None,
                    message=f"GitHub Actions workflow file '{file_name}' must use kebab-case.",
                    suggested_fix=f"{base_name.replace('_', '-')}.yaml",
                    severity=ViolationSeverity.ERROR,
                )
            )

    return violations


def validate_workflow_yaml_content(
    file_path: str, content: str
) -> List[NamingViolation]:
    """Scan GitHub Actions workflow YAML content for job ID and input/output naming violations."""
    violations: List[NamingViolation] = []
    lines = content.splitlines()

    in_jobs_section = False
    jobs_indent = 0
    in_inputs_section = False
    inputs_indent = 0
    in_outputs_section = False
    outputs_indent = 0
    in_run_block = False
    run_block_indent = 0

    for idx, raw_line in enumerate(lines, start=1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        indent = len(raw_line) - len(raw_line.lstrip())

        # Check multiline run block escape: any line with indentation <= run_block_indent exits the run block
        if in_run_block:
            if indent <= run_block_indent:
                in_run_block = False
            else:
                # Still inside bash run script body; ignore lines matching 'id:' etc.
                continue

        # Check if this line starts a multiline run block scalar (e.g. run: |, run: >, - run: |)
        if re.search(r"(?:^|[-\s])run\s*:\s*[|>][-+]?", stripped):
            in_run_block = True
            run_block_indent = indent
            continue

        # Check section boundaries
        if stripped == "jobs:" or stripped.startswith("jobs:"):
            in_jobs_section = True
            jobs_indent = indent
            in_inputs_section = False
            in_outputs_section = False
            continue

        if stripped == "inputs:" or stripped.startswith("inputs:"):
            in_inputs_section = True
            inputs_indent = indent
            in_outputs_section = False
            in_jobs_section = False
            continue

        if stripped == "outputs:" or stripped.startswith("outputs:"):
            in_outputs_section = True
            outputs_indent = indent
            in_inputs_section = False
            in_jobs_section = False
            continue

        # Section exit checks based on indentation
        if (
            in_jobs_section
            and indent <= jobs_indent
            and not stripped.startswith("jobs:")
        ):
            in_jobs_section = False

        if in_inputs_section and indent <= inputs_indent:
            in_inputs_section = False

        if in_outputs_section and indent <= outputs_indent:
            in_outputs_section = False

        # Top-level job keys under jobs: (indent is jobs_indent + 2)
        if in_jobs_section and indent == jobs_indent + 2 and ":" in stripped:
            job_key = stripped.split(":", 1)[0].strip()
            # If job_key contains underscores, report violation
            if (
                "_" in job_key
                and not job_key.startswith("${{")
                and not job_key.startswith("-")
            ):
                violations.append(
                    NamingViolation(
                        rule_id="CFG002",
                        file_path=file_path,
                        line_number=idx,
                        message=f"GitHub Actions job ID '{job_key}' uses underscores. Expected kebab-case.",
                        suggested_fix=job_key.replace("_", "-"),
                        severity=ViolationSeverity.ERROR,
                    )
                )

        # Action / Workflow inputs & outputs (indent is inputs_indent + 2 / outputs_indent + 2)
        if (in_inputs_section or in_outputs_section) and ":" in stripped:
            expected_param_indent = (
                (inputs_indent + 2) if in_inputs_section else (outputs_indent + 2)
            )
            if indent == expected_param_indent or (
                inputs_indent == 0 and indent in (2, 4)
            ):
                param_key = stripped.split(":", 1)[0].strip()
                if (
                    "_" in param_key
                    and not param_key.startswith("${{")
                    and not param_key.startswith("-")
                ):
                    violations.append(
                        NamingViolation(
                            rule_id="CFG003",
                            file_path=file_path,
                            line_number=idx,
                            message=f"Workflow input/output key '{param_key}' uses underscores. Expected kebab-case.",
                            suggested_fix=param_key.replace("_", "-"),
                            severity=ViolationSeverity.ERROR,
                        )
                    )

        # Step ID check (only when in jobs section and not in multiline run script block)
        if in_jobs_section and not in_run_block:
            if stripped.startswith("id:") or stripped.startswith("- id:"):
                if stripped.startswith("- id:"):
                    step_id = stripped[5:].strip().strip("\"'")
                else:
                    step_id = stripped.split(":", 1)[1].strip().strip("\"'")
                if "_" in step_id and not step_id.startswith("${{"):
                    violations.append(
                        NamingViolation(
                            rule_id="CFG004",
                            file_path=file_path,
                            line_number=idx,
                            message=f"Step ID '{step_id}' uses underscores. Expected kebab-case.",
                            suggested_fix=step_id.replace("_", "-"),
                            severity=ViolationSeverity.ERROR,
                        )
                    )

    return violations


def validate_k8s_resource_name(
    file_path: str, name: str, line_number: int = 1
) -> List[NamingViolation]:
    """Validate Kubernetes resource metadata.name against RFC 1123 DNS-1123."""
    violations: List[NamingViolation] = []
    if not RFC1123_NAME_RE.match(name) or "_" in name:
        violations.append(
            NamingViolation(
                rule_id="K8S001",
                file_path=file_path,
                line_number=line_number,
                message=f"Kubernetes resource name '{name}' violates RFC 1123 DNS subdomain standard (hyphens only, no underscores).",
                suggested_fix=name.lower().replace("_", "-"),
                severity=ViolationSeverity.ERROR,
            )
        )
    return violations


def validate_pulumi_config_key(
    file_path: str, key: str, line_number: int = 1
) -> List[NamingViolation]:
    """Validate Pulumi configuration key."""
    violations: List[NamingViolation] = []
    if not PULUMI_CONFIG_KEY_RE.match(key):
        violations.append(
            NamingViolation(
                rule_id="PUL001",
                file_path=file_path,
                line_number=line_number,
                message=f"Pulumi configuration key '{key}' has invalid casing.",
                severity=ViolationSeverity.WARNING,
            )
        )
    return violations
