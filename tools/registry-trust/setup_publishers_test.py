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

"""Setup makes the registry-side trust from what the code says, and says
plainly what it cannot make. Nothing here uses the network or a real token."""

import io
import json
import os
import tempfile
import unittest

import fixture_repo
import setup_publishers as setup

TOKEN = "cio-test-token-that-must-never-be-shown"
LIST = "https://crates.io/api/v1/trusted_publishing/github_configs?crate=example-kit"
CREATE = "https://crates.io/api/v1/trusted_publishing/github_configs"
WANTED = {
    "crate": "example-kit",
    "repository_owner": "Example",
    "repository_name": "sdk-mirror",
    "workflow_filename": "release.yml",
    "environment": "crates-io",
}


class World:
    """The registries, as a test set them up; and every call made to them."""

    def __init__(self):
        self.public = {
            "https://crates.io/api/v1/crates/example-kit": 200,
            "https://pypi.org/pypi/example-kit/json": 200,
            "https://registry.npmjs.org/@example%2Fkit": 200,
            "https://registry.npmjs.org/@example%2Fa": 200,
            "https://registry.npmjs.org/@example%2Fb": 200,
        }
        self.configs = []
        self.create_status = 200
        self.list_status = 200
        self.sent = []
        self.ran = []

    def fetch(self, url):
        if url not in self.public:
            raise AssertionError(f"setup asked for {url}, which no test recorded")
        return self.public[url], b"{}"

    def send(self, method, url, token, body=None):
        self.sent.append((method, url, token, body))
        if method == "GET" and url == LIST:
            if self.list_status != 200:
                return self.list_status, json.dumps(
                    {"errors": [{"detail": "this token cannot do that"}]}
                ).encode()
            return 200, json.dumps(
                {
                    "github_configs": self.configs,
                    "meta": {"total": len(self.configs), "next_page": None},
                }
            ).encode()
        if method == "POST" and url == CREATE:
            if self.create_status != 200:
                return self.create_status, json.dumps(
                    {"errors": [{"detail": "crates.io said no"}]}
                ).encode()
            return 200, json.dumps(
                {"github_config": dict(body["github_config"], id=1)}
            ).encode()
        raise AssertionError(f"setup sent {method} {url}, which no test expects")

    def run_npm(self, command, env):
        with open(env["NPM_TP_PACKAGES"], encoding="utf-8") as handle:
            self.ran.append((command, handle.read()))
        return 0


class SetupTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(dir=os.environ.get("TEST_TMPDIR"))
        self.addCleanup(self._tmp.cleanup)
        self.root = fixture_repo.make(os.path.join(self._tmp.name, "repo"))
        self.home = os.path.join(self._tmp.name, "home")
        os.makedirs(os.path.join(self.home, ".cargo"))
        self.world = World()
        self.env = {"HOME": self.home, "CARGO_REGISTRY_TOKEN": TOKEN}

    def run_setup(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        code = setup.main(
            list(argv),
            root=self.root,
            env=self.env,
            fetch=self.world.fetch,
            send=self.world.send,
            run_npm=self.world.run_npm,
            out=out,
            err=err,
        )
        self.assertNotIn(TOKEN, out.getvalue() + err.getvalue())
        return code, out.getvalue(), err.getvalue()

    def posts(self):
        return [s for s in self.world.sent if s[0] == "POST"]

    # --- crates.io -----------------------------------------------------------

    def test_a_missing_config_is_created_from_what_the_code_says(self):
        code, out, _ = self.run_setup("--only", "crates")
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.posts()), 1)
        method, url, token, body = self.posts()[0]
        self.assertEqual((url, token), (CREATE, TOKEN))
        self.assertEqual(body, {"github_config": WANTED})
        self.assertIn(
            "+ example-kit -> Example/sdk-mirror release.yml environment crates-io", out
        )

    def test_a_config_that_is_there_is_left_alone(self):
        self.world.configs = [dict(WANTED, id=7, repository_owner="example")]
        code, out, _ = self.run_setup("--only", "crates")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.posts(), [])
        self.assertIn("ok example-kit (already configured)", out)

    def test_a_config_for_another_workflow_does_not_count_as_there(self):
        self.world.configs = [dict(WANTED, id=7, workflow_filename="other.yml")]
        code, out, _ = self.run_setup("--only", "crates")
        self.assertEqual(len(self.posts()), 1)
        self.assertIn("other.yml", out)

    def test_a_config_for_another_environment_does_not_count_as_there(self):
        self.world.configs = [dict(WANTED, id=7, environment=None)]
        self.run_setup("--only", "crates")
        self.assertEqual(len(self.posts()), 1)

    def test_dry_run_changes_nothing_and_needs_no_token(self):
        self.env = {"HOME": self.home}
        code, out, _ = self.run_setup("--dry-run", "--only", "crates")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.world.sent, [])
        self.assertIn(
            "DRY_RUN example-kit -> Example/sdk-mirror release.yml environment crates-io",
            out,
        )

    def test_a_crate_that_is_not_published_yet_is_said_and_not_attempted(self):
        self.world.public["https://crates.io/api/v1/crates/example-kit"] = 404
        code, out, _ = self.run_setup("--only", "crates")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.world.sent, [])
        self.assertIn("example-kit is not on crates.io yet", out)
        self.assertIn("1 not yet on the registry", out)

    def test_the_token_is_read_from_cargo_s_credentials_file(self):
        self.env = {"HOME": self.home}
        with open(os.path.join(self.home, ".cargo", "credentials.toml"), "w") as handle:
            handle.write(f'[registry]\ntoken = "{TOKEN}"\n')
        code, out, _ = self.run_setup("--only", "crates")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.posts()[0][2], TOKEN)

    def test_cargo_home_moves_the_credentials_file(self):
        elsewhere = os.path.join(self._tmp.name, "elsewhere")
        os.makedirs(elsewhere)
        with open(os.path.join(elsewhere, "credentials.toml"), "w") as handle:
            handle.write(f'[registry]\ntoken = "{TOKEN}"\n')
        self.env = {"HOME": self.home, "CARGO_HOME": elsewhere}
        code, _, _ = self.run_setup("--only", "crates")
        self.assertEqual(code, 0)

    def test_a_broken_credentials_file_is_a_setup_error_that_shows_none_of_it(self):
        self.env = {"HOME": self.home}
        with open(os.path.join(self.home, ".cargo", "credentials.toml"), "w") as handle:
            handle.write(f'[registry]\ntoken = "{TOKEN}\n')
        code, _, err = self.run_setup("--only", "crates")
        self.assertEqual(code, 2)
        self.assertIn("credentials.toml", err)

    def test_no_token_is_a_setup_error_before_anything_is_sent(self):
        self.env = {"HOME": self.home}
        code, _, err = self.run_setup("--only", "crates")
        self.assertEqual(code, 2)
        self.assertEqual(self.world.sent, [])
        self.assertIn("cargo login", err)

    def test_a_refusal_is_a_failure_that_says_what_the_registry_said(self):
        self.world.create_status = 403
        code, _, err = self.run_setup("--only", "crates")
        self.assertEqual(code, 1)
        self.assertIn("example-kit", err)
        self.assertIn("HTTP 403", err)
        self.assertIn("crates.io said no", err)

    def test_a_list_that_cannot_be_read_is_a_failure_and_nothing_is_created(self):
        self.world.list_status = 403
        code, _, err = self.run_setup("--only", "crates")
        self.assertEqual(code, 1)
        self.assertEqual(self.posts(), [])
        self.assertIn("this token cannot do that", err)

    def test_a_token_goes_to_crates_io_and_nowhere_else(self):
        request = setup.crates_request("GET", LIST, TOKEN)
        self.assertEqual(request.get_header("Authorization"), TOKEN)
        self.assertIn("registry-trust", request.get_header("User-agent"))
        with self.assertRaises(ValueError):
            setup.crates_request("GET", "https://crates.io.example.com/api/v1/x", TOKEN)
        with self.assertRaises(ValueError):
            setup.crates_request("GET", "http://crates.io/api/v1/x", TOKEN)

    # --- PyPI ----------------------------------------------------------------

    def test_pypi_prints_the_values_to_enter_and_says_it_is_by_hand(self):
        code, out, _ = self.run_setup("--only", "pypi")
        self.assertEqual(code, 0, out)
        self.assertIn("PyPI has no API for trusted publishers", out)
        self.assertIn(
            "https://pypi.org/manage/project/example-kit/settings/publishing/", out
        )
        for line in (
            "Owner: Example",
            "Repository name: sdk-mirror",
            "Workflow name: release.yml",
            "Environment name: pypi",
        ):
            self.assertIn(line, out)
        self.assertIn("1 to enter by hand", out)
        self.assertEqual(self.world.sent, [])

    def test_a_pypi_project_that_does_not_exist_gets_a_pending_publisher(self):
        self.world.public["https://pypi.org/pypi/example-kit/json"] = 404
        code, out, _ = self.run_setup("--only", "pypi")
        self.assertIn("https://pypi.org/manage/account/publishing/", out)
        self.assertIn("PyPI Project Name: example-kit", out)

    # --- npm -----------------------------------------------------------------

    def test_npm_is_handed_to_the_npm_tool_with_the_derived_packages(self):
        code, out, _ = self.run_setup("--only", "npm")
        self.assertEqual(code, 0, out)
        ((command, listed),) = self.world.ran
        self.assertTrue(
            command[-1].endswith("tools/npm-trusted-publisher/setup.sh"), command
        )
        self.assertEqual(
            listed.split("\n"),
            [
                "packages/lib/ts/packages/a/package.json\tExample/lib-mirror\trelease.yml",
                "packages/lib/ts/packages/b/package.json\tExample/lib-mirror\trelease.yml",
                "packages/sdk/kits/ts/package.json\tExample/sdk-mirror\trelease.yml",
                "",
            ],
        )

    def test_npm_dry_run_runs_nothing_and_says_which_are_not_published(self):
        self.world.public["https://registry.npmjs.org/@example%2Fb"] = 404
        code, out, _ = self.run_setup("--dry-run", "--only", "npm")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.world.ran, [])
        self.assertIn("DRY_RUN @example/a -> Example/lib-mirror release.yml", out)
        self.assertIn("@example/b is not on npm yet", out)

    def test_the_npm_tool_s_failure_is_this_tool_s_failure(self):
        self.world.run_npm = lambda command, env: 1
        code, _, _ = self.run_setup("--only", "npm")
        self.assertEqual(code, 1)

    # --- all of it -----------------------------------------------------------

    def test_with_no_flag_every_registry_is_done(self):
        code, out, _ = self.run_setup("--dry-run")
        self.assertEqual(code, 0, out)
        for heading in ("npm:", "crates.io:", "PyPI:"):
            self.assertIn(heading, out)

    def test_an_unknown_flag_is_a_setup_error(self):
        code, _, err = self.run_setup("--force")
        self.assertEqual(code, 2)
        self.assertIn("--force", err)

    def test_a_broken_inventory_is_a_setup_error(self):
        os.remove(os.path.join(self.root, "packages/sdk/kits/rs/Cargo.toml"))
        code, _, err = self.run_setup("--dry-run")
        self.assertEqual(code, 2)
        self.assertEqual(self.world.sent, [])


if __name__ == "__main__":
    unittest.main()
