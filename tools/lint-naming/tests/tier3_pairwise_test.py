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

"""Tier 3: Pairwise Cross-Feature Interactions Test Suite.

Verifies interactions between different ecosystems, tooling layers, and conventions:
- Python modules inside Bazel py_library in kebab directories
- Go source files inside snake_case package dirs with Gazelle go_test targets
- React components in TypeScript library with package.json
- Shell CLI tools with --kebab-case flags and SCREAMING_SNAKE env vars
- GitHub Actions workflows running Bazel targets
- Pulumi stacks importing Go infrastructure modules
- Kubernetes manifests rendered via Helm in GitOps repos
- Migration symlinks paired with Bazel alias rules
- Copybara sync configs mapping monorepo directories
- Prisma migrations in Next.js apps
"""

import os
import sys
import unittest

# Ensure tools/lint-naming is on python path
_PKG_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_DIR not in sys.path:
    sys.path.insert(0, _PKG_DIR)

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


class Tier3PairwiseTestSuite(unittest.TestCase):
    """Tier 3 Cross-Feature Interaction Tests."""

    def test_p01_python_module_with_bazel_py_library_and_kebab_tool_dir(self):
        """Pairwise: Python snake_case module in kebab tool dir with py_library."""
        self.assertEqual(len(validate_directory_name("tools/stream-processor")), 0)
        self.assertEqual(len(validate_file_name("tools/stream-processor/stream_hook.py")), 0)
        self.assertEqual(len(validate_bazel_target_name("BUILD", "stream_processor_lib", "py_library")), 0)

    def test_p02_go_source_with_bazel_go_test_and_snake_package_dir(self):
        """Pairwise: Go snake_case source in snake package dir with go_test."""
        self.assertEqual(len(validate_directory_name("pkg/cloud_dns")), 0)
        self.assertEqual(len(validate_file_name("pkg/cloud_dns/cloud_dns.go")), 0)
        self.assertEqual(len(validate_file_name("pkg/cloud_dns/cloud_dns_test.go")), 0)
        self.assertEqual(len(validate_bazel_target_name("BUILD", "cloud_dns_test", "go_test")), 0)

    def test_p03_react_tsx_component_with_kebab_lib_and_package_json(self):
        """Pairwise: React component in TypeScript lib with package.json."""
        self.assertEqual(len(validate_directory_name("packages/design-system")), 0)
        self.assertEqual(len(validate_file_name("packages/design-system/src/Button.tsx")), 0)
        self.assertEqual(len(validate_file_name("packages/design-system/src/index.ts")), 0)

    def test_p04_shell_cli_script_with_kebab_flag_and_screaming_env(self):
        """Pairwise: Shell script reading SCREAMING_SNAKE env and parsing --kebab-case flag."""
        self.assertEqual(len(validate_file_name("tools/agent-app/agent-app.sh")), 0)
        self.assertEqual(len(validate_cli_flag_name("agent-app.sh", "--dry-run")), 0)
        self.assertEqual(len(validate_env_var_name("agent-app.sh", "GH_TOKEN")), 0)

    def test_p05_github_workflow_invoking_bazel_binary_with_kebab_job_id(self):
        """Pairwise: Workflow with kebab job ID running Bazel binary."""
        content = "jobs:\n  license-check:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bazel run //tools/license:check\n"
        self.assertEqual(len(validate_workflow_yaml_content(".github/workflows/ci.yaml", content)), 0)
        self.assertEqual(len(validate_bazel_target_name("tools/license/BUILD", "check", "sh_binary")), 0)

    def test_p06_pulumi_kebab_project_with_snake_go_module(self):
        """Pairwise: Pulumi kebab project importing snake_case Go module."""
        self.assertEqual(len(validate_directory_name("infrastructure/pulumi/foundation-gcp-networks")), 0)
        self.assertEqual(len(validate_directory_name("infrastructure/pulumi/foundation-gcp-networks/modules/cloud_dns")), 0)
        self.assertEqual(len(validate_file_name("infrastructure/pulumi/foundation-gcp-networks/modules/cloud_dns/main.go")), 0)

    def test_p07_kubernetes_manifest_with_helm_camel_values_in_kebab_gitops_dir(self):
        """Pairwise: Kubernetes resource in GitOps dir with Helm config."""
        self.assertEqual(len(validate_directory_name("gitops/apps/auth-service")), 0)
        self.assertEqual(len(validate_k8s_resource_name("gitops/apps/auth-service/deploy.yaml", "auth-service")), 0)
        self.assertEqual(len(validate_file_name("gitops/apps/auth-service/values.yaml")), 0)

    def test_p08_bazel_starlark_bzl_generating_kebab_binary_and_shell_test(self):
        """Pairwise: Starlark defs.bzl generating CLI binary and test target."""
        self.assertEqual(len(validate_starlark_file_name("tools/defs.bzl")), 0)
        self.assertEqual(len(validate_bazel_target_name("BUILD", "deploy-tool", "sh_binary")), 0)
        self.assertEqual(len(validate_bazel_target_name("BUILD", "deploy-tool_test", "sh_test")), 0)

    def test_p09_migration_symlink_with_bazel_alias_for_renamed_script(self):
        """Pairwise: Migrated script pairing symlink with Bazel alias target."""
        alias_map = {"//tools/ci:affected_targets": "//tools/ci:affected-targets"}
        self.assertEqual(len(validate_alias_compatibility("//tools/ci:affected_targets", "//tools/ci:affected-targets", alias_map)), 0)
        risk = assess_rename_risk("tools/ci/affected_targets.sh", "tools/ci/affected-targets.sh")
        self.assertEqual(risk, MigrationRiskLevel.MEDIUM)

    def test_p10_copybara_export_mapping_kebab_directory_to_standalone_repo(self):
        """Pairwise: Copybara config mapping kebab monorepo directory to mirror."""
        self.assertEqual(len(validate_directory_name("oauth-user-inspector", is_root=True)), 0)
        self.assertEqual(len(validate_file_name("tools/copybara/copy.bara.sky")), 0)

    def test_p11_prisma_timestamp_migration_inside_nextjs_app_with_pascal_components(self):
        """Pairwise: Prisma migration alongside React TSX component."""
        self.assertEqual(len(validate_directory_name("tabula/web/prisma/migrations/20260524120000_create_users")), 0)
        self.assertEqual(len(validate_file_name("tabula/web/components/UserProfile.tsx")), 0)
        self.assertEqual(len(validate_file_name("tabula/web/lib/api-client.ts")), 0)

    def test_p12_swift_macos_app_with_kebab_bazel_bundle_and_pascal_source(self):
        """Pairwise: Swift PascalCase source in macOS app with Bazel target."""
        self.assertEqual(len(validate_file_name("nexus-agent/macos/Sources/NexusAgent/AppDelegate.swift")), 0)
        self.assertEqual(len(validate_bazel_target_name("nexus-agent/macos/BUILD", "NexusAgent", "macos_application")), 0)

    def test_p13_backstage_catalog_info_yaml_referencing_kebab_component(self):
        """Pairwise: Backstage catalog-info.yaml referencing kebab component."""
        self.assertEqual(len(validate_file_name("catalog-info.yaml")), 0)
        self.assertEqual(len(validate_directory_name("backstage/packages/app")), 0)

    def test_p14_python_py_test_runner_validating_yaml_workflow_schemas(self):
        """Pairwise: Python test runner scanning workflow YAML."""
        content = "jobs:\n  unit-tests:\n    runs-on: ubuntu-latest\n"
        self.assertEqual(len(validate_workflow_yaml_content("ci.yaml", content)), 0)
        self.assertEqual(len(validate_file_name("tools/pytest/defs.bzl")), 0)

    def test_p15_cross_ecosystem_container_oci_target_with_kebab_script_entrypoint(self):
        """Pairwise: OCI container target running kebab-case shell script."""
        self.assertEqual(len(validate_bazel_target_name("tools/oci/BUILD", "deploy-image", "oci_image")), 0)
        self.assertEqual(len(validate_file_name("tools/delivery/deploy-affected.sh")), 0)

    def test_p16_cli_long_flag_and_env_var_override_pairing(self):
        """Pairwise: CLI flag paired with env var fallback."""
        self.assertEqual(len(validate_cli_flag_name("tool.sh", "--workspace-dir")), 0)
        self.assertEqual(len(validate_env_var_name("tool.sh", "WORKSPACE_DIR")), 0)

    def test_p17_pulumi_yaml_stack_config_referencing_gcp_project_and_env_vars(self):
        """Pairwise: Pulumi config key paired with GCP project variable."""
        self.assertEqual(len(validate_pulumi_config_key("Pulumi.dev.yaml", "gcp:project")), 0)
        self.assertEqual(len(validate_env_var_name("script.sh", "GOOGLE_CLOUD_PROJECT")), 0)

    def test_p18_git_preflight_hook_scanning_staged_go_and_shell_files(self):
        """Pairwise: Git preflight hook scanning staged Go and Shell files."""
        self.assertEqual(len(validate_file_name("tools/ci-preflight/ci-preflight.sh")), 0)
        self.assertEqual(len(validate_file_name("pkg/net_hubs.go")), 0)

    def test_p19_gazelle_python_yaml_manifest_with_snake_case_py_targets(self):
        """Pairwise: Gazelle config with Python snake_case target generation."""
        self.assertEqual(len(validate_file_name("tools/lint_naming.py")), 0)
        self.assertEqual(len(validate_bazel_target_name("BUILD", "lint_naming_lib", "py_library")), 0)

    def test_p20_monorepo_audit_report_correlating_file_violations_with_migration_risk(self):
        """Pairwise: Scanner violation correlated with migration risk level."""
        v = validate_file_name("tools/gitops/argocd_secret.sh")
        self.assertEqual(len(v), 1)
        risk = assess_rename_risk("tools/gitops/argocd_secret.sh", "tools/gitops/argocd-secret.sh")
        self.assertEqual(risk, MigrationRiskLevel.MEDIUM)


if __name__ == "__main__":
    unittest.main()
