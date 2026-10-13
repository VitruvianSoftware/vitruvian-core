#!/usr/bin/env python3
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
"""Tests for release_scope.py. No network: titles, bodies, file lists and
release-please configs come from testdata/ and from literals here.

    python3 tools/release-scope/release_scope_test.py
    bazel test //tools/release-scope:release_scope_test

The replay tests hold the check to 13 October 2026, when three pull requests
for one product each cut a release of another with nothing in it.
"""

import contextlib
import io
import json
import os
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
# The repository's root, in a checkout and in Bazel's runfiles alike.
ROOT = os.path.dirname(os.path.dirname(HERE))
WORKFLOW = ".github/workflows/release-scope.yaml"
sys.path.insert(0, HERE)

import release_scope as rs  # noqa: E402

SDK = "packages/vitruvian-sdk"
TOOL = "apps/desktop/vitruvian-tool-github"
APP = "apps/desktop/vitruvian"


def config(path, component, package_name=None, exclude=None, **more):
    package = {"component": component}
    if package_name:
        package["package-name"] = package_name
    if exclude:
        package["exclude-paths"] = exclude
    package.update(more)
    return {"packages": {path: package}}


# Three products shaped like the real ones: one folder name is the start of
# another's, and one keeps a folder out of its releases.
CONFIGS = {
    f"{SDK}/release-please-config.json": config(
        SDK, "vitruvian-sdk", "vitruvian-sdk", [f"{SDK}/.github", f"{SDK}/consumers"]
    ),
    f"{TOOL}/release-please-config.json": config(TOOL, "vitruvian-tool-github"),
    f"{APP}/release-please-config.json": config(APP, "vitruvian", "vitruvian"),
    "apps/mcp/slack/release-please-config.json": config(
        "apps/mcp/slack", "mcp-slack", "@vitruviansoftware/mcp-slack"
    ),
}
ALIASES = {"desktop": ["vitruvian"]}


def fixture(name):
    with open(os.path.join(HERE, "testdata", name), encoding="utf-8") as handle:
        return json.load(handle)


def before():
    """Every release-please config main had on 13 October 2026."""
    return rs.load_components(fixture("configs-2026-10-13.json"))


def replay(number, components, change=None):
    data = fixture(f"pr-{number}.json")
    files = [change(f) if change else f for f in data["files"]]
    pull = rs.pull_request(data["pull_request"], data["commits"], files)
    return rs.judge(pull, components, rs.load_aliases(read_aliases()))


def read_aliases():
    with open(os.path.join(HERE, "aliases.json"), encoding="utf-8") as handle:
        return json.load(handle)


def judge(title, files, body="", commits=None, **who):
    """A pull request of two commits, so it lands under its title."""
    pull = rs.PullRequest(
        title=title,
        body=body,
        files=files,
        commits=commits if commits is not None else ["wip: one", "wip: two"],
        author=who.get("author", "ipv1337"),
        author_type=who.get("author_type", "User"),
        head_ref=who.get("head_ref", "fix/something"),
    )
    return rs.judge(pull, rs.load_components(CONFIGS), ALIASES)


class WhatItLandsAs(unittest.TestCase):
    """main is squash-merged. GitHub writes the commit; release-please reads it."""

    def pull(self, title, commits, body=""):
        return rs.PullRequest(title, body, [], commits, "ipv1337", "User", "x")

    def test_many_commits_land_under_the_title_with_the_commits_as_bullets(self):
        message = rs.squash_message(
            self.pull("chore(ci): tidy", ["fix(a): one\n\nwhy", "feat(b): two"])
        )
        self.assertEqual(
            message, "chore(ci): tidy\n\n* fix(a): one\n\nwhy\n\n* feat(b): two"
        )

    def test_one_commit_lands_under_that_commits_subject_not_the_title(self):
        # #2987 was titled chore(deps) and landed as fix(gcp-org).
        data = fixture("pr-2987.json")
        pull = rs.pull_request(data["pull_request"], data["commits"], data["files"])
        self.assertTrue(pull.title.startswith("chore(deps): "))
        self.assertTrue(rs.squash_message(pull).startswith("fix(gcp-org): bump moment"))
        verdict = rs.judge(pull, before(), {})
        self.assertIn("foundation-gcp-org", verdict.released)
        self.assertTrue(verdict.one_commit)

    def test_the_description_can_replace_the_message_as_release_please_allows(self):
        body = "text\nBEGIN_COMMIT_OVERRIDE\nchore: nothing a user gets\nEND_COMMIT_OVERRIDE\n"
        self.assertEqual(
            rs.squash_message(self.pull("feat(x): y", ["a", "b"], body)),
            "chore: nothing a user gets",
        )


