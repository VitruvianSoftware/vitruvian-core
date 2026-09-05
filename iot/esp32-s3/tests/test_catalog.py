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

"""
mac-controller/tests/test_catalog.py
Automated test suite for Backstage catalog component entity compliance,
root catalog wiring, document link resolution, and CODEOWNERS conformance.

Covers:
1. File existence, YAML syntax validity, and license header presence.
2. Backstage Component entity schema validation (apiVersion, kind, metadata, annotations, spec).
3. Monorepo root catalog-info.yaml Location wiring and target registration.
4. Documentation link resolution against physical repository files.
5. .github/CODEOWNERS entry validation and ownership consistency (spec.owner == coteam).
6. mac-controller/OWNERS syntax and handle validity.
"""

import os
import sys
import re
import unittest
import yaml

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
COMPONENT_DIR = os.path.dirname(TESTS_DIR)


def get_repo_root():
    cur = os.path.dirname(os.path.abspath(__file__))
    while cur and cur != os.path.dirname(cur):
        if os.path.isfile(os.path.join(cur, "MODULE.bazel")) or os.path.isdir(
            os.path.join(cur, ".git")
        ):
            return cur
        cur = os.path.dirname(cur)
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))


REPO_ROOT = os.environ.get("BUILD_WORKSPACE_DIRECTORY", get_repo_root())

CATALOG_INFO_PATH = os.path.join(COMPONENT_DIR, "catalog-info.yaml")
ROOT_CATALOG_PATH = os.path.join(REPO_ROOT, "catalog-info.yaml")
CODEOWNERS_PATH = os.path.join(REPO_ROOT, ".github", "CODEOWNERS")
OWNERS_PATH = os.path.join(COMPONENT_DIR, "OWNERS")
DOCS_DIR = os.path.join(COMPONENT_DIR, "docs")


class TestCatalogFileIntegrity(unittest.TestCase):
    """Verifies that mac-controller/catalog-info.yaml exists and parses cleanly."""

    def test_catalog_file_exists(self):
        self.assertTrue(
            os.path.isfile(CATALOG_INFO_PATH),
            f"Missing Backstage catalog file at {CATALOG_INFO_PATH}",
        )

    def test_catalog_yaml_syntax(self):
        self.assertTrue(
            os.path.isfile(CATALOG_INFO_PATH), "Catalog file does not exist"
        )
        with open(CATALOG_INFO_PATH, "r", encoding="utf-8") as f:
            try:
                data = yaml.safe_load(f)
            except yaml.YAMLError as e:
                self.fail(f"catalog-info.yaml contains invalid YAML: {e}")
        self.assertIsInstance(
            data, dict, "Parsed catalog-info.yaml must be a YAML mapping/dictionary"
        )

    def test_license_header_present(self):
        """Monorepo hygiene: catalog-info.yaml must carry standard VitruvianSoftware copyright notice."""
        self.assertTrue(
            os.path.isfile(CATALOG_INFO_PATH), "Catalog file does not exist"
        )
        with open(CATALOG_INFO_PATH, "r", encoding="utf-8") as f:
            head = f.read(500)
        self.assertIn(
            "Copyright (c) 2026 VitruvianSoftware",
            head,
            "catalog-info.yaml must include VitruvianSoftware copyright header",
        )


