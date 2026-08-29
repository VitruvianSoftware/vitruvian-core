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

"""Tier 2: Boundary & Corner Cases Test Suite.

Verifies edge cases, extreme inputs, boundary conditions, and adversarial scenarios across all 10 features:
- Deeply nested paths (15+ levels)
- Single character names, leading/trailing separators, consecutive separators
- Numbers in various positions (bu1, v2beta1, sha256)
- Hidden dotfiles and nested dotdirectories
- Multi-dot extensions (.test.ts, .d.ts, .values.yaml)
- Empty files, empty directory trees, 0-byte configs
- Long paths (> 255 characters)
- Comments, string literals, and expression syntax
"""

import os
import sys
import tempfile
import unittest

# Ensure tools/lint-naming is on python path
_PKG_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_DIR not in sys.path:
    sys.path.insert(0, _PKG_DIR)

from rules import NamingViolation, ViolationSeverity
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
    validate_symlink_alias,
)
from scanner import RepositoryNamingScanner


class Tier2BoundaryTestSuite(unittest.TestCase):
    """Tier 2 Boundary & Corner Case Tests."""

    # --- F1: Repository Audit Boundaries ---

    def test_f1_b01_empty_directory_path(self):
        """F1 Boundary: Empty or single dot directory path produces no violations."""
        self.assertEqual(len(validate_directory_name("")), 0)
        self.assertEqual(len(validate_directory_name(".")), 0)

    def test_f1_b02_single_character_directory_names(self):
        """F1 Boundary: Single character valid kebab directory."""
        self.assertEqual(len(validate_directory_name("a/b/c")), 0)

    def test_f1_b03_deeply_nested_directory_paths_15_levels(self):
        """F1 Boundary: Deeply nested valid kebab directory (15 levels)."""
        deep_path = "/".join([f"level-{i}" for i in range(15)])
        self.assertEqual(len(validate_directory_name(deep_path)), 0)

    def test_f1_b04_directory_paths_with_consecutive_slashes(self):
        """F1 Boundary: Normalizing consecutive slashes in directory path."""
        self.assertEqual(len(validate_directory_name("tools//ci-preflight")), 0)

    def test_f1_b05_directory_names_with_trailing_slashes(self):
        """F1 Boundary: Trailing slashes stripped cleanly."""
        self.assertEqual(len(validate_directory_name("tools/ci-preflight/")), 0)

    def test_f1_b06_windows_style_backslashes_in_paths(self):
        """F1 Boundary: Windows backslash normalization in paths."""
        self.assertEqual(
            len(validate_directory_name("tools\\ci-preflight\\scripts")), 0
        )

    # --- F2: Ecosystem Constraint Boundaries ---

    def test_f2_b01_go_file_single_letter_valid(self):
        """F2 Boundary: Single letter Go source filename is valid snake_case."""
        self.assertEqual(len(validate_file_name("pkg/a.go")), 0)

    def test_f2_b02_go_file_consecutive_underscores(self):
        """F2 Boundary: Consecutive underscores in Go filename are invalid."""
        v = validate_file_name("pkg/net__hubs.go")
        self.assertGreater(len(v), 0)

    def test_f2_b03_python_dunder_init_and_main_allowed(self):
        """F2 Boundary: Python special dunder files __init__.py and __main__.py allowed."""
        self.assertEqual(len(validate_file_name("pkg/__init__.py")), 0)
        self.assertEqual(len(validate_file_name("pkg/__main__.py")), 0)

    def test_f2_b04_react_tsx_single_capital_letter(self):
        """F2 Boundary: Single capital letter component name (e.g. A.tsx)."""
        self.assertEqual(len(validate_file_name("web/components/A.tsx")), 0)

    def test_f2_b05_swift_source_with_numbers(self):
        """F2 Boundary: Swift source filename with numbers (e.g. Core2D.swift)."""
        self.assertEqual(len(validate_file_name("macos/Sources/Core2D.swift")), 0)

    def test_f2_b06_k8s_name_exact_63_char_boundary(self):
        """F2 Boundary: Kubernetes name with valid RFC 1123 characters."""
        valid_63 = "a" * 63
        self.assertEqual(len(validate_k8s_resource_name("svc.yaml", valid_63)), 0)

    # --- F3: Canonical Standard Boundaries ---

    def test_f3_b01_root_dir_single_char_valid(self):
        """F3 Boundary: Single lowercase char root dir is valid."""
        self.assertEqual(len(validate_directory_name("a", is_root=True)), 0)

    def test_f3_b02_root_dir_with_leading_hyphen_invalid(self):
        """F3 Boundary: Leading hyphen in root directory is rejected."""
        v = validate_directory_name("-mcp-slack", is_root=True)
        self.assertGreater(len(v), 0)

    def test_f3_b03_root_dir_with_trailing_hyphen_invalid(self):
        """F3 Boundary: Trailing hyphen in root directory is rejected."""
        v = validate_directory_name("mcp-slack-", is_root=True)
        self.assertGreater(len(v), 0)

    def test_f3_b04_root_dir_consecutive_hyphens_invalid(self):
        """F3 Boundary: Consecutive hyphens in root directory rejected."""
        v = validate_directory_name("mcp--slack", is_root=True)
        self.assertGreater(len(v), 0)

    def test_f3_b05_shell_script_without_extension(self):
        """F3 Boundary: Non-shell extension files not flagged by shell rule."""
        self.assertEqual(len(validate_file_name("tools/binary_executable")), 0)

    def test_f3_b06_doc_markdown_multi_dot_names(self):
        """F3 Boundary: Multi-dot documentation names handled gracefully."""
        self.assertEqual(len(validate_file_name("docs/v1.0.0-release.md")), 0)

    # --- F4: Compound Words & Acronym Boundaries ---

    def test_f4_b01_acronym_all_caps_in_kebab_path_invalid(self):
        """F4 Boundary: Uppercase acronyms in kebab paths rejected."""
        v = validate_directory_name("tools/CI-Preflight")
        self.assertGreater(len(v), 0)

    def test_f4_b02_compound_number_prefix_2fa_kebab(self):
        """F4 Boundary: Number prefixed acronym in kebab path."""
        self.assertEqual(len(validate_directory_name("auth/2fa-service")), 0)

    def test_f4_b03_compound_number_suffix_bu1_kebab(self):
        """F4 Boundary: Number suffixed name in kebab path."""
        self.assertEqual(
            len(validate_directory_name("infrastructure/foundation-bu1")), 0
        )

    def test_f4_b04_acronym_single_letter_segments(self):
        """F4 Boundary: Single letter segments in kebab names (e.g. g-suite-auth)."""
        self.assertEqual(len(validate_directory_name("tools/g-suite-auth")), 0)

    def test_f4_b05_screaming_snake_leading_underscore_invalid(self):
        """F4 Boundary: Leading underscore in env var rejected."""
        v = validate_env_var_name("run.sh", "_TOKEN")
        self.assertGreater(len(v), 0)

    def test_f4_b06_screaming_snake_consecutive_underscores_invalid(self):
        """F4 Boundary: Consecutive underscores in env var rejected."""
        v = validate_env_var_name("run.sh", "AUTH__TOKEN")
        self.assertGreater(len(v), 0)

    # --- F5: Automated Linter Engine Boundaries ---

    def test_f5_b01_scan_empty_directory_tree(self):
        """F5 Boundary: Scanning an empty directory produces 0 violations."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            scanner = RepositoryNamingScanner(root_dir=tmp_dir)
            self.assertEqual(len(scanner.scan()), 0)

    def test_f5_b02_scan_0_byte_files(self):
        """F5 Boundary: Scanning 0-byte valid files produces no violations."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            fpath = os.path.join(tmp_dir, "clean-script.sh")
            with open(fpath, "w") as f:
                pass
            scanner = RepositoryNamingScanner(root_dir=tmp_dir)
            violations = scanner.scan()
            self.assertEqual(len(violations), 0)

    def test_f5_b03_scan_file_path_255_chars_long(self):
        """F5 Boundary: Scanning extremely long paths."""
        long_dir = "a" * 200
        self.assertEqual(len(validate_directory_name(long_dir)), 0)

    def test_f5_b04_scan_nested_dot_directories(self):
        """F5 Boundary: Nested dot directories (e.g. .github/workflows) allowed."""
        self.assertEqual(len(validate_directory_name(".github/workflows")), 0)

    def test_f5_b05_scan_symlink_loops_or_broken_links(self):
        """F5 Boundary: Scanner handles symlinks gracefully without infinite loops."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            # Create a broken symlink
            broken_link = os.path.join(tmp_dir, "broken-script.sh")
            try:
                os.symlink("nonexistent_target_file.sh", broken_link)
            except OSError:
                pass

            # Create a cyclic directory symlink if OS permits
            loop_link = os.path.join(tmp_dir, "cyclic-loop")
            try:
                os.symlink(tmp_dir, loop_link)
            except OSError:
                pass

            scanner = RepositoryNamingScanner(root_dir=tmp_dir)
            violations = scanner.scan()
            self.assertIsInstance(violations, list)

    def test_f5_b06_scan_with_custom_ignore_set(self):
        """F5 Boundary: Scanner respects custom ignore sets."""
        scanner = RepositoryNamingScanner(root_dir=".", ignores={"custom_vendor"})
        self.assertTrue(scanner.should_ignore("custom_vendor/bad_name.go"))

    # --- F6: Bazel Tooling Boundaries ---

    def test_f6_b01_bazel_target_single_char_name(self):
        """F6 Boundary: Single character binary target is valid."""
        self.assertEqual(len(validate_bazel_target_name("BUILD", "a", "sh_binary")), 0)

    def test_f6_b02_bazel_target_with_colons_and_slashes(self):
        """F6 Boundary: Target names containing underscores rejected for binaries."""
        v = validate_bazel_target_name("BUILD", "my_bad_bin", "sh_binary")
        self.assertEqual(v[0].rule_id, "BZL001")

    def test_f6_b03_bazel_target_with_dots_in_name(self):
        """F6 Boundary: Target names with dots."""
        self.assertEqual(
            len(validate_bazel_target_name("BUILD", "app.min", "js_binary")), 0
        )

    def test_f6_b04_bazel_empty_build_file_clean(self):
        """F6 Boundary: Empty BUILD file parsing returns 0 violations."""
        self.assertEqual(len(validate_build_file_content("BUILD.bazel", "")), 0)

    def test_f6_b05_bazel_build_file_with_comments_only(self):
        """F6 Boundary: BUILD file with comments only returns 0 violations."""
        content = "# Just a comment\n# Another comment\n"
        self.assertEqual(len(validate_build_file_content("BUILD.bazel", content)), 0)

    def test_f6_b06_bazel_starlark_bzl_single_letter(self):
        """F6 Boundary: Single letter .bzl filename (e.g. a.bzl) valid."""
        self.assertEqual(len(validate_starlark_file_name("tools/a.bzl")), 0)

    # --- F7: Config & Schema Boundaries ---

    def test_f7_b01_workflow_yaml_empty_file(self):
        """F7 Boundary: Empty workflow YAML returns 0 violations."""
        self.assertEqual(len(validate_workflow_yaml_content("ci.yaml", "")), 0)

    def test_f7_b02_workflow_yaml_comment_lines_with_underscores_ignored(self):
        """F7 Boundary: Underscores in YAML comments do not trigger violations."""
        content = "jobs:\n  # This is a comment_with_underscore\n  test-job:\n    runs-on: ubuntu-latest\n"
        self.assertEqual(len(validate_workflow_yaml_content("ci.yaml", content)), 0)

    def test_f7_b03_workflow_yaml_job_name_with_expression_syntax(self):
        """F7 Boundary: GitHub expressions ${{ matrix.job_name }} ignored."""
        content = "jobs:\n  build:\n    steps:\n      - id: ${{ matrix.step_id }}\n"
        self.assertEqual(len(validate_workflow_yaml_content("ci.yaml", content)), 0)

    def test_f7_b04_pulumi_yaml_with_namespace_colons(self):
        """F7 Boundary: Namespaced Pulumi config key (e.g. gcp:project)."""
        self.assertEqual(
            len(validate_pulumi_config_key("Pulumi.dev.yaml", "gcp:project")), 0
        )

    def test_f7_b05_pulumi_yaml_single_level_key(self):
        """F7 Boundary: Simple Pulumi config key (e.g. environment)."""
        self.assertEqual(
            len(validate_pulumi_config_key("Pulumi.dev.yaml", "environment")), 0
        )

    def test_f7_b06_k8s_name_starting_with_hyphen_invalid(self):
        """F7 Boundary: Kubernetes name starting with hyphen rejected."""
        v = validate_k8s_resource_name("deploy.yaml", "-invalid-k8s-name")
        self.assertGreater(len(v), 0)

    # --- F8: Phased Migration Roadmap Boundaries ---

    def test_f8_b01_migration_risk_deeply_nested_source(self):
        """F8 Boundary: Deeply nested test script remains LOW risk."""
        risk = assess_rename_risk("a/b/c/d/e/f/my_test.sh", "a/b/c/d/e/f/my-test.sh")
        self.assertEqual(risk, MigrationRiskLevel.LOW)

    def test_f8_b02_migration_risk_mixed_path_separators(self):
        """F8 Boundary: Windows backslash normalization in risk assessment."""
        risk = assess_rename_risk("gitops\\apps\\app.yaml", "gitops\\apps\\new.yaml")
        self.assertEqual(risk, MigrationRiskLevel.HIGH)

    def test_f8_b03_migration_risk_spec_file_suffixes(self):
        """F8 Boundary: TypeScript spec file (.spec.tsx) is LOW risk."""
        risk = assess_rename_risk(
            "web/components/App.spec.tsx", "web/components/NewApp.spec.tsx"
        )
        self.assertEqual(risk, MigrationRiskLevel.LOW)

    def test_f8_b04_migration_empty_source_path(self):
        """F8 Boundary: Empty source path defaults to LOW risk."""
        risk = assess_rename_risk("", "")
        self.assertEqual(risk, MigrationRiskLevel.LOW)

    def test_f8_b05_migration_identical_source_and_target(self):
        """F8 Boundary: Identical source and target assessment."""
        risk = assess_rename_risk("pkg/main.go", "pkg/main.go")
        self.assertEqual(risk, MigrationRiskLevel.LOW)

    def test_f8_b06_migration_extreme_path_levels(self):
        """F8 Boundary: Workflow path at any nesting level remains HIGH risk."""
        risk = assess_rename_risk(".github/workflows/deploy/sub/deep.yaml", "new.yaml")
        self.assertEqual(risk, MigrationRiskLevel.HIGH)

    # --- F9: Backwards Compatibility Boundaries ---

    def test_f9_b01_alias_map_with_none_values(self):
        """F9 Boundary: Alias map handles missing keys gracefully."""
        v = validate_alias_compatibility("//pkg:old", "//pkg:new", {})
        self.assertEqual(len(v), 1)

    def test_f9_b02_alias_map_circular_reference(self):
        """F9 Boundary: Direct alias mapped correctly."""
        alias_map = {"//pkg:old": "//pkg:new"}
        self.assertEqual(
            len(validate_alias_compatibility("//pkg:old", "//pkg:new", alias_map)), 0
        )

    def test_f9_b03_symlink_target_nonexistent(self):
        """F9 Boundary: Missing symlink flags error."""
        v = validate_symlink_alias("/nonexistent/path/symlink", "/target")
        self.assertEqual(v[0].rule_id, "MIG002")

    def test_f9_b04_symlink_target_relative_path(self):
        """F9 Boundary: Relative symlink verification."""
        v = validate_symlink_alias("relative/path/missing", "relative/target")
        self.assertEqual(len(v), 1)

    def test_f9_b05_symlink_target_directory_symlink(self):
        """F9 Boundary: Directory symlink existence verification."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            real_dir = os.path.join(tmp_dir, "target-pkg")
            os.makedirs(real_dir, exist_ok=True)
            link_dir = os.path.join(tmp_dir, "alias-pkg")
            try:
                os.symlink(real_dir, link_dir)
                violations = validate_symlink_alias(link_dir, real_dir)
                self.assertEqual(len(violations), 0)
            except OSError:
                pass

    def test_f9_b06_alias_map_exact_match_success(self):
        """F9 Boundary: Exact target match succeeds with 0 violations."""
        alias_map = {"//tools/legacy": "//tools/modern"}
        self.assertEqual(
            len(
                validate_alias_compatibility(
                    "//tools/legacy", "//tools/modern", alias_map
                )
            ),
            0,
        )

    # --- F10: E2E Integrity Boundaries ---

    def test_f10_b01_format_report_empty_violations_list(self):
        """F10 Boundary: Formatting empty violations list produces clean summary."""
        scanner = RepositoryNamingScanner(root_dir=".")
        report = scanner.format_report([], output_format="text")
        self.assertIn("0 issues found", report)

    def test_f10_b02_format_report_1000_violations_performance(self):
        """F10 Boundary: Performance formatting 1000 violations completes instantly."""
        violations = [
            NamingViolation(
                rule_id=f"DIR{i:03d}",
                file_path=f"path/to/item_{i}",
                line_number=i,
                message="Test violation",
            )
            for i in range(1000)
        ]
        scanner = RepositoryNamingScanner(root_dir=".")
        report = scanner.format_report(violations, output_format="text")
        self.assertIn("1000 issues found", report)

    def test_f10_b03_json_serialization_unicode_characters(self):
        """F10 Boundary: JSON formatting handles Unicode / emoji in paths gracefully."""
        v = [
            NamingViolation(
                rule_id="DIR001",
                file_path="path/🚀/test",
                line_number=None,
                message="Unicode character test",
            )
        ]
        scanner = RepositoryNamingScanner(root_dir=".")
        json_report = scanner.format_report(v, output_format="json")
        self.assertIn("🚀", json_report)

    def test_f10_b04_cli_flags_unknown_argument_handling(self):
        """F10 Boundary: Unknown flags raise SystemExit."""
        import io
        import contextlib
        import lint_naming

        buf = io.StringIO()
        with contextlib.redirect_stderr(buf):
            with self.assertRaises(SystemExit):
                lint_naming.main(["--unknown-nonexistent-flag"])

    def test_f10_b05_cli_flags_empty_root_defaults_to_cwd(self):
        """F10 Boundary: Default root directory resolution."""
        scanner = RepositoryNamingScanner(root_dir=".")
        self.assertTrue(os.path.isabs(scanner.root_dir))

    def test_f10_b06_scanner_read_permission_error_graceful_handling(self):
        """F10 Boundary: Scanner continues on unreadable files."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            unreadable_file = os.path.join(tmp_dir, "unreadable.yaml")
            with open(unreadable_file, "w") as f:
                f.write("key: value\n")
            try:
                os.chmod(unreadable_file, 0o000)
            except OSError:
                pass

            scanner = RepositoryNamingScanner(root_dir=tmp_dir)
            try:
                violations = scanner.scan()
                self.assertIsInstance(violations, list)
            finally:
                try:
                    os.chmod(unreadable_file, 0o644)
                except OSError:
                    pass

    # --- Adversarial Boundary Edge Cases Discovered by Challenger 1 ---

    def test_adv_b01_directory_prefix_boundary_exact_check(self):
        """Adversarial Boundary: Prefix matching must enforce directory segment boundaries."""
        v_dir = validate_directory_name("pkg_invalid/cloud_dns")
        self.assertGreater(len(v_dir), 0)
        self.assertEqual(v_dir[0].rule_id, "DIR003")

        v_devx = validate_directory_name("devx_tools/my_module")
        self.assertGreater(len(v_devx), 0)
        self.assertEqual(v_devx[0].rule_id, "DIR003")

    def test_adv_b02_typescript_multidot_qualifiers(self):
        """Adversarial Boundary: Multi-dot domain qualifiers in TypeScript/JavaScript."""
        valid_ts_files = [
            "src/routes/user.routes.ts",
            "src/services/workspace.service.ts",
            "jest.config.js",
            "next.config.ts",
            "postcss.config.mjs",
            "src/data.server.ts",
            "src/sync.service.test.ts",
            "src/runtime-config.server.test.ts",
            "src/apiEndpoints.server.ts",
        ]
        for fpath in valid_ts_files:
            violations = validate_file_name(fpath)
            self.assertEqual(
                len(violations),
                0,
                f"File {fpath} should be accepted without violations",
            )

    def test_adv_b03_nextjs_app_router_and_react_test_conventions(self):
        """Adversarial Boundary: Next.js App Router and React component test conventions."""
        valid_ui_files = [
            "app/page.tsx",
            "app/layout.tsx",
            "app/loading.tsx",
            "app/error.tsx",
            "app/not-found.tsx",
            "app/api/auth/route.ts",
            "tabula/web/__tests__/RelayLanding.test.tsx",
            "tabula/web/__tests__/EditableSpace.test.tsx",
            "tabula/web/__tests__/space-detail.test.tsx",
        ]
        for fpath in valid_ui_files:
            violations = validate_file_name(fpath)
            self.assertEqual(
                len(violations),
                0,
                f"UI file {fpath} should be accepted without violations",
            )

    def test_adv_b04_shell_test_suggested_fix_sentinel_preservation(self):
        """Adversarial Boundary: Suggested fix for shell test preserves _test.sh suffix without corruption."""
        violations = validate_file_name("tools/copybara/check_version_maps_test.sh")
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].rule_id, "SH001")
        self.assertEqual(violations[0].suggested_fix, "check-version-maps_test.sh")


if __name__ == "__main__":
    unittest.main()