class WhatReleasePleaseReads(unittest.TestCase):
    def kinds(self, message):
        return [(m.type, m.scope, m.breaking) for m in rs.messages(message)]

    def test_a_subject_has_a_type_a_scope_and_a_breaking_mark(self):
        self.assertEqual(
            self.kinds("feat(vitruvian-sdk): a timer"),
            [("feat", "vitruvian-sdk", False)],
        )
        self.assertEqual(self.kinds("fix: a thing"), [("fix", None, False)])
        self.assertEqual(
            self.kinds("refactor(api)!: drop v1"), [("refactor", "api", True)]
        )

    def test_a_subject_that_is_not_a_conventional_commit_is_nothing(self):
        self.assertEqual(self.kinds("chore(gitops) Update Helm release argo to v2"), [])
        self.assertEqual(self.kinds("Merge branch 'main' into x"), [])

    def test_a_line_in_the_body_that_reads_as_a_commit_is_one(self):
        message = "chore(ci): tidy\n\nwhy\n\nfix(vitruvian-sdk): the thing"
        self.assertEqual(
            self.kinds(message),
            [("chore", "ci", False), ("fix", "vitruvian-sdk", False)],
        )

    def test_so_is_one_that_follows_other_text_with_no_blank_line(self):
        # release-please reads it as a footer, and a footer that parses as a
        # commit is a commit.
        message = "chore(ci): tidy\n\nwhy, and then\nfix(vitruvian-sdk): the thing"
        self.assertEqual(
            self.kinds(message),
            [("chore", "ci", False), ("fix", "vitruvian-sdk", False)],
        )

    def test_a_bullet_from_a_squashed_commit_is_not_one(self):
        self.assertEqual(
            self.kinds("chore: x\n\n* fix(a): one\n\n* feat(b): two"),
            [("chore", None, False)],
        )

    def test_a_breaking_change_footer_marks_the_commit_breaking(self):
        self.assertEqual(
            self.kinds("chore: x\n\nBREAKING CHANGE: the flag is gone"),
            [("chore", None, True)],
        )
        self.assertEqual(
            self.kinds("chore: x\n\nBREAKING-CHANGE: the flag is gone"),
            [("chore", None, True)],
        )

    def test_a_release_as_footer_is_kept(self):
        (message,) = rs.messages("chore: release\n\nRelease-As: 2.0.0")
        self.assertTrue(message.release_as)