class TestBackstageComponentSchema(unittest.TestCase):
    """Verifies strict compliance with Backstage Component entity specifications."""

    @classmethod
    def setUpClass(cls):
        if not os.path.isfile(CATALOG_INFO_PATH):
            raise unittest.SkipTest(
                f"Skipping schema tests: {CATALOG_INFO_PATH} not found"
            )
        with open(CATALOG_INFO_PATH, "r", encoding="utf-8") as f:
            cls.catalog = yaml.safe_load(f) or {}

    def test_api_version(self):
        self.assertEqual(
            self.catalog.get("apiVersion"),
            "backstage.io/v1alpha1",
            "apiVersion must be backstage.io/v1alpha1",
        )

    def test_kind(self):
        self.assertEqual(
            self.catalog.get("kind"),
            "Component",
            "kind must be Component",
        )

    def test_metadata_name_conformance(self):
        """metadata.name MUST equal 'esp32-s3' (or 'mac-controller')."""
        metadata = self.catalog.get("metadata", {})
        self.assertIn(
            metadata.get("name"),
            ["esp32-s3", "mac-controller"],
            "metadata.name must match component name 'esp32-s3'",
        )

    def test_metadata_title(self):
        metadata = self.catalog.get("metadata", {})
        title = metadata.get("title")
        self.assertIsInstance(title, str, "metadata.title must be a string")
        self.assertTrue(len(title.strip()) > 0, "metadata.title must not be empty")

    def test_metadata_description(self):
        metadata = self.catalog.get("metadata", {})
        desc = metadata.get("description")
        self.assertIsInstance(desc, str, "metadata.description must be a string")
        self.assertTrue(
            len(desc.strip()) >= 20,
            "metadata.description must provide meaningful details (>= 20 chars)",
        )

    def test_metadata_tags(self):
        metadata = self.catalog.get("metadata", {})
        tags = metadata.get("tags")
        self.assertIsInstance(tags, list, "metadata.tags must be a list of strings")
        self.assertTrue(
            len(tags) >= 3, "metadata.tags should include at least 3 descriptive tags"
        )
        tag_pattern = re.compile(r"^[a-z0-9-]+$")
        for tag in tags:
            self.assertRegex(
                tag,
                tag_pattern,
                f"Tag '{tag}' must be lowercase alphanumeric or hyphenated",
            )
        expected_tags = {"esp32-s3", "embedded", "macos"}
        self.assertTrue(
            expected_tags.issubset(set(tags)),
            f"metadata.tags missing expected core tags: {expected_tags - set(tags)}",
        )

    def test_metadata_annotations(self):
        metadata = self.catalog.get("metadata", {})
        annotations = metadata.get("annotations", {})
        self.assertEqual(
            annotations.get("github.com/project-slug"),
            "VitruvianSoftware/vitruvian-core",
            "Missing or invalid github.com/project-slug annotation",
        )
        self.assertEqual(
            annotations.get("backstage.io/techdocs-ref"),
            "dir:.",
            "backstage.io/techdocs-ref must point to 'dir:.'",
        )
        self.assertEqual(
            annotations.get("vitruvian.dev/release-model"),
            "monorepo-bazel",
            "vitruvian.dev/release-model annotation must be monorepo-bazel",
        )

    def test_spec_type(self):
        spec = self.catalog.get("spec", {})
        allowed_types = {"application", "tool", "device", "hardware", "service"}
        self.assertIn(
            spec.get("type"),
            allowed_types,
            f"spec.type must be one of {allowed_types}",
        )

    def test_spec_lifecycle(self):
        spec = self.catalog.get("spec", {})
        allowed_lifecycles = {"experimental", "development", "production"}
        self.assertIn(
            spec.get("lifecycle"),
            allowed_lifecycles,
            f"spec.lifecycle must be one of {allowed_lifecycles}",
        )

    def test_spec_owner(self):
        """spec.owner must be 'platform-team' to agree with .github/CODEOWNERS."""
        spec = self.catalog.get("spec", {})
        self.assertEqual(
            spec.get("owner"),
            "platform-team",
            "spec.owner must be 'platform-team' to match CODEOWNERS coteam extraction",
        )

    def test_spec_system(self):
        spec = self.catalog.get("spec", {})
        self.assertEqual(
            spec.get("system"),
            "vitruvian-core",
            "spec.system must reference root system 'vitruvian-core'",
        )


