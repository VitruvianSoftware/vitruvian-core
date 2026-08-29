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

"""Tier 4: Real-World Workload Scenarios Test Suite.

Executes comprehensive end-to-end simulations mirroring realistic CI/CD, development, and migration workflows:
1. Scenario 1: CI Preflight Commit Hook Simulation
2. Scenario 2: New Go Microservice Scaffolding Validation
3. Scenario 3: Cloud Run Deployment Workflow Rename Simulation
4. Scenario 4: Bazel Target Query & Build Graph Audit
5. Scenario 5: Cross-Ecosystem Polyglot Monorepo Compliance
"""

import os
import sys
import tempfile
import unittest

# Ensure tools/lint-naming is on python path
_PKG_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_DIR not in sys.path:
    sys.path.insert(0, _PKG_DIR)

from rules import ViolationSeverity
from rules.directories import validate_directory_name
from rules.source_files import validate_file_name
from rules.configs import validate_workflow_yaml_content
from rules.bazel import validate_build_file_content, validate_bazel_target_name
from rules.migration import (
    assess_rename_risk,
    validate_alias_compatibility,
    MigrationRiskLevel,
)
from scanner import RepositoryNamingScanner


class Tier4RealWorldScenarioTestSuite(unittest.TestCase):
    """Tier 4 Real-World Scenario Tests."""

    def test_scenario_1_ci_preflight_commit_hook_simulation(self):
        """Scenario 1: CI Preflight Commit Hook Simulation.

        Simulates pre-commit git preflight check scanning a changeset.
        Asserts non-zero exit on violations and zero exit when fixed.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            # 1. Setup clean commit tree
            pkg_dir = os.path.join(tmp_dir, "pkg", "auth_service")
            os.makedirs(pkg_dir, exist_ok=True)
            with open(os.path.join(pkg_dir, "auth_service.go"), "w") as f:
                f.write("package auth_service\n")

            scanner = RepositoryNamingScanner(root_dir=tmp_dir)
            violations = scanner.scan()
            errors = [v for v in violations if v.severity == ViolationSeverity.ERROR]
            self.assertEqual(
                len(errors), 0, "Preflight hook should pass on clean commit"
            )

            # 2. Introduce violation (e.g. kebab-case Go file)
            bad_file = os.path.join(pkg_dir, "auth-handler.go")
            with open(bad_file, "w") as f:
                f.write("package auth_service\n")

            violations = scanner.scan()
            errors = [v for v in violations if v.severity == ViolationSeverity.ERROR]
            self.assertGreater(len(errors), 0, "Preflight hook should reject violation")
            self.assertEqual(errors[0].rule_id, "GO001")
            self.assertIn("auth-handler.go", errors[0].file_path)

            # 3. Fix violation (rename to auth_handler.go)
            os.remove(bad_file)
            with open(os.path.join(pkg_dir, "auth_handler.go"), "w") as f:
                f.write("package auth_service\n")

            violations = scanner.scan()
            errors = [v for v in violations if v.severity == ViolationSeverity.ERROR]
            self.assertEqual(len(errors), 0, "Preflight hook should succeed after fix")

    def test_scenario_2_new_go_microservice_scaffolding_validation(self):
        """Scenario 2: New Go Microservice Scaffolding Validation.

        Validates end-to-end naming compliance of a complete newly scaffolded service.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            svc_dir = os.path.join(tmp_dir, "devx", "services", "user_auth")
            os.makedirs(svc_dir, exist_ok=True)

            # Create Go sources
            with open(os.path.join(svc_dir, "main.go"), "w") as f:
                f.write("package main\nfunc main() {}\n")
            with open(os.path.join(svc_dir, "server.go"), "w") as f:
                f.write("package main\n")
            with open(os.path.join(svc_dir, "server_test.go"), "w") as f:
                f.write("package main\n")

            # Create BUILD.bazel
            build_content = """load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "user_auth_lib",
    srcs = ["server.go"],
)

go_binary(
    name = "user-auth",
    srcs = ["main.go"],
    embed = [":user_auth_lib"],
)

go_test(
    name = "user_auth_test",
    srcs = ["server_test.go"],
    embed = [":user_auth_lib"],
)
"""
            with open(os.path.join(svc_dir, "BUILD.bazel"), "w") as f:
                f.write(build_content)

            scanner = RepositoryNamingScanner(root_dir=tmp_dir)
            violations = scanner.scan()
            errors = [v for v in violations if v.severity == ViolationSeverity.ERROR]
            self.assertEqual(
                len(errors),
                0,
                f"Scaffolded Go service must be 100% compliant: {errors}",
            )

    def test_scenario_3_cloud_run_deployment_workflow_rename_simulation(self):
        """Scenario 3: Cloud Run Deployment Workflow Rename Simulation.

        Simulates renaming a drifted deployment script and updating workflows with backwards compatibility.
        """
        old_script = "tools/deploy/deploy_cloud_run.sh"
        new_script = "tools/deploy/deploy-cloud-run.sh"

        # 1. Assess rename risk
        risk = assess_rename_risk(old_script, new_script)
        self.assertEqual(risk, MigrationRiskLevel.MEDIUM)

        # 2. Validate alias mapping for Bazel target
        old_target = "//tools/deploy:deploy_cloud_run"
        new_target = "//tools/deploy:deploy-cloud-run"
        alias_map = {old_target: new_target}
        alias_violations = validate_alias_compatibility(
            old_target, new_target, alias_map
        )
        self.assertEqual(len(alias_violations), 0)

        # 3. Validate workflow referencing the new target
        workflow_content = """name: Deploy

jobs:
  deploy-cloud-run:
    runs-on: ubuntu-latest
    steps:
      - name: Run deploy
        id: run-deploy
        run: bazel run //tools/deploy:deploy-cloud-run
"""
        wf_violations = validate_workflow_yaml_content(
            ".github/workflows/deploy.yaml", workflow_content
        )
        self.assertEqual(len(wf_violations), 0)

    def test_scenario_4_bazel_target_query_and_build_graph_audit(self):
        """Scenario 4: Bazel Target Query & Build Graph Audit.

        Simulates auditing a multi-package Bazel workspace graph.
        """
        targets = [
            ("tools/agent-app", "agent-app", "sh_binary"),
            ("tools/agent-app", "agent-app_test", "sh_test"),
            ("infrastructure/pulumi/network_hubs", "network_hubs_lib", "go_library"),
            ("infrastructure/pulumi/network_hubs", "network_hubs_test", "go_test"),
            ("tools/license", "check", "sh_binary"),
            ("tools/license", "add", "sh_binary"),
            ("tools/license", "verify", "sh_binary"),
        ]

        violations = []
        for pkg, target_name, rule_type in targets:
            violations.extend(
                validate_bazel_target_name(f"{pkg}/BUILD.bazel", target_name, rule_type)
            )

        self.assertEqual(
            len(violations),
            0,
            "All targets in query graph should comply with naming standard",
        )

    def test_scenario_5_cross_ecosystem_polyglot_monorepo_compliance(self):
        """Scenario 5: Cross-Ecosystem Polyglot Monorepo Compliance.

        Simulates full stack monorepo workspace containing Go, TypeScript, Python, Swift, Shell, K8s, and YAML.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            # 1. Go backend in snake package dir
            go_dir = os.path.join(tmp_dir, "pkg", "user_service")
            os.makedirs(go_dir, exist_ok=True)
            with open(os.path.join(go_dir, "user_service.go"), "w") as f:
                f.write("package user_service\n")

            # 2. React TSX frontend in kebab package dir
            ts_dir = os.path.join(tmp_dir, "packages", "web-ui", "src")
            os.makedirs(ts_dir, exist_ok=True)
            with open(os.path.join(ts_dir, "UserProfile.tsx"), "w") as f:
                f.write("export const UserProfile = () => null;\n")

            # 3. Python data hook in snake filename
            py_dir = os.path.join(tmp_dir, "tools", "hooks")
            os.makedirs(py_dir, exist_ok=True)
            with open(os.path.join(py_dir, "data_hook.py"), "w") as f:
                f.write("def hook(): pass\n")

            # 4. Swift macOS app in PascalCase
            swift_dir = os.path.join(tmp_dir, "macos", "Sources", "NexusAgent")
            os.makedirs(swift_dir, exist_ok=True)
            with open(os.path.join(swift_dir, "AppDelegate.swift"), "w") as f:
                f.write("import Foundation\n")

            # 5. Shell CI runner in kebab-case
            ci_dir = os.path.join(tmp_dir, "tools", "ci")
            os.makedirs(ci_dir, exist_ok=True)
            with open(os.path.join(ci_dir, "build-all.sh"), "w") as f:
                f.write("#!/usr/bin/env bash\n")

            # 6. GitHub Actions workflow in kebab-case
            wf_dir = os.path.join(tmp_dir, ".github", "workflows")
            os.makedirs(wf_dir, exist_ok=True)
            with open(os.path.join(wf_dir, "ci.yaml"), "w") as f:
                f.write("name: CI\njobs:\n  test:\n    runs-on: ubuntu-latest\n")

            scanner = RepositoryNamingScanner(root_dir=tmp_dir)
            violations = scanner.scan()
            errors = [v for v in violations if v.severity == ViolationSeverity.ERROR]
            self.assertEqual(
                len(errors),
                0,
                f"Polyglot monorepo workspace must produce 0 errors: {errors}",
            )


if __name__ == "__main__":
    unittest.main()