class WhichProductsARelease(unittest.TestCase):
    def test_a_fix_releases_the_product_whose_folder_it_changes(self):
        verdict = judge(
            "fix(vitruvian-tool-github): a row's id", [f"{TOOL}/Sources/Row.swift"]
        )
        self.assertEqual(
            verdict.released, {"vitruvian-tool-github": [f"{TOOL}/Sources/Row.swift"]}
        )
        self.assertTrue(verdict.ok)

    def test_a_folder_whose_name_starts_like_another_is_not_that_product(self):
        verdict = judge("fix(vitruvian-tool-github): x", [f"{TOOL}/version_test.py"])
        self.assertNotIn("vitruvian", verdict.released)

    def test_a_type_that_does_not_release_releases_nothing(self):
        for kind in ["chore", "ci", "test", "docs", "refactor", "build", "style"]:
            verdict = judge(
                f"{kind}(ci): x", [f"{SDK}/BUILD", f"{TOOL}/version_test.py"]
            )
            self.assertEqual(verdict.released, {}, kind)
            self.assertTrue(verdict.ok, kind)

    def test_feat_fix_perf_and_revert_release(self):
        for kind in ["feat", "feature", "fix", "perf", "revert"]:
            self.assertIn(
                "vitruvian-sdk",
                judge(f"{kind}(ci): x", [f"{SDK}/BUILD"]).released,
                kind,
            )

    def test_a_breaking_mark_releases_whatever_the_type(self):
        self.assertIn(
            "vitruvian-sdk", judge("chore(ci)!: x", [f"{SDK}/BUILD"]).released
        )

    def test_a_release_as_footer_releases_whatever_the_type(self):
        verdict = judge(
            "x", [f"{SDK}/BUILD"], commits=["chore: release\n\nRelease-As: 2.0.0"]
        )
        self.assertIn("vitruvian-sdk", verdict.released)

    def test_a_commit_only_in_an_excluded_folder_releases_nothing(self):
        verdict = judge(
            "feat(home-speaker): a tool",
            [f"{SDK}/consumers/BUILD", f"{SDK}/.github/workflows/ci.yml"],
        )
        self.assertEqual(verdict.released, {})

    def test_one_file_outside_the_excluded_folders_releases(self):
        files = [f"{SDK}/consumers/BUILD", f"{SDK}/BUILD"]
        self.assertEqual(
            judge("feat(home-speaker): a tool", files).released,
            {"vitruvian-sdk": [f"{SDK}/BUILD"]},
        )

    def test_exclude_paths_names_folders_and_never_a_file(self):
        # release-please's test is file.indexOf(`${path}/`) === 0.
        configs = {"c.json": config(SDK, "vitruvian-sdk", exclude=[f"{SDK}/BUILD"])}
        pull = rs.PullRequest(
            "fix: x", "", [f"{SDK}/BUILD"], ["a", "b"], "u", "User", "x"
        )
        self.assertIn(
            "vitruvian-sdk", rs.judge(pull, rs.load_components(configs), {}).released
        )

    def test_the_configs_changelog_sections_decide_which_types_release(self):
        sections = [
            {"type": "fix", "section": "Fixes", "hidden": True},
            {"type": "docs", "section": "Docs"},
        ]
        configs = {
            "c.json": config(SDK, "vitruvian-sdk", **{"changelog-sections": sections})
        }
        components = rs.load_components(configs)
        fix = rs.PullRequest("fix: x", "", [f"{SDK}/a"], ["a", "b"], "u", "User", "x")
        docs = rs.PullRequest("docs: x", "", [f"{SDK}/a"], ["a", "b"], "u", "User", "x")
        self.assertEqual(rs.judge(fix, components, {}).released, {})
        self.assertIn("vitruvian-sdk", rs.judge(docs, components, {}).released)

    def test_in_one_config_a_file_belongs_to_the_longest_folder_that_holds_it(self):
        configs = {
            "c.json": {
                "packages": {"a": {"component": "outer"}, "a/b": {"component": "inner"}}
            }
        }
        pull = rs.PullRequest("fix: x", "", ["a/b/f"], ["a", "b"], "u", "User", "x")
        self.assertEqual(
            list(rs.judge(pull, rs.load_components(configs), {}).released), ["inner"]
        )

    def test_two_configs_each_judge_the_file_for_themselves(self):
        # tabula-shared is saved from tabula-api's files by exclude-paths alone.
        configs = {
            "1.json": config("a", "outer"),
            "2.json": config("a/b", "inner"),
        }
        pull = rs.PullRequest("fix: x", "", ["a/b/f"], ["a", "b"], "u", "User", "x")
        self.assertEqual(
            sorted(rs.judge(pull, rs.load_components(configs), {}).released),
            ["inner", "outer"],
        )

    def test_a_package_at_the_root_takes_every_file(self):
        configs = {"c.json": {"packages": {".": {"component": "everything"}}}}
        pull = rs.PullRequest("fix: x", "", ["README.md"], ["a", "b"], "u", "User", "x")
        self.assertIn(
            "everything", rs.judge(pull, rs.load_components(configs), {}).released
        )


