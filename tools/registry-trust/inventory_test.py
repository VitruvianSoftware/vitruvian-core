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

"""The inventory comes from release-please and the package files, not a list."""

import os
import tempfile
import unittest

import fixture_repo
import inventory


def names(found, registry=None):
    return sorted(
        p.name for p in found.packages if registry is None or p.registry == registry
    )


class InventoryTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(dir=os.environ.get("TEST_TMPDIR"))
        self.addCleanup(self._tmp.cleanup)
        self.root = fixture_repo.make(self._tmp.name)

    def package(self, registry, name):
        found = inventory.load(self.root)
        for package in found.packages:
            if (package.registry, package.name) == (registry, name):
                return package
        self.fail(f"{name} is not in the {registry} inventory: {found.packages}")

    def test_the_extra_files_that_carry_a_version_are_the_packages(self):
        found = inventory.load(self.root)
        self.assertEqual(found.problems, [])
        self.assertEqual(names(found, "pypi"), ["example-kit"])
        self.assertEqual(names(found, "crates"), ["example-kit"])
        self.assertIn("@example/kit", names(found, "npm"))

    def test_a_package_carries_its_version_and_where_it_came_from(self):
        kit = self.package("crates", "example-kit")
        self.assertEqual(kit.version, "1.1.0")
        self.assertEqual(kit.file, "packages/sdk/kits/rs/Cargo.toml")
        self.assertEqual(kit.path, "packages/sdk")
        self.assertEqual(kit.config, "packages/sdk/release-please-config.json")

    def test_the_mirror_is_the_copybara_component_that_holds_the_package(self):
        kit = self.package("crates", "example-kit")
        self.assertEqual((kit.owner, kit.repo), ("Example", "sdk-mirror"))
        self.assertEqual(kit.repository, "Example/sdk-mirror")

    def test_the_workflow_and_environment_are_the_publishing_job_s(self):
        crate = self.package("crates", "example-kit")
        self.assertEqual(
            (crate.workflow, crate.job, crate.environment),
            ("release.yml", "crates-publish", "crates-io"),
        )
        python = self.package("pypi", "example-kit")
        self.assertEqual(
            (python.workflow, python.job, python.environment),
            ("release.yml", "publish-pypi-kit", "pypi"),
        )
        node = self.package("npm", "@example/kit")
        self.assertEqual(
            (node.workflow, node.job, node.environment),
            ("release.yml", "publish-npm-kit", ""),
        )

    def test_a_sample_that_only_depends_on_a_kit_is_not_a_package(self):
        found = inventory.load(self.root)
        self.assertNotIn("hello", names(found))
        self.assertNotIn("hello-rs", names(found))

    def test_a_node_release_is_its_package_json(self):
        a = self.package("npm", "@example/a")
        self.assertEqual(a.version, "0.4.1")
        self.assertEqual(a.file, "packages/lib/ts/packages/a/package.json")
        self.assertEqual(
            (a.repository, a.workflow), ("Example/lib-mirror", "release.yml")
        )
        self.assertEqual(a.job, "release")

    def test_a_private_package_and_an_unpublished_crate_are_left_out(self):
        found = inventory.load(self.root)
        self.assertNotIn("@example/priv", names(found))
        self.assertNotIn("example-internal", names(found))
        reasons = dict(found.skipped)
        self.assertIn("private", reasons["packages/lib/ts/packages/priv/package.json"])
        self.assertIn(
            "publish = false", reasons["packages/sdk/kits/internal/Cargo.toml"]
        )

    def test_a_package_no_workflow_publishes_is_left_out_and_said(self):
        found = inventory.load(self.root)
        self.assertNotIn("some-app", names(found))
        self.assertIn("no job", dict(found.skipped)["app/package.json"])

    def test_a_package_no_mirror_carries_is_left_out_and_said(self):
        found = inventory.load(self.root)
        self.assertNotIn("@example/nomirror", names(found))
        self.assertIn("no mirror", dict(found.skipped)["apps/nomirror/package.json"])

    def test_node_modules_is_not_walked(self):
        found = inventory.load(self.root)
        self.assertNotIn("@example/dep", names(found))
        self.assertNotIn("node_modules/dep/package.json", dict(found.skipped))

    def test_a_package_added_to_release_please_is_found_with_no_other_edit(self):
        before = names(inventory.load(self.root), "npm")
        fixture_repo.node_package(
            self.root, "packages/lib/ts/packages/new", "@example/new", "0.1.0"
        )
        after = names(inventory.load(self.root), "npm")
        self.assertEqual(sorted(before + ["@example/new"]), after)

    def test_two_jobs_that_publish_one_registry_is_a_problem_not_a_guess(self):
        fixture_repo.write(
            self.root,
            "packages/sdk/.github/workflows/again.yml",
            "jobs:\n  twice:\n    runs-on: ubuntu-latest\n    steps:\n"
            "      - run: cargo publish\n",
        )
        found = inventory.load(self.root)
        self.assertEqual(names(found, "crates"), [])
        self.assertEqual(len(found.problems), 1)
        self.assertIn("example-kit", found.problems[0])
        self.assertIn("again.yml", found.problems[0])
        self.assertIn("release.yml", found.problems[0])

    def test_a_config_whose_version_file_is_missing_is_a_problem(self):
        os.remove(os.path.join(self.root, "packages/sdk/kits/rs/Cargo.toml"))
        found = inventory.load(self.root)
        self.assertEqual(len(found.problems), 1)
        self.assertIn("packages/sdk/kits/rs/Cargo.toml", found.problems[0])


class RealCopybaraTest(unittest.TestCase):
    """The mirrors are read from the real copy.bara.sky with a pattern, not
    by running it. If its layout moves, a mirror would quietly go missing and
    its packages with it; this says so instead."""

    ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")

    def test_every_component_of_the_real_file_is_read(self):
        with open(os.path.join(self.ROOT, inventory.COPYBARA), encoding="utf-8") as f:
            declared = sum(
                1 for line in f if line.strip().startswith('"standalone_rev_id":')
            )
        found = inventory.mirrors(self.ROOT)
        self.assertGreater(declared, 10)
        self.assertEqual(len(found), declared)
        self.assertIn(
            ("packages/vitruvian-sdk", "VitruvianSoftware", "vitruvian-sdk"), found
        )
        self.assertIn(
            ("packages/pulumi/library", "VitruvianSoftware", "pulumi-library"), found
        )
        # nexus-agent names no "repo": it is its name.
        self.assertIn(
            ("apps/desktop/nexus-agent", "VitruvianSoftware", "nexus-agent"), found
        )


if __name__ == "__main__":
    unittest.main()
