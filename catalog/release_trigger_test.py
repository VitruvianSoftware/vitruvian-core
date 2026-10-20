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

"""A tool's release starts its catalog update.

catalog-bump starts when a release workflow named in its workflow_run list
finishes. That list has to match catalog/sources.json: a tool released from
this repository whose workflow is missing from it would wait for the hourly
run, which GitHub often drops. These tests read the live files, with no
network."""

import copy
import json
import unittest
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
WORKFLOWS = ROOT / ".github" / "workflows"
THIS_REPO = "VitruvianSoftware/vitruvian-core"


def push_trigger_problem(workflow):
    """Why `workflow` would not start when a change to the catalog merges,
    or None. A merged bump changes catalog/tools.json, and that is when its
    sibling bump pull requests stop merging and need rebuilding."""
    push = workflow["on"].get("push")
    if push is None:
        return "catalog-bump has no push trigger"
    if push.get("branches") != ["main"]:
        return f"its push trigger must be for main only, not {push.get('branches')}"
    if push.get("paths") != ["catalog/tools.json"]:
        return (
            "its push trigger must be filtered to catalog/tools.json alone, "
            f"not {push.get('paths')}: catalog-publish's own merges write only the "
            "website's copy, and any wider filter could start runs for nothing"
        )
    return None


def load_workflow(path):
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    # YAML 1.1 reads the key `on` as true.
    data["on"] = data.pop(True, data.get("on"))
    return data


class ReleaseTriggerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = json.loads((HERE / "sources.json").read_text(encoding="utf-8"))[
            "sources"
        ]
        cls.bump = load_workflow(WORKFLOWS / "catalog-bump.yaml")
        cls.by_name = {}
        for path in sorted(WORKFLOWS.glob("*.y*ml")):
            name = load_workflow(path).get("name")
            if name:
                cls.by_name.setdefault(name, []).append(path)

    def trigger(self):
        return self.bump["on"].get("workflow_run") or {}

    def test_every_tool_released_here_names_its_release_workflow(self):
        for row in self.rows:
            if row["repo"] == THIS_REPO:
                self.assertTrue(
                    row.get("releaseWorkflow"),
                    f"{row['id']} is released from this repository but its row in "
                    "catalog/sources.json has no releaseWorkflow, so its release "
                    "would wait for the hourly run: name the workflow that uploads "
                    "its zip, and add it to catalog-bump's workflow_run list",
                )

    def test_a_tool_released_elsewhere_names_none(self):
        """A run in another repository cannot start a workflow here."""
        for row in self.rows:
            if row["repo"] != THIS_REPO:
                self.assertNotIn(
                    "releaseWorkflow",
                    row,
                    f"{row['id']} is released from {row['repo']}: no workflow "
                    "there can start catalog-bump here; the hourly run covers it",
                )

    def test_catalog_bump_starts_when_each_of_them_finishes(self):
        named = {r["releaseWorkflow"] for r in self.rows if r.get("releaseWorkflow")}
        trigger = self.trigger()
        self.assertEqual(
            set(trigger.get("workflows", [])),
            named,
            "catalog-bump's workflow_run list must be exactly the releaseWorkflow "
            "column of catalog/sources.json",
        )
        self.assertEqual(trigger.get("types"), ["completed"])
        self.assertEqual(trigger.get("branches"), ["main"])

    def test_each_named_workflow_is_one_workflow_here(self):
        """workflow_run matches by the `name:` line, not the file name."""
        for row in self.rows:
            name = row.get("releaseWorkflow")
            if name:
                self.assertEqual(
                    len(self.by_name.get(name, [])),
                    1,
                    f"{row['id']}: exactly one workflow in .github/workflows must "
                    f"be named {name!r}; found {self.by_name.get(name, [])}",
                )

    def test_each_named_workflow_uploads_and_checks_the_zip(self):
        """The run that wakes catalog-bump is the one that attached the zip:
        it names the zip, as its check that the release holds it does."""
        for row in self.rows:
            name = row.get("releaseWorkflow")
            if not name or len(self.by_name.get(name, [])) != 1:
                continue
            text = self.by_name[name][0].read_text(encoding="utf-8")
            zip_name = row["asset"].replace("{version}", "${version}")
            self.assertIn(
                zip_name,
                text,
                f"{name} does not name {zip_name}: is it the workflow that "
                f"uploads {row['id']}'s zip?",
            )

    def test_the_hourly_backup_stays(self):
        """GitHub drops scheduled runs, but the GitHub tool has no other way
        in, and a release whose trigger was missed is caught next hour."""
        crons = [s.get("cron") for s in self.bump["on"].get("schedule") or []]
        self.assertEqual(crons, ["17 * * * *"], "catalog-bump lost its hourly schedule")

    def test_every_run_shares_one_lane(self):
        """Two runs at once could open the same pull request twice."""
        concurrency = self.bump.get("concurrency") or {}
        self.assertEqual(
            concurrency.get("group"),
            "catalog-bump",
            "every catalog-bump run, whatever started it, must share one fixed "
            "concurrency group",
        )
        self.assertIs(concurrency.get("cancel-in-progress"), False)

    def test_a_catalog_change_on_main_starts_it(self):
        """A merged bump changes the catalog, and the other open bump pull
        requests can stop merging. On 2026-10-19 one sat broken for about
        three hours, waiting for an hourly run GitHub kept dropping."""
        self.assertIsNone(push_trigger_problem(self.bump))

    def test_the_push_check_bites(self):
        """push_trigger_problem fails a workflow without the trigger, or with
        the trigger but no path filter, or with a different one."""
        gone = copy.deepcopy(self.bump)
        gone["on"].pop("push", None)
        self.assertIsNotNone(push_trigger_problem(gone))
        unfiltered = copy.deepcopy(self.bump)
        unfiltered["on"].setdefault("push", {"branches": ["main"]}).pop("paths", None)
        self.assertIsNotNone(push_trigger_problem(unfiltered))
        wider = copy.deepcopy(self.bump)
        wider["on"]["push"] = {"branches": ["main"], "paths": ["catalog/**"]}
        self.assertIsNotNone(push_trigger_problem(wider))
        branchless = copy.deepcopy(self.bump)
        branchless["on"]["push"] = {"paths": ["catalog/tools.json"]}
        self.assertIsNotNone(push_trigger_problem(branchless))

    def test_the_trigger_list_is_exact(self):
        """The ways in are these four, and no other: a new one needs its own
        thought about the lane and the cost."""
        self.assertEqual(
            set(self.bump["on"]),
            {"workflow_run", "push", "schedule", "workflow_dispatch"},
        )

    def test_no_run_is_empty(self):
        """GitHub keeps one waiting run per group and cancels it when another
        arrives. That loses nothing only if every run checks every tool: a plan
        job skipped by an `if:` would be an empty run that can push out a
        waiting one with work to do."""
        self.assertNotIn("if", self.bump["jobs"]["plan"])


if __name__ == "__main__":
    unittest.main()