class WhatTheTitleNames(unittest.TestCase):
    def test_the_scope_is_the_component(self):
        self.assertTrue(judge("feat(vitruvian-sdk): x", [f"{SDK}/a"]).ok)

    def test_the_scope_is_the_package_name(self):
        self.assertTrue(
            judge("fix(@vitruviansoftware/mcp-slack): x", ["apps/mcp/slack/a"]).ok
        )

    def test_the_scope_is_an_alias_from_the_tracked_file(self):
        self.assertTrue(judge("feat(desktop): x", [f"{APP}/a"]).ok)

    def test_an_alias_names_only_its_own_product(self):
        verdict = judge("feat(desktop): x", [f"{APP}/a", f"{SDK}/BUILD"])
        self.assertFalse(verdict.ok)
        self.assertEqual(verdict.unnamed, ["vitruvian-sdk"])

    def test_another_products_scope_does_not_name_this_one(self):
        verdict = judge(
            "feat(vitruvian-tool-github): the tool", [f"{TOOL}/a", f"{SDK}/BUILD"]
        )
        self.assertEqual(verdict.unnamed, ["vitruvian-sdk"])
        self.assertEqual(verdict.named, ["vitruvian-tool-github"])

    def test_no_scope_names_nothing(self):
        self.assertEqual(judge("fix: x", [f"{SDK}/a"]).unnamed, ["vitruvian-sdk"])

    def test_a_commit_line_in_the_body_names_its_own_scope(self):
        verdict = judge(
            "x",
            [f"{SDK}/a"],
            commits=["chore(ci): tidy\n\nwhy\n\nfix(vitruvian-sdk): the thing"],
        )
        self.assertEqual(verdict.released, {"vitruvian-sdk": [f"{SDK}/a"]})
        self.assertTrue(verdict.ok)

    def test_an_alias_to_a_product_no_config_has_is_refused(self):
        with self.assertRaises(rs.Misconfigured):
            pull = rs.PullRequest("fix: x", "", [], ["a", "b"], "u", "User", "x")
            rs.judge(
                pull, rs.load_components(CONFIGS), {"desktop": ["no-such-product"]}
            )


class SayingSoInTheDescription(unittest.TestCase):
    FILES = [f"{TOOL}/a", f"{SDK}/Sources/a.swift"]

    def test_a_releases_line_names_the_other_product(self):
        verdict = judge(
            "feat(vitruvian-tool-github): x",
            self.FILES,
            body="Why.\n\nReleases: vitruvian-sdk\n",
        )
        self.assertTrue(verdict.ok)
        self.assertEqual(verdict.named, ["vitruvian-sdk", "vitruvian-tool-github"])

    def test_it_may_name_several_and_be_written_as_code(self):
        body = "Releases: `vitruvian-sdk`, vitruvian-tool-github\r\n"
        self.assertTrue(judge("fix(ci): x", self.FILES, body=body).ok)

    def test_it_must_start_its_line(self):
        self.assertFalse(
            judge(
                "fix(ci): x",
                self.FILES,
                body="This Releases: vitruvian-sdk, vitruvian-tool-github",
            ).ok
        )

    def test_naming_one_of_two_is_not_enough(self):
        verdict = judge("fix(ci): x", self.FILES, body="Releases: vitruvian-sdk")
        self.assertEqual(verdict.unnamed, ["vitruvian-tool-github"])

    def test_a_name_no_config_has_fails_and_is_reported(self):
        verdict = judge(
            "feat(vitruvian-tool-github): x",
            [f"{TOOL}/a"],
            body="Releases: vitruvian-skd",
        )
        self.assertFalse(verdict.ok)
        self.assertEqual(verdict.unknown, ["vitruvian-skd"])

    def test_a_name_that_is_not_released_is_noted_and_passes(self):
        verdict = judge("chore(ci): x", self.FILES, body="Releases: vitruvian-sdk")
        self.assertTrue(verdict.ok)
        self.assertEqual(verdict.idle, ["vitruvian-sdk"])


class WhoIsLeftAlone(unittest.TestCase):
    FILES = [f"{SDK}/CHANGELOG.md", f"{TOOL}/a"]

    def test_release_pleases_own_pull_request_by_its_branch(self):
        verdict = judge(
            "fix: x",
            self.FILES,
            head_ref="release-please--branches--main--components--vitruvian-sdk",
        )
        self.assertTrue(verdict.ok)
        self.assertIn("release-please", verdict.exempt)

    def test_a_dependency_bot_by_its_account_and_its_branch(self):
        for login, ref in [
            ("dependabot[bot]", "dependabot/npm/x"),
            ("vitruvian-renovate[bot]", "renovate/argo"),
        ]:
            verdict = judge(
                "fix: x", self.FILES, author=login, author_type="Bot", head_ref=ref
            )
            self.assertTrue(verdict.ok, login)
            self.assertTrue(verdict.exempt, login)

    def test_a_person_on_a_bots_branch_is_not_left_alone(self):
        self.assertFalse(judge("fix: x", self.FILES, head_ref="dependabot/npm/x").ok)

    def test_an_agent_is_a_bot_account_and_is_judged(self):
        # #3193 and #3211 were opened by vitruvian-wren-agent[bot].
        verdict = judge(
            "fix: x", self.FILES, author="vitruvian-wren-agent[bot]", author_type="Bot"
        )
        self.assertFalse(verdict.ok)


