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
# SOFTWARE.

"""Tests for upstream.py, against throwaway upstream and monorepo repositories.

bazel test //apps/web/gods-eye-view:upstream_test
"""

import contextlib
import importlib.util
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "upstream", Path(__file__).with_name("upstream.py")
)
upstream = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(upstream)

APP = upstream.APP_DIR
MIT = (
    "Copyright (c) 2026 VitruvianSoftware\n"
    "\n"
    "Permission is hereby granted, free of charge, to any person obtaining a copy\n"
    "of this software ...\n"
    "\n"
    'THE SOFTWARE IS PROVIDED "AS IS", ... DEALINGS IN THE\n'
    "SOFTWARE.\n"
)


def js_header():
    return (
        "/**\n"
        + "".join(f" * {line}".rstrip() + "\n" for line in MIT.splitlines())
        + " */\n\n"
    )


def hash_header():
    return "".join(f"# {line}".rstrip() + "\n" for line in MIT.splitlines()) + "\n"


def html_header():
    return (
        "<!--\n"
        + "".join(f" {line}".rstrip() + "\n" for line in MIT.splitlines())
        + "-->\n\n"
    )


BODY = "".join(f"export const line{n} = {n};\n" for n in range(12))
CAMERA = BODY + "export const HOME = 'Austin';\n" + BODY.replace("line", "tail")
CAMERA_HERE = CAMERA.replace("'Austin'", "'Irvine'")


def run(cwd, *args):
    return subprocess.run(
        ["git", *args], cwd=cwd, check=True, capture_output=True, text=True
    ).stdout.strip()


def write(root, rel, text, executable=False):
    path = Path(root) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if executable:
        path.chmod(0o755)


def commit(root, message):
    run(root, "add", "-A")
    run(root, "commit", "-q", "-m", message)
    return run(root, "rev-parse", "HEAD")


def init(root):
    Path(root).mkdir(parents=True, exist_ok=True)
    run(root, "init", "-q", "-b", "main")
    run(root, "config", "user.email", "t@example.com")
    run(root, "config", "user.name", "t")


CHANGES = """# test list
# base\t{base}\ttree\t{tree}
# path\tchange\twhy
src/camera.js\tmodified\tlands on Irvine
package-lock.json\tdeleted\tpnpm workspace
server.mjs\tadded\tproduction server
tests/e2e/\tadded\tlocal suite
upstream/\tadded\tthis tracking
"""


class Fixture:
    """An upstream at base A, and a monorepo whose copy is A plus headers and listed changes."""

    def __init__(self, tmp):
        self.tmp = Path(tmp)
        self.up = self.tmp / "upstream"
        self.mono = self.tmp / "mono"
        self.cache = self.tmp / "cache"
        init(self.up)
        write(self.up, "src/main.js", BODY)
        write(self.up, "src/camera.js", CAMERA)
        write(self.up, "src/old.js", BODY)
        write(self.up, "index.html", "<!doctype html>\n<html></html>\n")
        write(
            self.up,
            "scripts/dev.sh",
            "#!/usr/bin/env bash\necho dev\n",
            executable=True,
        )
        write(self.up, "package-lock.json", "{}\n")
        write(self.up, "logo.png", "\0PNG binary\n")
        write(self.up, "server/routes.js", BODY)
        self.base = commit(self.up, "A")
        self.base_tree = run(self.up, "rev-parse", "HEAD^{tree}")

        init(self.mono)
        app = self.mono / APP
        write(app, "src/main.js", js_header() + BODY)
        write(app, "src/camera.js", js_header() + CAMERA_HERE)
        write(app, "src/old.js", js_header() + BODY)
        write(
            app, "index.html", "<!doctype html>\n" + html_header() + "<html></html>\n"
        )
        write(
            app,
            "scripts/dev.sh",
            "#!/usr/bin/env bash\n" + hash_header() + "echo dev\n",
            executable=True,
        )
        write(app, "logo.png", "\0PNG binary\n")
        write(app, "server/routes.js", js_header() + BODY)
        write(app, "server.mjs", js_header() + "serve();\n")
        write(app, "tests/e2e/run.sh", "echo e2e\n")
        write(
            app,
            "upstream/local-changes.tsv",
            CHANGES.format(base=self.base, tree=self.base_tree),
        )
        commit(self.mono, "import")

    @property
    def changes_path(self):
        return self.mono / APP / "upstream/local-changes.tsv"

    def tool(self, *args, fetch=True):
        argv = [
            "--root",
            str(self.mono),
            "--cache",
            str(self.cache),
            "--upstream-url",
            str(self.up),
        ]
        if not fetch:
            argv.append("--no-fetch")
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = upstream.main(argv + list(args))
        return code, stdout.getvalue(), stderr.getvalue()

    def read(self, rel):
        return (self.mono / APP / rel).read_text()