class TestRootCatalogWiring(unittest.TestCase):
    """Verifies that mac-controller/catalog-info.yaml is wired into root catalog-info.yaml."""

    @classmethod
    def setUpClass(cls):
        if not os.path.isfile(ROOT_CATALOG_PATH):
            raise unittest.SkipTest(
                f"Root catalog file not found at {ROOT_CATALOG_PATH}"
            )
        with open(ROOT_CATALOG_PATH, "r", encoding="utf-8") as f:
            cls.root_docs = list(yaml.safe_load_all(f))
            f.seek(0)
            cls.root_raw = f.read()

    def test_root_catalog_contains_mac_controller_target(self):
        """Finds Location vitruvian-core-apps and asserts ./iot/esp32-s3/catalog-info.yaml in spec.targets."""
        location_apps = None
        for doc in self.root_docs:
            if not isinstance(doc, dict):
                continue
            if (
                doc.get("kind") == "Location"
                and doc.get("metadata", {}).get("name") == "vitruvian-core-apps"
            ):
                location_apps = doc
                break

        self.assertIsNotNone(
            location_apps,
            "Could not find Location entity 'vitruvian-core-apps' in root catalog-info.yaml",
        )
        targets = location_apps.get("spec", {}).get("targets", [])
        valid_targets = [
            "./iot/esp32-s3/catalog-info.yaml",
            "./mac-controller/catalog-info.yaml",
        ]
        self.assertTrue(
            any(t in targets for t in valid_targets),
            f"Root Location targets missing target from {valid_targets}. Current targets: {targets}",
        )

    def test_conformance_grep_target_alignment(self):
        """Simulates tools/conformance/check.sh literal grep check."""
        valid_targets = [
            "./iot/esp32-s3/catalog-info.yaml",
            "./mac-controller/catalog-info.yaml",
        ]
        self.assertTrue(
            any(t in self.root_raw for t in valid_targets),
            f"Root catalog-info.yaml does not literally contain any of {valid_targets}",
        )


class TestDocumentationLinksResolution(unittest.TestCase):
    """Verifies that all documentation links in catalog-info.yaml resolve to real filesystem files."""

    @classmethod
    def setUpClass(cls):
        if not os.path.isfile(CATALOG_INFO_PATH):
            raise unittest.SkipTest(f"Catalog file not found at {CATALOG_INFO_PATH}")
        with open(CATALOG_INFO_PATH, "r", encoding="utf-8") as f:
            cls.catalog = yaml.safe_load(f) or {}

    def test_links_structure(self):
        links = self.catalog.get("metadata", {}).get("links", [])
        self.assertIsInstance(links, list, "metadata.links must be a list")
        self.assertTrue(
            len(links) >= 5, "Expected at least 5 links covering docs and repo tree"
        )

        for idx, link in enumerate(links):
            self.assertIn("url", link, f"Link #{idx} missing 'url'")
            self.assertIn("title", link, f"Link #{idx} missing 'title'")
            self.assertIn("icon", link, f"Link #{idx} missing 'icon'")

    def test_documentation_file_links_resolve_locally(self):
        """Ensures that any monorepo blob/tree link points to a real existing file/dir."""
        links = self.catalog.get("metadata", {}).get("links", [])
        blob_prefix = "https://github.com/VitruvianSoftware/vitruvian-core/blob/main/"
        tree_prefix = "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/"

        checked_links = 0
        for link in links:
            url = link["url"]
            if url.startswith(blob_prefix):
                rel_path = url[len(blob_prefix) :]
                abs_path = os.path.join(REPO_ROOT, rel_path)
                self.assertTrue(
                    os.path.isfile(abs_path),
                    f"Link '{link['title']}' points to non-existent file: {abs_path} (from {url})",
                )
                checked_links += 1
            elif url.startswith(tree_prefix):
                rel_path = url[len(tree_prefix) :]
                abs_path = os.path.join(REPO_ROOT, rel_path)
                self.assertTrue(
                    os.path.isdir(abs_path),
                    f"Link '{link['title']}' points to non-existent directory: {abs_path} (from {url})",
                )
                checked_links += 1

        self.assertTrue(
            checked_links >= 4,
            f"Expected at least 4 local repo links verified, got {checked_links}",
        )

    def test_core_documentation_files_exist(self):
        """Verifies presence of the complete documentation suite planned for mac-controller."""
        expected_docs = [
            os.path.join(COMPONENT_DIR, "README.md"),
            os.path.join(DOCS_DIR, "architecture.md"),
            os.path.join(DOCS_DIR, "protocol.md"),
            os.path.join(DOCS_DIR, "hardware.md"),
            os.path.join(DOCS_DIR, "flashing.md"),
        ]
        for doc_path in expected_docs:
            self.assertTrue(
                os.path.isfile(doc_path),
                f"Missing required documentation file: {doc_path}",
            )