class TheThirteenthOfOctober(unittest.TestCase):
    """The day's pull requests, against the configs main had that day."""

    def test_3193_the_github_tool_would_release_the_sdk(self):
        verdict = replay(3193, before())
        self.assertFalse(verdict.ok)
        self.assertEqual(verdict.unnamed, ["vitruvian-sdk"])
        self.assertEqual(verdict.released["vitruvian-sdk"], [f"{SDK}/BUILD"])
        self.assertIn("vitruvian-tool-github", verdict.named)

    def test_3211_the_homespeaker_tool_would_release_the_sdk(self):
        verdict = replay(3211, before())
        self.assertFalse(verdict.ok)
        self.assertEqual(verdict.unnamed, ["vitruvian-sdk"])
        self.assertEqual(verdict.released["vitruvian-sdk"], [f"{SDK}/BUILD"])

    def test_3217_a_ci_fix_would_release_the_github_tool(self):
        verdict = replay(3217, before())
        self.assertFalse(verdict.ok)
        self.assertIn("vitruvian-tool-github", verdict.unnamed)
        self.assertEqual(
            verdict.released["vitruvian-tool-github"], [f"{TOOL}/version_test.py"]
        )

    def test_3210_the_nexus_agent_tool_would_release_the_app_and_the_sdk(self):
        # Merged the same evening, before this check was on main. The SDK's
        # release is a real one here (the kit changed); the app's is not.
        verdict = replay(3210, before())
        self.assertFalse(verdict.ok)
        self.assertEqual(verdict.named, ["nexus-agent"])
        self.assertEqual(verdict.unnamed, ["vitruvian", "vitruvian-sdk"])
        self.assertEqual(verdict.released["vitruvian"], [f"{APP}/UPSTREAM.md"])
        self.assertIn(
            f"{SDK}/Sources/VitruvianToolKit/Tool.swift",
            verdict.released["vitruvian-sdk"],
        )

    def test_3209_a_fix_to_the_github_tool_alone_passes(self):
        verdict = replay(3209, before())
        self.assertTrue(verdict.ok)
        self.assertEqual(list(verdict.released), ["vitruvian-tool-github"])

    def test_3191_a_feature_of_the_sdk_passes(self):
        verdict = replay(3191, before())
        self.assertTrue(verdict.ok)
        self.assertIn("vitruvian-sdk", verdict.released)

    def test_3199_release_pleases_own_pull_request_is_left_alone(self):
        self.assertTrue(replay(3199, before()).exempt)

    def test_3163_dependabot_is_left_alone(self):
        self.assertTrue(replay(3163, before()).exempt)

    def test_with_the_consumers_folder_3193_and_3211_touch_no_sdk_release(self):
        # The same pull requests, letting the tool in where it is done now,
        # against the SDK's config as it is in this checkout.
        with open(
            os.path.join(ROOT, SDK, "release-please-config.json"), encoding="utf-8"
        ) as handle:
            live = {f"{SDK}/release-please-config.json": json.load(handle)}
        configs = dict(fixture("configs-2026-10-13.json"), **live)
        moved = lambda f: f"{SDK}/consumers/BUILD" if f == f"{SDK}/BUILD" else f  # noqa: E731
        for number in [3193, 3211]:
            verdict = replay(number, rs.load_components(configs), moved)
            self.assertNotIn("vitruvian-sdk", verdict.released, number)
            self.assertTrue(verdict.ok, number)