class HeaderTest(unittest.TestCase):
    def test_round_trips_each_comment_style(self):
        cases = [
            ("", js_header(), "import x;\n"),
            ("#!/usr/bin/env node\n", js_header(), "run();\n"),
            ("", hash_header(), "set -e\n"),
            ("#!/usr/bin/env bash\n", hash_header(), "set -e\n"),
            ("<!doctype html>\n", html_header(), "<html></html>\n"),
        ]
        for prefix, header, rest in cases:
            data = (prefix + header + rest).encode()
            body, got, line = upstream.split_header(data)
            self.assertEqual(body, (prefix + rest).encode())
            self.assertEqual(got, header.encode())
            self.assertEqual(upstream.join_header(body, got, line), data)

    def test_a_file_without_the_header_is_unchanged(self):
        data = b"// Copyright 2024 Someone Else\nlet x;\n"
        self.assertEqual(upstream.split_header(data), (data, b"", 0))

    def test_a_copyright_line_without_the_mit_text_is_not_a_header(self):
        data = b"# Copyright (c) 2026 VitruvianSoftware\n# SPDX-License-Identifier: MIT\n\necho\n"
        self.assertEqual(upstream.split_header(data)[1], b"")


class ChangesTest(unittest.TestCase):
    def load(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "list.tsv"
            path.write_text(text)
            return upstream.Changes.load(path)

    def test_errors(self):
        base = "a" * 40
        changes = self.load(
            f"# base\t{base}\ttree\t{'b' * 40}\n"
            "src/a.js\tmodified\twhy\n"
            "src/a.js\tadded\tagain\n"
            "src/b.js\trenamed\twhy\n"
            "dir/\tmodified\twhy\n"
            "../c.js\tadded\twhy\n"
            "d.js\tdeleted\t-\n"
        )
        errs = "\n".join(changes.errors())
        self.assertIn("duplicate of line 2", errs)
        self.assertIn("'renamed' is not one of", errs)
        self.assertIn("only an `added` row may name a directory", errs)
        self.assertIn("not relative", errs)
        self.assertIn("say why", errs)

    def test_needs_a_base_line(self):
        with self.assertRaises(upstream.ToolError):
            self.load("src/a.js\tmodified\twhy\n")

    def test_the_committed_list_is_valid(self):
        path = Path(
            os.environ.get("UPSTREAM_LOCAL_CHANGES")
            or Path(__file__).with_name("local-changes.tsv")
        )
        changes = upstream.Changes.load(path)
        self.assertEqual(changes.errors(), [])
        self.assertTrue(
            changes.row_for("upstream/upstream.py"), "the list must cover upstream/"
        )


class ToolTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.f = Fixture(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def test_check_passes_on_the_base_plus_the_listed_changes(self):
        code, out, err = self.f.tool("check")
        self.assertEqual(code, 0, err)
        self.assertIn("ok: this copy is upstream", out)

    def test_check_fails_on_an_unlisted_change(self):
        write(self.f.mono / APP, "src/main.js", js_header() + BODY + "tweak();\n")
        code, _, err = self.f.tool("check")
        self.assertEqual(code, 1)
        self.assertIn(
            "src/main.js: modified here, but local-changes.tsv does not list it", err
        )

    def test_check_fails_on_a_lost_executable_bit(self):
        (self.f.mono / APP / "scripts/dev.sh").chmod(0o644)
        code, _, err = self.f.tool("check")
        self.assertEqual(code, 1)
        self.assertIn("scripts/dev.sh: modified here", err)

    def test_check_fails_on_an_unlisted_file(self):
        write(self.f.mono / APP, "extra.js", "x\n")
        code, _, err = self.f.tool("check")
        self.assertEqual(code, 1)
        self.assertIn("extra.js: added here", err)

    def test_check_fails_on_a_stale_or_wrong_row(self):
        with self.f.changes_path.open("a") as fh:
            fh.write("src/main.js\tmodified\tno longer true\n")
            fh.write("tests/e2e/run.sh\tmodified\twrong kind\n")
        code, _, err = self.f.tool("check")
        self.assertEqual(code, 1)
        self.assertIn(
            "(src/main.js): listed as modified, but matches upstream; remove the row",
            err,
        )
        self.assertIn(
            "tests/e2e/run.sh: listed as modified on line 10, but is added", err
        )

    def test_status_counts_what_landed_since_the_base(self):
        write(self.f.up, "src/main.js", BODY + "more();\n")
        commit(self.f.up, "B")
        run(self.f.up, "checkout", "-q", "-b", "feature")
        write(self.f.up, "src/new.js", "new\n")
        commit(self.f.up, "C")
        run(self.f.up, "checkout", "-q", "main")
        run(
            self.f.up,
            "merge",
            "-q",
            "--no-ff",
            "-m",
            "Merge pull request #2",
            "feature",
        )
        code, out, err = self.f.tool("status", "--check")
        self.assertEqual(code, 1, err)
        self.assertIn("3 commit(s) behind, 2 on the first-parent line", out)
        self.assertIn("Merge pull request #2", out)

    def test_status_markdown_counts_only_new_commits(self):
        write(self.f.up, "src/main.js", BODY + "more();\n")
        b = commit(self.f.up, "B")
        previous = self.f.tmp / "previous.md"
        previous.write_text(f"<!-- behind-shas: {b[:12]} -->\n")
        write(self.f.up, "src/main.js", BODY + "more();\nand_more();\n")
        commit(self.f.up, "C")
        code, out, _ = self.f.tool(
            "status", "--markdown", "--previous-body", str(previous)
        )
        self.assertEqual(code, 0)
        self.assertEqual(
            out.splitlines()[0], "<!-- upstream-watch behind: 2 drift: 0 new: 1 -->"
        )

    def test_status_follows_an_upstream_history_rewrite(self):
        self.f.tool("status")  # caches the clone
        run(self.f.up, "commit", "-q", "--amend", "-m", "A, reworded")
        code, out, err = self.f.tool("status")
        self.assertEqual(code, 0, err)
        self.assertIn("re-anchored by tree", out)

    def upstream_moves(self):
        up = self.f.up
        write(up, "src/main.js", BODY + "more();\n")  # unchanged here: taken
        write(up, "src/camera.js", CAMERA.replace("tail8", "tail8_renamed"))  # merged
        (up / "src/old.js").unlink()  # unchanged here: deleted
        write(up, "src/fresh.js", "fresh();\n")  # added
        write(up, "package-lock.json", '{"v": 2}\n')  # dropped here
        write(
            up, "index.html", "<!doctype html>\n<html lang=en></html>\n"
        )  # header after doctype
        (up / "scripts/dev.sh").chmod(0o644)  # mode change
        write(up, "server/routes.js", BODY + "route();\n")  # dev-server wiring
        write(up, "server/providers/flights.js", "flights();\n")  # production runs it
        write(up, "maps/tiles.js", "tiles();\n")  # new top-level directory
        return commit(up, "B")

    def test_sync_merges_upstream_into_this_copy(self):
        target = self.upstream_moves()
        code, out, err = self.f.tool("sync")
        self.assertEqual(code, 0, err + out)
        f = self.f
        self.assertEqual(f.read("src/main.js"), js_header() + BODY + "more();\n")
        self.assertEqual(
            f.read("src/camera.js"),
            js_header() + CAMERA_HERE.replace("tail8", "tail8_renamed"),
        )
        self.assertFalse((f.mono / APP / "src/old.js").exists())
        self.assertEqual(f.read("src/fresh.js"), "fresh();\n")
        self.assertFalse((f.mono / APP / "package-lock.json").exists())
        self.assertEqual(
            f.read("index.html"),
            "<!doctype html>\n" + html_header() + "<html lang=en></html>\n",
        )
        self.assertFalse(os.access(f.mono / APP / "scripts/dev.sh", os.X_OK))
        self.assertIn(f"# base\t{target}\ttree\t", f.changes_path.read_text())
        self.assertIn("`src/camera.js`: lands on Irvine", out)
        self.assertIn("`package-lock.json`: pnpm workspace", out)
        self.assertIn("run `bazel run //tools/license:add`", out)
        self.assertIn("`server/routes.js`", out)
        # server.mjs mounts the providers itself, so they need no follow-up.
        self.assertNotIn("server/providers/flights.js", out)
        self.assertIn("new top-level entries `maps`", out)
        # New files lack the header until //tools/license:add runs; the check
        # sets the header aside, so the copy already reads as the new base.
        code, _, err = f.tool("check", fetch=False)
        self.assertEqual(code, 0, err)

    def test_sync_marks_conflicts_and_still_moves_the_base(self):
        write(self.f.up, "src/camera.js", CAMERA.replace("'Austin'", "'Denver'"))
        target = commit(self.f.up, "B")
        code, out, _ = self.f.tool("sync")
        self.assertEqual(code, 1)
        text = self.f.read("src/camera.js")
        self.assertTrue(text.startswith(js_header()))
        self.assertIn("<<<<<<< this copy", text)
        self.assertIn("'Irvine'", text)
        self.assertIn("'Denver'", text)
        self.assertIn("`src/camera.js`: 1 conflict(s) marked in the file", out)
        self.assertIn(target, self.f.changes_path.read_text())

    def test_sync_will_not_overwrite_what_this_copy_changed_and_upstream_deleted(self):
        (self.f.up / "src/camera.js").unlink()
        commit(self.f.up, "B")
        code, out, _ = self.f.tool("sync")
        self.assertEqual(code, 1)
        self.assertTrue((self.f.mono / APP / "src/camera.js").exists())
        self.assertIn(
            "upstream deleted it, and this copy changes it (lands on Irvine)", out
        )

    def test_dry_run_changes_nothing(self):
        self.upstream_moves()
        before = self.f.changes_path.read_text()
        code, out, err = self.f.tool("sync", "--dry-run")
        self.assertEqual(code, 0, err)
        self.assertIn("(dry run)", out)
        self.assertEqual(run(self.f.mono, "status", "--porcelain"), "")
        self.assertEqual(self.f.changes_path.read_text(), before)

    def test_sync_refuses_a_dirty_copy(self):
        self.upstream_moves()
        write(self.f.mono / APP, "src/main.js", "edited\n")
        code, _, err = self.f.tool("sync")
        self.assertEqual(code, 2)
        self.assertIn("uncommitted changes", err)


if __name__ == "__main__":
    unittest.main()