class TestCodeownersConformance(unittest.TestCase):
    """Verifies that mac-controller ownership is registered in .github/CODEOWNERS and conforms to policy."""

    def test_codeowners_file_exists(self):
        self.assertTrue(
            os.path.isfile(CODEOWNERS_PATH),
            f"Missing .github/CODEOWNERS file at {CODEOWNERS_PATH}",
        )

    def test_codeowners_contains_mac_controller_rule(self):
        with open(CODEOWNERS_PATH, "r", encoding="utf-8") as f:
            lines = [
                line.strip()
                for line in f
                if line.strip() and not line.strip().startswith("#")
            ]

        found_rule = False
        for line in lines:
            parts = line.split()
            if parts and parts[0] in ("/iot/esp32-s3/", "/iot/", "/mac-controller/"):
                found_rule = True
                self.assertIn(
                    "@VitruvianSoftware/platform-team",
                    parts[1:],
                    f"Rule for {parts[0]} must assign @VitruvianSoftware/platform-team. Line: '{line}'",
                )
                break

        self.assertTrue(
            found_rule,
            "Could not find ownership rule for '/iot/esp32-s3/' in .github/CODEOWNERS",
        )

    def test_spec_owner_matches_codeowners_team(self):
        """Strict check_app_metadata conformance: spec.owner must equal the CODEOWNERS team slug."""
        if not os.path.isfile(CATALOG_INFO_PATH):
            raise unittest.SkipTest(f"Catalog file not found at {CATALOG_INFO_PATH}")

        with open(CATALOG_INFO_PATH, "r", encoding="utf-8") as f:
            catalog = yaml.safe_load(f) or {}
        catalog_owner = catalog.get("spec", {}).get("owner")

        with open(CODEOWNERS_PATH, "r", encoding="utf-8") as f:
            coteam = None
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2 and parts[0] in (
                    "/iot/esp32-s3/",
                    "/iot/",
                    "/mac-controller/",
                ):
                    coteam = parts[1].split("/")[-1]
                    break

        self.assertIsNotNone(
            coteam, "No /iot/esp32-s3/ rule found in .github/CODEOWNERS"
        )
        self.assertEqual(
            catalog_owner,
            coteam,
            f"spec.owner ('{catalog_owner}') disagrees with CODEOWNERS team ('{coteam}')",
        )

    def test_local_owners_file_valid(self):
        """Verifies mac-controller/OWNERS format and approvers."""
        self.assertTrue(os.path.isfile(OWNERS_PATH), f"Missing {OWNERS_PATH}")
        with open(OWNERS_PATH, "r", encoding="utf-8") as f:
            owners_data = yaml.safe_load(f) or {}

        approvers = owners_data.get("approvers", [])
        self.assertIn(
            "@VitruvianSoftware/platform-team",
            approvers,
            f"mac-controller/OWNERS approvers must include '@VitruvianSoftware/platform-team'. Found: {approvers}",
        )


if __name__ == "__main__":
    unittest.main()
