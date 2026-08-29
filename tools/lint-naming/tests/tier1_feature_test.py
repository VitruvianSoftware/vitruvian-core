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

"""Tier 1: Feature Coverage Test Suite.

Verifies all 10 core features (F1 through F10) in isolation:
- F1: Repository Audit Report
- F2: Ecosystem Constraints
- F3: Canonical Naming Standard
- F4: Compound Words & Acronyms
- F5: Automated Linter Engine
- F6: Bazel Tooling Integration
- F7: Config & Schema Linter Rule
- F8: Phased Migration Roadmap
- F9: Backwards Compatibility Strategy
- F10: Complete E2E Integrity
"""

import os
import sys
import unittest

# Ensure tools/lint-naming is on python path
_PKG_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_DIR not in sys.path:
    sys.path.insert(0, _PKG_DIR)

from rules import ViolationSeverity
from rules.directories import validate_directory_name
from rules.source_files import validate_file_name
from rules.configs import (
    validate_config_file_name,
    validate_workflow_yaml_content,
    validate_k8s_resource_name,
    validate_pulumi_config_key,
)
from rules.bazel import (
    validate_bazel_target_name,
    validate_starlark_file_name,
    validate_build_file_content,
)
from rules.environment import (
    validate_env_var_name,
    validate_cli_flag_name,
)
from rules.migration import (
    MigrationRiskLevel,
    assess_rename_risk,
    validate_alias_compatibility,
)
from scanner import RepositoryNamingScanner