class WhatItSays(unittest.TestCase):
    def test_a_failure_says_which_product_which_files_and_the_three_ways_out(self):
        text = rs.report(replay(3217, before()))
        for part in [
            "vitruvian-tool-github",
            f"{TOOL}/version_test.py",
            "fix(ci): the HomeSpeaker tool's manifest",
            "Split",
            "chore",
            "Releases: home-speaker, vitruvian-tool-github",
        ]:
            self.assertIn(part, text)

    def test_one_commit_is_told_to_change_the_commit_not_the_title(self):
        self.assertIn("one commit", rs.report(replay(3217, before())))
        self.assertNotIn("one commit", rs.report(replay(3193, before())))

    def test_a_pass_says_what_it_releases(self):
        self.assertIn("vitruvian-tool-github", rs.report(replay(3209, before())))


class TheCommand(unittest.TestCase):
    def run_it(self, number, root):
        data = fixture(f"pr-{number}.json")
        with tempfile.TemporaryDirectory() as tmp:
            paths = {}
            for name, value in [
                ("pr", data["pull_request"]),
                ("commits", data["commits"]),
            ]:
                paths[name] = os.path.join(tmp, name + ".json")
                with open(paths[name], "w", encoding="utf-8") as handle:
                    json.dump(value, handle)
            paths["files"] = os.path.join(tmp, "files.txt")
            with open(paths["files"], "w", encoding="utf-8") as handle:
                handle.write("\n".join(data["files"]) + "\n")
            out = io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
                code = rs.main(
                    [
                        "--pr-json",
                        paths["pr"],
                        "--commits-json",
                        paths["commits"],
                        "--files",
                        paths["files"],
                        "--repo-root",
                        root,
                        "--aliases",
                        os.path.join(HERE, "aliases.json"),
                    ]
                )
            return code, out.getvalue()

    def tree(self, tmp, configs):
        for path, value in configs.items():
            os.makedirs(os.path.join(tmp, os.path.dirname(path)), exist_ok=True)
            with open(os.path.join(tmp, path), "w", encoding="utf-8") as handle:
                json.dump(value, handle)
        return tmp

    def test_it_finds_the_configs_in_the_tree_and_exits_1_on_a_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.tree(tmp, fixture("configs-2026-10-13.json"))
            code, text = self.run_it(3217, root)
            self.assertEqual(code, 1)
            self.assertIn("vitruvian-tool-github", text)
            self.assertEqual(self.run_it(3209, root)[0], 0)

    def test_a_tree_with_no_config_is_an_error_not_a_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.run_it(3209, tmp)[0], 2)

    def test_a_config_that_does_not_parse_is_an_error_not_a_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "a"))
            with open(
                os.path.join(tmp, "a", "release-please-config.json"), "w"
            ) as handle:
                handle.write("{")
            self.assertEqual(self.run_it(3209, tmp)[0], 2)


class TheWorkflow(unittest.TestCase):
    """The parts of release-scope.yaml the check is no use without."""

    def setUp(self):
        with open(os.path.join(ROOT, WORKFLOW), encoding="utf-8") as handle:
            self.lines = [
                line.rstrip() for line in handle if not line.lstrip().startswith("#")
            ]
        start = self.lines.index("on:")
        end = next(
            i
            for i in range(start + 1, len(self.lines))
            if re.match(r"\S", self.lines[i])
        )
        self.on = self.lines[start + 1 : end]

    def test_it_runs_again_when_the_title_or_description_is_edited(self):
        # Retitling and adding a Releases line are how a failure is fixed, and
        # neither pushes a commit.
        types = next(line for line in self.on if line.strip().startswith("types:"))
        named = re.findall(r"[a-z_]+", types.split(":", 1)[1])
        for kind in ["opened", "reopened", "synchronize", "edited"]:
            self.assertIn(kind, named)

    def test_it_reports_on_every_pull_request_and_every_queue_entry(self):
        # It is a required check: where it does not run, nothing can merge.
        self.assertIn("  merge_group:", self.on)
        self.assertIn("  pull_request:", self.on)
        for line in self.on:
            self.assertNotRegex(
                line, r"^\s*(paths|paths-ignore|branches|branches-ignore):"
            )
        self.assertIn("  release-scope:", self.lines)

    def test_the_title_and_description_never_reach_a_command_line(self):
        text = "\n".join(self.lines)
        self.assertNotRegex(text, r"\$\{\{\s*github\.event\.pull_request\.(title|body)")
        self.assertNotRegex(
            text, r"\$\{\{\s*github\.(head_ref|event\.pull_request\.head\.ref)"
        )


if __name__ == "__main__":
    unittest.main()