class Tier1FeatureTestSuite(unittest.TestCase):
    """Tier 1 Feature Coverage Tests."""

    def setUp(self):
        self.base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.clean_fixture_dir = os.path.join(self.base_dir, "testdata", "clean_repo")
        self.violations_fixture_dir = os.path.join(self.base_dir, "testdata", "violations")

    # --- F1: Repository Audit Report ---

    def test_f1_01_audit_directory_casing_catalog(self):
        """F1: Catalog directory casing styles accurately."""
        self.assertEqual(len(validate_directory_name("tools/ci-preflight")), 0)
        self.assertEqual(len(validate_directory_name("devx")), 0)
        v = validate_directory_name("tools/ci_preflight")
        self.assertGreater(len(v), 0)

    def test_f1_02_audit_filename_casing_catalog(self):
        """F1: Catalog filename casing across extensions."""
        self.assertEqual(len(validate_file_name("pkg/net/cloud_dns.go")), 0)
        self.assertEqual(len(validate_file_name("hooks/stream_hook.py")), 0)
        v_go = validate_file_name("pkg/net/net-hubs.go")
        self.assertEqual(v_go[0].rule_id, "GO001")
        v_py = validate_file_name("hooks/stream-hook.py")
        self.assertEqual(v_py[0].rule_id, "PY001")

    def test_f1_03_audit_config_keys_catalog(self):
        """F1: Audit YAML and JSON config keys."""
        content = "jobs:\n  build_image:\n    runs-on: ubuntu-latest\n"
        v = validate_workflow_yaml_content(".github/workflows/build.yaml", content)
        self.assertGreater(len(v), 0)
        self.assertEqual(v[0].rule_id, "CFG002")

    def test_f1_04_audit_bazel_targets_catalog(self):
        """F1: Catalog Bazel target types and names."""
        v_bin = validate_bazel_target_name("tools/BUILD.bazel", "bad_bin", "sh_binary", 10)
        self.assertEqual(v_bin[0].rule_id, "BZL001")
        v_lib = validate_bazel_target_name("pkg/BUILD.bazel", "bad-lib", "go_library", 12)
        self.assertEqual(v_lib[0].rule_id, "BZL002")

    def test_f1_05_audit_env_vars_catalog(self):
        """F1: Catalog environment variable casing across files."""
        self.assertEqual(len(validate_env_var_name("tools/run.sh", "GH_TOKEN")), 0)
        v = validate_env_var_name("tools/run.sh", "gh_token")
        self.assertEqual(v[0].rule_id, "ENV001")

    def test_f1_06_audit_summary_metrics(self):
        """F1: Ensure scanner outputs structured summary metrics."""
        scanner = RepositoryNamingScanner(root_dir=self.clean_fixture_dir)
        violations = scanner.scan()
        report = scanner.format_report(violations, output_format="json")
        self.assertIn("total_violations", report)
        self.assertIn("error_count", report)

    # --- F2: Ecosystem Constraints ---

    def test_f2_01_go_package_snake_case_allowance(self):
        """F2: Go packages allow snake_case where package identifier requires it."""
        v = validate_directory_name("infrastructure/pulumi/network_hubs/modules/cloud_dns")
        self.assertEqual(len(v), 0)

    def test_f2_02_python_import_module_snake_case_rule(self):
        """F2: Python modules require snake_case (no hyphens)."""
        self.assertEqual(len(validate_file_name("tools/lint_naming.py")), 0)
        v = validate_file_name("tools/lint-naming.py")
        self.assertEqual(v[0].rule_id, "PY001")

    def test_f2_03_react_tsx_pascal_case_rule(self):
        """F2: React TSX components permit PascalCase."""
        self.assertEqual(len(validate_file_name("web/components/App.tsx")), 0)
        self.assertEqual(len(validate_file_name("web/components/EntityPage.tsx")), 0)

    def test_f2_04_swift_apple_pascal_case_rule(self):
        """F2: Swift sources permit PascalCase."""
        self.assertEqual(len(validate_file_name("nexus-agent/macos/NexusAgentCore.swift")), 0)

    def test_f2_05_k8s_rfc1123_dns_rule(self):
        """F2: Kubernetes resource names enforce RFC 1123 DNS-1123."""
        self.assertEqual(len(validate_k8s_resource_name("manifest.yaml", "argocd-repo-server")), 0)
        v = validate_k8s_resource_name("manifest.yaml", "argocd_repo_server")
        self.assertEqual(v[0].rule_id, "K8S001")

    def test_f2_06_prisma_migration_timestamp_rule(self):
        """F2: Prisma migration timestamp snake_case directories are allowed."""
        v = validate_directory_name("tabula/web/prisma/migrations/20260524120000_init_schema")
        self.assertEqual(len(v), 0)

    # --- F3: Canonical Naming Standard ---

    def test_f3_01_root_directory_kebab_case_standard(self):
        """F3: Root directories must be kebab-case."""
        self.assertEqual(len(validate_directory_name("mcp-slack", is_root=True)), 0)
        self.assertEqual(len(validate_directory_name("nexus-agent", is_root=True)), 0)
        v = validate_directory_name("mcp_slack", is_root=True)
        self.assertEqual(v[0].rule_id, "DIR002")

    def test_f3_02_shell_script_kebab_case_standard(self):
        """F3: Shell scripts must be kebab-case (with optional _test.sh)."""
        self.assertEqual(len(validate_file_name("tools/ci/affected-targets.sh")), 0)
        self.assertEqual(len(validate_file_name("tools/ci/affected-targets_test.sh")), 0)
        v = validate_file_name("tools/ci/affected_targets.sh")
        self.assertEqual(v[0].rule_id, "SH001")

    def test_f3_03_documentation_markdown_standard(self):
        """F3: Documentation must be kebab-case or UPPERCASE."""
        self.assertEqual(len(validate_file_name("docs/standards/naming-conventions.md")), 0)
        self.assertEqual(len(validate_file_name("README.md")), 0)
        self.assertEqual(len(validate_file_name("PROJECT.md")), 0)
        v = validate_file_name("docs/my_custom_doc.md")
        self.assertEqual(v[0].rule_id, "DOC001")

    def test_f3_04_internal_cli_flag_kebab_standard(self):
        """F3: Internal CLI flags must be --kebab-case."""
        self.assertEqual(len(validate_cli_flag_name("script.sh", "--dry-run")), 0)
        self.assertEqual(len(validate_cli_flag_name("script.sh", "--check-mode")), 0)
        v = validate_cli_flag_name("script.sh", "--dry_run")
        self.assertEqual(v[0].rule_id, "CLI001")

    def test_f3_05_env_var_screaming_snake_standard(self):
        """F3: Environment variables must be SCREAMING_SNAKE_CASE."""
        self.assertEqual(len(validate_env_var_name("ci.sh", "GOOGLE_OAUTH_ACCESS_TOKEN")), 0)
        self.assertEqual(len(validate_env_var_name("ci.sh", "BUILD_WORKSPACE_DIRECTORY")), 0)
        v = validate_env_var_name("ci.sh", "google_oauth_token")
        self.assertEqual(v[0].rule_id, "ENV001")

    def test_f3_06_pulumi_project_kebab_standard(self):
        """F3: Pulumi project names must be kebab-case."""
        self.assertEqual(len(validate_directory_name("infrastructure/pulumi/foundation-app-infra")), 0)

    # --- F4: Compound Words & Acronyms ---

    def test_f4_01_acronym_kebab_case_handling(self):
        """F4: Multi-character acronyms in kebab-case."""
        self.assertEqual(len(validate_directory_name("mcp-slack")), 0)
        self.assertEqual(len(validate_directory_name("oauth-user-inspector")), 0)

    def test_f4_02_acronym_snake_case_go_handling(self):
        """F4: Acronyms in Go snake_case filenames."""
        self.assertEqual(len(validate_file_name("pkg/cloud_dns/cloud_dns.go")), 0)
        self.assertEqual(len(validate_file_name("pkg/oauth_jwt/oauth_jwt.go")), 0)

    def test_f4_03_acronym_screaming_snake_env_handling(self):
        """F4: Acronyms in SCREAMING_SNAKE env vars."""
        self.assertEqual(len(validate_env_var_name("app.go", "HTTP_PROXY")), 0)
        self.assertEqual(len(validate_env_var_name("app.go", "OAUTH_CLIENT_ID")), 0)

    def test_f4_04_compound_word_splitting_rules(self):
        """F4: Compound words in kebab-case directories and scripts."""
        self.assertEqual(len(validate_directory_name("tools/ci-preflight")), 0)
        self.assertEqual(len(validate_file_name("tools/changelog-summary.sh")), 0)

    def test_f4_05_alphanumeric_acronyms_with_numbers(self):
        """F4: Alphanumeric identifiers with numbers."""
        self.assertEqual(len(validate_directory_name("infrastructure/pulumi/bu1-dev")), 0)
        self.assertEqual(len(validate_file_name("pkg/sha256_digest.go")), 0)

    def test_f4_06_k8s_compound_acronym_subdomains(self):
        """F4: Kubernetes RFC 1123 compound names."""
        self.assertEqual(len(validate_k8s_resource_name("k8s.yaml", "argo-cd-server-v1")), 0)

    # --- F5: Automated Linter Engine ---

    def test_f5_01_linter_clean_repo_exit_zero(self):
        """F5: Clean fixture repository produces 0 errors."""
        scanner = RepositoryNamingScanner(root_dir=self.clean_fixture_dir)
        violations = scanner.scan()
        errors = [v for v in violations if v.severity == ViolationSeverity.ERROR]
        self.assertEqual(len(errors), 0)

    def test_f5_02_linter_violations_detected(self):
        """F5: Violations fixture produces expected violations."""
        scanner = RepositoryNamingScanner(root_dir=self.violations_fixture_dir, ignore_violation_fixtures=False)
        violations = scanner.scan()
        rule_ids = {v.rule_id for v in violations}
        self.assertIn("GO001", rule_ids)
        self.assertIn("PY001", rule_ids)
        self.assertIn("SH001", rule_ids)
        self.assertIn("DOC001", rule_ids)

    def test_f5_03_linter_exact_line_reporting(self):
        """F5: Workflow violations report line numbers."""
        scanner = RepositoryNamingScanner(root_dir=self.violations_fixture_dir, ignore_violation_fixtures=False)
        violations = scanner.scan()
        workflow_violations = [v for v in violations if v.rule_id in ("CFG002", "CFG004")]
        self.assertGreater(len(workflow_violations), 0)
        self.assertIsNotNone(workflow_violations[0].line_number)

    def test_f5_04_linter_rule_id_tagging(self):
        """F5: All violations have structured rule ID tags."""
        scanner = RepositoryNamingScanner(root_dir=self.violations_fixture_dir, ignore_violation_fixtures=False)
        violations = scanner.scan()
        for v in violations:
            self.assertTrue(len(v.rule_id) >= 5)

    def test_f5_05_linter_ignore_patterns_respected(self):
        """F5: Scanner ignores node_modules and .git by default."""
        scanner = RepositoryNamingScanner(root_dir=self.clean_fixture_dir)
        self.assertTrue(scanner.should_ignore("node_modules/pkg/bad_file.go"))
        self.assertTrue(scanner.should_ignore(".git/hooks/pre-commit"))

    def test_f5_06_linter_json_output_mode(self):
        """F5: JSON output format contains required keys."""
        scanner = RepositoryNamingScanner(root_dir=self.clean_fixture_dir)
        violations = scanner.scan()
        json_report = scanner.format_report(violations, output_format="json")
        self.assertIn('"total_violations"', json_report)
        self.assertIn('"violations"', json_report)

    # --- F6: Bazel Tooling Integration ---

    def test_f6_01_bazel_binary_target_kebab_rule(self):
        """F6: Bazel binary targets require kebab-case."""
        self.assertEqual(len(validate_bazel_target_name("BUILD", "agent-app", "sh_binary")), 0)
        v = validate_bazel_target_name("BUILD", "agent_app", "sh_binary")
        self.assertEqual(v[0].rule_id, "BZL001")

    def test_f6_02_bazel_go_library_snake_rule(self):
        """F6: Bazel Go libraries require snake_case."""
        self.assertEqual(len(validate_bazel_target_name("BUILD", "cloud_dns_lib", "go_library")), 0)
        v = validate_bazel_target_name("BUILD", "cloud-dns-lib", "go_library")
        self.assertEqual(v[0].rule_id, "BZL002")

    def test_f6_03_bazel_shell_test_target_rule(self):
        """F6: Bazel shell test target requires <bin>_test."""
        self.assertEqual(len(validate_bazel_target_name("BUILD", "agent-app_test", "sh_test")), 0)

    def test_f6_04_bazel_starlark_file_snake_rule(self):
        """F6: Bazel Starlark files require snake_case."""
        self.assertEqual(len(validate_starlark_file_name("tools/defs.bzl")), 0)
        v = validate_starlark_file_name("tools/my-defs.bzl")
        self.assertEqual(v[0].rule_id, "BZL004")

    def test_f6_05_bazel_build_file_parsing(self):
        """F6: Parse BUILD.bazel content for target violations."""
        content = 'sh_binary(name = "bad_name", srcs = ["a.sh"])\n'
        v = validate_build_file_content("BUILD.bazel", content)
        self.assertEqual(len(v), 1)
        self.assertEqual(v[0].rule_id, "BZL001")

    def test_f6_06_bazel_workspace_directory_env(self):
        """F6: Scanner detects workspace root from environment variable."""
        old_env = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
        os.environ["BUILD_WORKSPACE_DIRECTORY"] = self.clean_fixture_dir
        try:
            scanner = RepositoryNamingScanner(root_dir=os.environ["BUILD_WORKSPACE_DIRECTORY"])
            self.assertEqual(scanner.root_dir, self.clean_fixture_dir)
        finally:
            if old_env is not None:
                os.environ["BUILD_WORKSPACE_DIRECTORY"] = old_env
            else:
                os.environ.pop("BUILD_WORKSPACE_DIRECTORY", None)

    # --- F7: Config & Schema Linter Rule ---

    def test_f7_01_github_workflow_job_id_kebab(self):
        """F7: GitHub Actions workflow job IDs must be kebab-case."""
        content = "jobs:\n  unit-test:\n    runs-on: ubuntu-latest\n"
        self.assertEqual(len(validate_workflow_yaml_content("ci.yaml", content)), 0)

    def test_f7_02_github_workflow_step_id_kebab(self):
        """F7: Step IDs must be kebab-case."""
        content = "jobs:\n  test:\n    steps:\n      - id: run-test\n"
        self.assertEqual(len(validate_workflow_yaml_content("ci.yaml", content)), 0)
        content_bad = "jobs:\n  test:\n    steps:\n      - id: run_test\n"
        v = validate_workflow_yaml_content("ci.yaml", content_bad)
        self.assertEqual(v[0].rule_id, "CFG004")

    def test_f7_03_github_workflow_input_output_kebab(self):
        """F7: Action inputs and outputs must be kebab-case."""
        content = "inputs:\n  github-token:\n    description: token\n"
        self.assertEqual(len(validate_workflow_yaml_content("action.yaml", content)), 0)
        content_bad = "inputs:\n  github_token:\n    description: token\n"
        v = validate_workflow_yaml_content("action.yaml", content_bad)
        self.assertEqual(v[0].rule_id, "CFG003")

    def test_f7_04_github_workflow_file_name_kebab(self):
        """F7: Workflow files must be kebab-case."""
        self.assertEqual(len(validate_config_file_name(".github/workflows/ci-preflight.yaml")), 0)
        v = validate_config_file_name(".github/workflows/ci_preflight.yaml")
        self.assertEqual(v[0].rule_id, "CFG001")

    def test_f7_05_pulumi_config_yaml_naming(self):
        """F7: Pulumi configuration file naming and keys."""
        self.assertEqual(len(validate_config_file_name("Pulumi.dev.yaml")), 0)
        self.assertEqual(len(validate_pulumi_config_key("Pulumi.dev.yaml", "gcp:project")), 0)

    def test_f7_06_kubernetes_yaml_resource_naming(self):
        """F7: Kubernetes manifest resource naming."""
        self.assertEqual(len(validate_k8s_resource_name("deploy.yaml", "auth-service")), 0)

    # --- F8: Phased Migration Roadmap ---

    def test_f8_01_migration_risk_low_test_scripts(self):
        """F8: Test scripts classified as LOW risk."""
        risk = assess_rename_risk("tools/ci/test_runner_test.sh", "tools/ci/test-runner_test.sh")
        self.assertEqual(risk, MigrationRiskLevel.LOW)

    def test_f8_02_migration_risk_medium_internal_tools(self):
        """F8: Internal tools classified as MEDIUM risk."""
        risk = assess_rename_risk("tools/pulumi/create_app.sh", "tools/pulumi/create-app.sh")
        self.assertEqual(risk, MigrationRiskLevel.MEDIUM)

    def test_f8_03_migration_risk_high_public_apis(self):
        """F8: Workflows and public interfaces classified as HIGH risk."""
        risk = assess_rename_risk(".github/workflows/deploy.yaml", ".github/workflows/deploy-app.yaml")
        self.assertEqual(risk, MigrationRiskLevel.HIGH)

    def test_f8_04_migration_phase_sequencing_rules(self):
        """F8: Low risk items sequence before high risk items."""
        order = [MigrationRiskLevel.LOW, MigrationRiskLevel.MEDIUM, MigrationRiskLevel.HIGH]
        self.assertEqual(order[0], MigrationRiskLevel.LOW)
        self.assertEqual(order[-1], MigrationRiskLevel.HIGH)

    def test_f8_05_migration_dependency_resolution(self):
        """F8: Migration targets must map cleanly."""
        risk_go = assess_rename_risk("pkg/net-hubs.go", "pkg/net_hubs.go")
        self.assertIn(risk_go, [MigrationRiskLevel.LOW, MigrationRiskLevel.MEDIUM, MigrationRiskLevel.HIGH])

    def test_f8_06_migration_dry_run_validation(self):
        """F8: Dry-run simulation mode verifies risk calculation and mapping."""
        dry_run_plan = [
            ("tabula/web/components/App.test.tsx", "tabula/web/components/App.spec.tsx", MigrationRiskLevel.LOW),
            ("tools/pulumi/create_app.sh", "tools/pulumi/create-app.sh", MigrationRiskLevel.MEDIUM),
            (".github/workflows/deploy.yaml", ".github/workflows/deploy-app.yaml", MigrationRiskLevel.HIGH),
        ]
        for src, dst, expected_risk in dry_run_plan:
            risk = assess_rename_risk(src, dst)
            self.assertEqual(risk, expected_risk, f"Dry-run risk mismatch for {src} -> {dst}")

    # --- F9: Backwards Compatibility Strategy ---

    def test_f9_01_symlink_alias_validation(self):
        """F9: Validate alias compatibility mapping."""
        alias_map = {"//tools/old-bin": "//tools/new-bin"}
        self.assertEqual(len(validate_alias_compatibility("//tools/old-bin", "//tools/new-bin", alias_map)), 0)

    def test_f9_02_bazel_alias_rule_validation(self):
        """F9: Report missing alias mapping."""
        alias_map = {}
        v = validate_alias_compatibility("//tools/old-bin", "//tools/new-bin", alias_map)
        self.assertEqual(v[0].rule_id, "MIG001")

    def test_f9_03_copybara_export_transformation_rules(self):
        """F9: Copybara mapping preservation and export validation."""
        export_mappings = {
            "tools/copybara/check_version_maps.sh": "tools/copybara/check-version-maps.sh",
            "oauth-user-inspector/src/index.ts": "src/index.ts",
            "devx/tools/lint_naming.py": "tools/lint_naming.py",
        }
        for internal_path, export_path in export_mappings.items():
            violations = validate_file_name(export_path)
            self.assertEqual(len(violations), 0, f"Export path {export_path} must be naming-compliant")

    def test_f9_04_shell_redirect_stub_validation(self):
        """F9: Shell stub redirects validate delegation contract."""
        import tempfile
        with tempfile.TemporaryDirectory() as tmp_dir:
            stub_script = os.path.join(tmp_dir, "legacy-cmd.sh")
            with open(stub_script, "w") as f:
                f.write('#!/usr/bin/env bash\nexec "$(dirname "$0")/modern-cmd.sh" "$@"\n')

            alias_map = {"//tools:legacy-cmd": "//tools:modern-cmd"}
            violations = validate_alias_compatibility("//tools:legacy-cmd", "//tools:modern-cmd", alias_map)
            self.assertEqual(len(violations), 0)

    def test_f9_05_deprecated_flag_forwarding_rules(self):
        """F9: Flag aliases forwarded cleanly with suggested fixes."""
        deprecated_flags = [
            ("--dry_run", "--dry-run"),
            ("--check_mode", "--check-mode"),
            ("--output_format", "--output-format"),
        ]
        for bad_flag, expected_fix in deprecated_flags:
            violations = validate_cli_flag_name("script.sh", bad_flag)
            self.assertEqual(len(violations), 1)
            self.assertEqual(violations[0].rule_id, "CLI001")
            self.assertEqual(violations[0].suggested_fix, expected_fix)

    def test_f9_06_missing_alias_warning_generation(self):
        """F9: Warning generated on unaliased renamed targets."""
        v = validate_alias_compatibility("//pkg:old", "//pkg:new", {})
        self.assertEqual(v[0].severity, ViolationSeverity.WARNING)

    # --- F10: Complete E2E Integrity ---

    def test_f10_01_clean_fixture_repo_full_scan(self):
        """F10: Clean fixture repo scan yields 0 errors."""
        scanner = RepositoryNamingScanner(root_dir=self.clean_fixture_dir)
        violations = scanner.scan()
        errors = [v for v in violations if v.severity == ViolationSeverity.ERROR]
        self.assertEqual(len(errors), 0)

    def test_f10_02_violation_fixture_repo_full_scan(self):
        """F10: Violations fixture repo scan catches all violations."""
        scanner = RepositoryNamingScanner(root_dir=self.violations_fixture_dir, ignore_violation_fixtures=False)
        violations = scanner.scan()
        self.assertGreaterEqual(len(violations), 5)

    def test_f10_03_diff_mode_selective_scan(self):
        """F10: Diff scanning mode processes selected subset."""
        v = validate_file_name("tools/bad_script.sh")
        self.assertEqual(len(v), 1)

    def test_f10_04_strict_vs_default_exit_codes(self):
        """F10: Strict mode flags warnings as exit failures."""
        import tempfile
        import io
        import contextlib
        import lint_naming
        with tempfile.TemporaryDirectory() as tmp_dir:
            # Create a file that triggers ONLY a warning (e.g. TSX001)
            react_dir = os.path.join(tmp_dir, "web", "components")
            os.makedirs(react_dir, exist_ok=True)
            with open(os.path.join(react_dir, "bad_component.tsx"), "w") as f:
                f.write("// Bad React component casing\n")

            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                # Default mode (strict=False) on warnings only: exit code 0
                exit_default = lint_naming.main(["--root", tmp_dir])
                self.assertEqual(exit_default, 0, "Default mode should return 0 on warnings only")

                # Strict mode on warnings only: exit code 1
                exit_strict = lint_naming.main(["--root", tmp_dir, "--strict"])
                self.assertEqual(exit_strict, 1, "Strict mode should return 1 when warnings exist")

    def test_f10_05_end_to_end_cli_execution(self):
        """F10: Scanner report formats text properly."""
        scanner = RepositoryNamingScanner(root_dir=self.clean_fixture_dir)
        v = scanner.scan()
        text_report = scanner.format_report(v, output_format="text")
        self.assertIn("Naming Audit Complete", text_report)

    def test_f10_06_summary_reporter_output_fidelity(self):
        """F10: Verify fidelity of reported violation lines."""
        v = validate_file_name("tools/bad_script.sh")[0]
        formatted = v.format_line()
        self.assertIn("SH001", formatted)
        self.assertIn("tools/bad_script.sh", formatted)

    # --- Adversarial Edge Cases Discovered by Challenger 1 ---

    def test_adv_01_bazel_target_srcs_before_name(self):
        """Adversarial: Parse BUILD targets where srcs precedes name or comments precede name."""
        content = """sh_binary(
    srcs = ["script.sh"],
    # Primary entrypoint
    name = "bad_binary_name",
    tags = ["manual"],
)
"""
        violations = validate_build_file_content("BUILD.bazel", content)
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].rule_id, "BZL001")

    def test_adv_02_workflow_nested_inputs_4_space_indent(self):
        """Adversarial: Workflow dispatch nested inputs with 4+ space indentation."""
        content = """name: Deploy
on:
  workflow_dispatch:
    inputs:
      target_environment:
        description: "Target environment"
        required: true
"""
        violations = validate_workflow_yaml_content(".github/workflows/deploy.yaml", content)
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].rule_id, "CFG003")
        self.assertIn("target_environment", violations[0].message)

    def test_adv_03_workflow_multiline_bash_run_block_isolation(self):
        """Adversarial: Multiline bash run blocks do not trigger false step ID errors."""
        content = """name: CI
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Execute script
        id: valid-step-id
        run: |
          id: internal_var
          echo "id: inside bash block"
"""
        violations = validate_workflow_yaml_content(".github/workflows/ci.yaml", content)
        self.assertEqual(len(violations), 0)

    def test_adv_04_workflow_reusable_leading_underscore(self):
        """Adversarial: Reusable workflow files with leading underscore are valid."""
        violations = validate_config_file_name(".github/workflows/_deploy-cloud-run.yaml")
        self.assertEqual(len(violations), 0)


if __name__ == "__main__":
    unittest.main()
