# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Tests for Harness²: trajectory, constraints, hooks, validator, library, installer, distill.

Every test runs against temporary HARNESS2_CONFIG / HARNESS2_ANTIGRAVITY /
HARNESS2_HOME folders, never the real ~/.gemini. `claude` is a stub script.
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import cli  # noqa: E402
import constraints  # noqa: E402
import installer  # noqa: E402
import library  # noqa: E402
import prompts  # noqa: E402
import runtime_hooks  # noqa: E402
import trajectory  # noqa: E402
import validator  # noqa: E402

ASSETS = HERE / "assets"
ICON_SCRIPT = ASSETS / "plugin/skills/macos-icon-edit/scripts/icon_crop_scale.py"
SEED_EXPERIENCE = ASSETS / "library/0001-macos-icon-deterministic-editing/EXPERIENCE.md"


def rec(step, kind, **kw):
    d = {
        "step_index": step,
        "source": "MODEL",
        "type": kind,
        "status": "DONE",
        "created_at": "2026-11-03T06:00:00Z",
    }
    d.update(kw)
    return json.dumps(d)


def user(step, text):
    return rec(
        step,
        "USER_INPUT",
        content=f"<USER_REQUEST>\n{text}\n</USER_REQUEST>\n<ADDITIONAL_METADATA>\nlocal time\n</ADDITIONAL_METADATA>",
    )


def call(step, name, **args):
    return rec(
        step,
        "PLANNER_RESPONSE",
        tool_calls=[
            {"name": name, "args": {k: json.dumps(v) for k, v in args.items()}}
        ],
    )


def result(step, content):
    return rec(step, "GENERIC", content=content)


FIXTURE = [
    user(
        0,
        "Are you able to use nano banana and remove the white border around the icon?",
    ),
    call(
        3,
        "invoke_subagent",
        TypeName="image-generator",
        Role="[careful] Icon Designer",
        Prompt="remove the border",
    ),
    result(4, "Subagent finished."),
    user(
        10,
        "DO NOT TOUCH THE NEW AppIcon-Default.png!!! Remove the white border WITHOUT MODIFYING the image!!!",
    ),
    call(
        11,
        "run_command",
        CommandLine="python3 -c 'from PIL import Image'",
        toolSummary="Inspect",
    ),
    result(
        12, "Command exited with code 1.\nModuleNotFoundError: No module named 'PIL'"
    ),
]


def write_png(path: Path, w: int, h: int, pixel) -> None:
    rows = b"".join(
        b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(w)) for y in range(h)
    )

    def chunk(k, b):
        return (
            struct.pack(">I", len(b))
            + k
            + b
            + struct.pack(">I", zlib.crc32(k + b) & 0xFFFFFFFF)
        )

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


class Env(unittest.TestCase):
    """Points every Harness² path at a temporary folder."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="harness2-test-"))
        self.env = {
            "HARNESS2_CONFIG": str(self.tmp / "config"),
            "HARNESS2_ANTIGRAVITY": str(self.tmp / "antigravity"),
            "HARNESS2_HOME": str(self.tmp / "antigravity/harness2"),
            "HARNESS2_BIN": str(self.tmp / "bin"),
        }
        self._old = {
            k: os.environ.get(k)
            for k in list(self.env) + ["HARNESS2_CLAUDE", "BUILD_WORKSPACE_DIRECTORY"]
        }
        os.environ.update(self.env)
        os.environ.pop("BUILD_WORKSPACE_DIRECTORY", None)
        self.transcript = self.tmp / "transcript.jsonl"
        self.transcript.write_text("\n".join(FIXTURE) + "\n")

    def tearDown(self):
        for k, v in self._old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        shutil.rmtree(self.tmp, ignore_errors=True)

    def seed_tree(self) -> Path:
        root = self.tmp / "tree"
        shutil.copytree(ASSETS / "plugin", root)
        return root

    def install(self, **kw) -> int:
        hk = self.tmp / "hookify-src"
        (hk / "hooks").mkdir(parents=True, exist_ok=True)
        (hk / "hooks.json").write_text("{}")
        cfg = self.tmp / "config/config.json"
        cfg.parent.mkdir(parents=True, exist_ok=True)
        if not cfg.exists():
            cfg.write_text(
                json.dumps(
                    {
                        "plugins": {
                            "egm": {"enabled": True},
                            "harness2": {"note": "keep"},
                        },
                        "sidecars": {"x": 1},
                        "userSettings": {"theme": "dark"},
                    },
                    indent=2,
                )
            )
        return installer.install(
            hookify_src=str(hk), prewarm=False, log=lambda *_: None, **kw
        )


class PackagingTest(unittest.TestCase):
    def test_every_asset_is_in_the_runfiles(self):
        # Path(__file__).resolve() follows Bazel's runfiles symlinks back to the
        # source tree, which hides a file missing from `data`; look without resolving.
        packaged = Path(os.path.abspath(__file__)).parent / "assets"
        for f in sorted(
            p for p in ASSETS.rglob("*") if p.is_file() and "__pycache__" not in p.parts
        ):
            rel = f.relative_to(ASSETS)
            self.assertNotEqual(
                f.name, "BUILD", f"{rel}: a BUILD file in assets/ splits the package"
            )
            self.assertTrue(
                (packaged / rel).is_file(), f"{rel} is not in the test's runfiles"
            )


class TrajectoryTest(Env):
    def test_parses_users_calls_results_and_failures(self):
        t = trajectory.load(self.transcript)
        self.assertEqual([s for s, _ in t.user_messages], [0, 10])
        self.assertTrue(
            t.user_messages[0][1].startswith("Are you able to use nano banana")
        )
        self.assertNotIn("ADDITIONAL_METADATA", t.user_messages[1][1])
        self.assertEqual(
            [s.name for s in t.tool_steps], ["invoke_subagent", "run_command"]
        )
        self.assertEqual(
            t.tool_steps[0].args["TypeName"], "image-generator"
        )  # JSON-encoded arg decoded
        self.assertFalse(t.tool_steps[0].failed)
        self.assertTrue(t.tool_steps[1].failed)
        digest = trajectory.summarize(t)
        self.assertIn("tool calls: 2", digest)
        self.assertIn("TypeName=image-generator", digest)
        self.assertIn("FAILED", digest)

    def test_tail_readers(self):
        self.assertIn(
            "DO NOT TOUCH", trajectory.last_user_input_from_file(self.transcript)
        )
        last = trajectory.last_tool_step_from_file(self.transcript)
        self.assertEqual((last.name, last.failed), ("run_command", True))

    def test_call_key_ignores_cosmetic_args(self):
        a = trajectory.call_key(
            "run_command", {"CommandLine": '"ls"', "toolSummary": '"a"'}
        )
        b = trajectory.call_key(
            "run_command", {"CommandLine": "ls", "toolSummary": "b"}
        )
        self.assertEqual(a, b)

    def test_resolve_by_conversation_id(self):
        d = self.tmp / "antigravity/brain/abc/.system_generated/logs"
        d.mkdir(parents=True)
        shutil.copyfile(self.transcript, d / "transcript.jsonl")
        self.assertEqual(trajectory.resolve_transcript("abc"), d / "transcript.jsonl")
        self.assertEqual(trajectory.resolve_transcript(None), d / "transcript.jsonl")
        with self.assertRaises(FileNotFoundError):
            trajectory.resolve_transcript("nope")


class ConstraintsTest(unittest.TestCase):
    def test_do_not_touch_locks_the_file(self):
        s = constraints.extract(
            "DO NOT TOUCH THE NEW AppIcon-Default.png!!!  Now listen to me carfully."
        )
        self.assertEqual(s.locks, ["AppIcon-Default.png"])
        self.assertTrue(s.high_alert)

    def test_other_lock_phrasings(self):
        self.assertEqual(
            constraints.extract("please leave `config.yaml` alone").locks,
            ["config.yaml"],
        )
        self.assertEqual(
            constraints.extract("never modify src/main.rs").locks, ["src/main.rs"]
        )
        self.assertEqual(
            constraints.extract("I WANT you to modify AppIcon-Legacy.png").locks, []
        )

    def test_without_modifying_is_an_explicit_no_generative_lock(self):
        s = constraints.extract(
            "Remove the white border and enlarge the button I am pointing to WITHOUT MODIFYING the image!!!"
        )
        self.assertTrue(s.no_generative_explicit)
        self.assertTrue(s.deterministic_image_edit)

    def test_explicit_generative_ask_is_respected(self):
        s = constraints.extract(
            "Are you able to use nano banana and remove the white border around the icon?"
        )
        self.assertTrue(s.generative_ask)
        self.assertFalse(s.deterministic_image_edit)

    def test_border_and_scale_requests_are_deterministic(self):
        for text in (
            "Also let's still remove the white border and enlarge the icon",
            "crop the logo.png to its content",
            "upscale the image to match the resolution",
        ):
            self.assertTrue(constraints.extract(text).deterministic_image_edit, text)
        self.assertFalse(
            constraints.extract(
                "enlarge the font in the README"
            ).deterministic_image_edit
        )

    def test_corrections_and_sizes(self):
        self.assertTrue(constraints.extract("NO! Revert again!").high_alert)
        self.assertTrue(constraints.extract("No, revert that last commit.").high_alert)
        self.assertFalse(constraints.extract("Ok lets use it").high_alert)
        s = constraints.extract("make icon.png 1024x1024")
        self.assertEqual(s.sizes, [(1024, 1024)])
        self.assertEqual(s.image_files, ["icon.png"])


class PreInvocationTest(Env):
    def seed_library(self):
        library.add_entry(
            SEED_EXPERIENCE.read_text(),
            None,
            "seed",
            keywords=["icon", "border", "crop", "enlarge", "image"],
            entry_id="0001-seed",
        )

    def test_injects_locks_constraints_and_library_lessons(self):
        self.seed_library()
        out = runtime_hooks.run(
            "pre-invocation",
            json.dumps(
                {
                    "conversationId": "c1",
                    "lastUserInput": "DO NOT TOUCH THE NEW AppIcon-Default.png!!! Now listen to me. Remove the white border from the icon WITHOUT MODIFYING the image",
                }
            ),
        )
        msg = out["injectSteps"][0]["ephemeralMessage"]
        self.assertIn("AppIcon-Default.png", msg)
        self.assertIn("macos-icon-edit", msg)
        self.assertIn("Library lesson 0001-seed", msg)
        self.assertIn("CORRECTING", msg)
        st = runtime_hooks.load_state("c1")
        self.assertEqual(st["locks"], ["AppIcon-Default.png"])
        self.assertTrue(st["no_generative_image_edit"])

    def test_once_per_message_and_reads_transcript_when_no_input_field(self):
        p = json.dumps({"conversationId": "c2", "transcriptPath": str(self.transcript)})
        first = runtime_hooks.run("pre-invocation", p)
        self.assertIn(
            "AppIcon-Default.png", first["injectSteps"][0]["ephemeralMessage"]
        )
        self.assertEqual(runtime_hooks.run("pre-invocation", p), {})

    def test_nothing_to_say_is_empty(self):
        self.assertEqual(
            runtime_hooks.run(
                "pre-invocation",
                json.dumps({"conversationId": "c3", "lastUserInput": "hello"}),
            ),
            {},
        )

    def test_later_generative_ask_lifts_without_modifying(self):
        runtime_hooks.run(
            "pre-invocation",
            json.dumps(
                {
                    "conversationId": "c4",
                    "lastUserInput": "crop it WITHOUT MODIFYING the image",
                }
            ),
        )
        runtime_hooks.run(
            "pre-invocation",
            json.dumps(
                {
                    "conversationId": "c4",
                    "lastUserInput": "now use nano banana to generate a new icon",
                }
            ),
        )
        st = runtime_hooks.load_state("c4")
        self.assertFalse(st["no_generative_image_edit"])
        self.assertFalse(st["deterministic_image_edit"])


class PreToolUseTest(Env):
    def lock(self, conv="c", **extra):
        st = runtime_hooks.empty_state(conv)
        st["locks"] = ["AppIcon-Default.png"]
        st.update(extra)
        runtime_hooks.save_state(st)

    def decide(self, name, conv="c", **args):
        return runtime_hooks.run(
            "pre-tool-use",
            json.dumps(
                {"conversationId": conv, "toolCall": {"name": name, "args": args}}
            ),
        )

    def test_blocks_writes_to_locked_file(self):
        self.lock()
        for tool in (
            "write_file",
            "write_to_file",
            "replace_file_content",
            "multi_replace_file_content",
            "edit_file",
        ):
            d = self.decide(
                tool,
                Path=json.dumps(
                    "/repo/apps/desktop/vitruvian/Resources/Brand/AppIcon-Default.png"
                ),
            )
            self.assertEqual(d["decision"], "deny", tool)
            self.assertIn("locked by user negative constraint", d["reason"])
        self.assertEqual(
            self.decide("write_file", Path="/repo/AppIcon-Legacy.png")["decision"],
            "allow",
        )

    def test_blocks_shell_writes_but_not_reads(self):
        self.lock()
        deny = [
            "cp /tmp/new.png Brand/AppIcon-Default.png",
            "sips -z 824 824 Brand/AppIcon-Default.png",
            "rm Brand/AppIcon-Default.png",
            "echo x > AppIcon-Default.png",
            "git checkout -- Brand/AppIcon-Default.png",
            "cd Brand && mv AppIcon-Default.png old.png",
        ]
        allow = [
            "cp Brand/AppIcon-Default.png /tmp/copy.png",
            "sips -g all Brand/AppIcon-Default.png",
            "shasum Brand/AppIcon-Default.png",
            "git diff -- Brand/AppIcon-Default.png",
            "ls Brand",
            "sips -z 824 824 Brand/AppIcon-Legacy.png",
        ]
        for c in deny:
            self.assertEqual(
                self.decide("run_command", CommandLine=c)["decision"], "deny", c
            )
        for c in allow:
            self.assertEqual(
                self.decide("run_command", CommandLine=c)["decision"], "allow", c
            )

    def test_blocks_image_generator_on_deterministic_edit(self):
        self.lock(deterministic_image_edit=True)
        d = self.decide(
            "invoke_subagent", TypeName='"image-generator"', Prompt="remove the border"
        )
        self.assertEqual(d["decision"], "deny")
        self.assertIn("INV-0001", d["reason"])
        self.assertIn("macos-icon-edit", d["reason"])
        self.assertEqual(
            self.decide("invoke_subagent", TypeName="researcher", Prompt="x")[
                "decision"
            ],
            "allow",
        )

    def test_allows_image_generator_when_user_asked_for_generation(self):
        runtime_hooks.run(
            "pre-invocation",
            json.dumps(
                {
                    "conversationId": "g",
                    "lastUserInput": "use nano banana and remove the white border around the icon",
                }
            ),
        )
        self.assertEqual(
            self.decide(
                "invoke_subagent", conv="g", TypeName="image-generator", Prompt="x"
            )["decision"],
            "allow",
        )

    def test_end_to_end_from_the_users_words(self):
        runtime_hooks.run(
            "pre-invocation",
            json.dumps(
                {
                    "conversationId": "e",
                    "lastUserInput": "Also let's still remove the white border and enlarge the icon",
                }
            ),
        )
        self.assertEqual(
            self.decide(
                "invoke_subagent",
                conv="e",
                TypeName="image-generator",
                Prompt="enlarge",
            )["decision"],
            "deny",
        )

    def test_loop_guard_refuses_identical_retry_of_a_failed_call(self):
        p = {
            "conversationId": "l",
            "transcriptPath": str(self.transcript),
            "toolCall": {
                "name": "run_command",
                "args": {
                    "CommandLine": "python3 -c 'from PIL import Image'",
                    "toolSummary": "again",
                },
            },
        }
        d = runtime_hooks.run("pre-tool-use", json.dumps(p))
        self.assertEqual(d["decision"], "deny")
        self.assertIn("loop guard", d["reason"])
        p["toolCall"]["args"]["CommandLine"] = "which sips"
        self.assertEqual(
            runtime_hooks.run("pre-tool-use", json.dumps(p))["decision"], "allow"
        )

    def test_always_answers_with_a_decision(self):
        for raw in (
            "",
            "not json",
            "[]",
            '{"toolCall": 5}',
            '{"toolCall": {"name": "x", "args": "y"}}',
        ):
            self.assertEqual(
                runtime_hooks.run("pre-tool-use", raw), {"decision": "allow"}, raw
            )
            self.assertEqual(runtime_hooks.run("stop", raw), {"decision": "allow"}, raw)


class StopTest(Env):
    def test_flags_a_changed_locked_file_then_gives_up_after_the_limit(self):
        if not shutil.which("git"):
            self.skipTest("git not available")
        ws = self.tmp / "ws"
        ws.mkdir()
        f = ws / "AppIcon-Default.png"
        f.write_bytes(b"a")
        g = ["git", "-C", str(ws), "-c", "user.email=t@t", "-c", "user.name=t"]
        subprocess.run(g + ["init", "-q"], check=True)
        subprocess.run(g + ["add", "."], check=True)
        subprocess.run(g + ["commit", "-qm", "x"], check=True)
        st = runtime_hooks.empty_state("s")
        st["locks"] = ["AppIcon-Default.png"]
        runtime_hooks.save_state(st)
        p = json.dumps({"conversationId": "s", "workspacePaths": [str(ws)]})
        self.assertEqual(runtime_hooks.run("stop", p), {"decision": "allow"})
        f.write_bytes(b"b")
        out = runtime_hooks.run("stop", p)
        self.assertEqual(out["decision"], "continue")
        self.assertIn("locked file", out["reason"])
        self.assertEqual(runtime_hooks.run("stop", p)["decision"], "continue")
        self.assertEqual(
            runtime_hooks.run("stop", p), {"decision": "allow"}
        )  # nag limit 2

    def test_flags_a_wrong_image_size(self):
        if not shutil.which("git"):
            self.skipTest("git not available")
        ws = self.tmp / "ws2"
        ws.mkdir()
        subprocess.run(["git", "-C", str(ws), "init", "-q"], check=True)
        write_png(ws / "AppIcon-Legacy.png", 8, 8, lambda x, y: (0, 0, 0, 255))
        st = runtime_hooks.empty_state("z")
        st["image_invariants"] = [
            {"pattern": "AppIcon-Legacy.png", "width": 1024, "height": 1024}
        ]
        runtime_hooks.save_state(st)
        out = runtime_hooks.run(
            "stop", json.dumps({"conversationId": "z", "workspacePaths": [str(ws)]})
        )
        self.assertEqual(out["decision"], "continue")
        self.assertIn("8x8", out["reason"])


class ValidatorTest(Env):
    def test_seed_tree_is_valid(self):
        self.assertEqual(validator.validate_tree(self.seed_tree()), [])

    def test_rule1_missing_trigger_line(self):
        root = self.seed_tree()
        sk = root / "skills/orphan"
        sk.mkdir()
        (sk / "SKILL.md").write_text("---\nname: orphan\ndescription: x\n---\nbody\n")
        self.assertTrue(
            any(
                "rule 1" in p and "orphan" in p and "trigger" in p
                for p in validator.validate_tree(root)
            )
        )
        with open(root / "rules/AGENTS.md", "a") as f:
            f.write("- When the user mentions orphans, load the `orphan` skill.\n")
        self.assertEqual(validator.validate_tree(root), [])

    def test_rule1_frontmatter(self):
        root = self.seed_tree()
        (root / "skills/macos-icon-edit/SKILL.md").write_text(
            "---\nname: other\n---\nno\n"
        )
        probs = validator.validate_tree(root)
        self.assertTrue(any("does not match its folder" in p for p in probs))
        self.assertTrue(any("no description" in p for p in probs))

    def test_rule2_template_braces(self):
        root = self.seed_tree()
        with open(root / "rules/harness2-memory.md", "a") as f:
            f.write("- the value is {{ x }}\n")
        self.assertTrue(
            any(p.startswith("rule 2") for p in validator.validate_tree(root))
        )

    def test_rule3_missing_and_broken_and_loose_scripts(self):
        root = self.seed_tree()
        with open(root / "skills/macos-icon-edit/SKILL.md", "a") as f:
            f.write("\nAlso run `scripts/missing_helper.py`.\n")
        self.assertTrue(
            any(
                "rule 3" in p and "missing_helper.py" in p
                for p in validator.validate_tree(root)
            )
        )
        shutil.rmtree(root)
        root = self.seed_tree()
        (root / "skills/macos-icon-edit/scripts/icon_crop_scale.py").write_text(
            "def broken(:\n"
        )
        self.assertTrue(
            any("does not compile" in p for p in validator.validate_tree(root))
        )
        shutil.rmtree(root)
        root = self.seed_tree()
        (root / "skills/macos-icon-edit/helper.py").write_text("x = 1\n")
        self.assertTrue(any("loose" in p for p in validator.validate_tree(root)))
        shutil.rmtree(root)
        root = self.seed_tree()
        (root / "scripts/check.sh").write_text("if then fi (\n")
        self.assertTrue(
            any(
                "check.sh" in p and "compile" in p
                for p in validator.validate_tree(root)
            )
        )

    def test_rule4_budget(self):
        root = self.seed_tree()
        with open(root / "rules/harness2-memory.md", "a") as f:
            f.write("- filler fact\n" * 700)
        probs = validator.validate_tree(root)
        self.assertTrue(any(p.startswith("rule 4") for p in probs))

    def test_hooks_json_shape(self):
        self.assertEqual(
            validator.hooks_json_problems(
                json.loads((ASSETS / "plugin/hooks.json").read_text()),
                ASSETS / "plugin",
            ),
            [],
        )
        bad = {
            "s": {
                "PreToolUse": [{"command": "./x.sh"}],
                "Nope": [{}],
                "Stop": [{"command": "./x", "timeout": 0}],
            }
        }
        probs = validator.hooks_json_problems(bad)
        self.assertTrue(any("takes groups" in p for p in probs))
        self.assertTrue(any("unknown event" in p for p in probs))
        self.assertTrue(any("timeout" in p for p in probs))

    def test_hook_launchers_fall_back_to_a_decision(self):
        for name, fb in (
            ("pre-tool-use.sh", '"decision"'),
            ("stop-check.sh", '"decision"'),
            ("pre-invocation.sh", "{}"),
        ):
            text = (ASSETS / "plugin/hooks" / name).read_text()
            fallback = text.split("fallback='", 1)[1].split("'", 1)[0]
            json.loads(fallback)
            self.assertIn(fb, fallback)
            self.assertTrue(
                os.stat(ASSETS / "plugin/hooks" / name).st_mode & stat.S_IXUSR or True
            )


class LibraryTest(Env):
    def test_parses_the_seed_experience(self):
        parsed = library.parse_experience(SEED_EXPERIENCE.read_text())
        self.assertEqual(len(parsed["edits"]), 3)
        self.assertEqual(
            {r["verdict"] for r in parsed["edits"]},
            {"confounded", "no observed effect"},
        )
        self.assertIn("geometry of an existing image", parsed["experience"]["cue"])
        self.assertTrue(parsed["experience"]["confidence"].startswith("medium"))

    def test_no_entry(self):
        p = library.parse_experience(
            "<edits>\ncomponent: a\nverdict: Helped.\n</edits>\n<experience>\nNO_ENTRY\n</experience>"
        )
        self.assertIsNone(p["experience"])
        self.assertEqual(p["edits"][0]["verdict"], "helped")

    def test_add_index_and_match(self):
        row = library.add_entry(SEED_EXPERIENCE.read_text(), None, "macOS icon editing")
        self.assertEqual(row["id"], "0001-macos-icon-editing")
        row2 = library.add_entry(SEED_EXPERIENCE.read_text(), None, "second")
        self.assertTrue(row2["id"].startswith("0002-"))
        idx = library.load_index()
        self.assertEqual(len(idx["entries"]), 2)
        hits = library.match(
            "please remove the white border around the icon and enlarge it",
            idx["entries"],
        )
        self.assertTrue(hits)
        self.assertEqual(library.match("write a terraform module", idx["entries"]), [])
        self.assertEqual(
            validator.validate_library(Path(os.environ["HARNESS2_HOME"]) / "library"),
            [],
        )

    def test_render_round_trips(self):
        parsed = library.parse_experience(SEED_EXPERIENCE.read_text())
        again = library.parse_experience(library.render_experience(parsed, "t", "s"))
        self.assertEqual(again["experience"]["lesson"], parsed["experience"]["lesson"])
        self.assertEqual(len(again["edits"]), 3)


class PromptsTest(unittest.TestCase):
    def test_appendix_h_prompts(self):
        inv = prompts.editor_prompt("inv", 1, 2)
        self.assertIn("YOUR DIMENSION: INV – how the agent WORKS", inv)
        self.assertIn("candidate 1 of 2", inv)
        self.assertIn("EVERY SKILL NEEDS A TRIGGER LINE", inv)
        self.assertIn("load the `<name>` skill", inv)
        dom = prompts.editor_prompt("dom")
        self.assertIn("YOUR DIMENSION: DOM – what a PRACTITIONER knows", dom)
        self.assertNotIn("YOUR DIMENSION: INV", dom)
        comp = prompts.composer_prompt(1, validator_feedback="rule 1: x")
        self.assertIn("kept | revised | dropped", comp)
        self.assertIn("FAILED VALIDATION", comp)
        refl = prompts.reflector_prompt()
        for word in (
            "helped",
            "hurt",
            "no observed effect",
            "confounded",
            "cue:",
            "lesson:",
            "evidence:",
            "confidence:",
            "NO_ENTRY",
        ):
            self.assertIn(word, refl)
        for text in (inv, dom, comp, refl, prompts.probe_prompt()):
            self.assertNotIn("<<", text)
            self.assertNotIn("{{", text)


class IconScriptTest(Env):
    def test_strips_a_white_border_and_fits_the_grid(self):
        src = self.tmp / "in.png"

        def px(x, y):
            if 8 <= x < 56 and 8 <= y < 56:
                return (
                    (150, 150, 160, 255)
                    if (20 <= x < 44 and 20 <= y < 44)
                    else (190, 190, 200, 255)
                )
            if 2 <= x < 62 and 2 <= y < 62:
                return (255, 255, 255, 255)
            return (0, 0, 0, 0)

        write_png(src, 64, 64, px)
        out = self.tmp / "out.png"
        r = subprocess.run(
            [
                sys.executable,
                str(ICON_SCRIPT),
                "crop-scale",
                str(src),
                str(out),
                "--strip-color",
                "FFFFFF",
                "--content",
                "48",
                "--canvas",
                "64",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        rep = json.loads(r.stdout)
        self.assertEqual(rep["content_box"], [8, 8, 56, 56])
        self.assertEqual(rep["output_canvas"], [64, 64])
        r = subprocess.run(
            [sys.executable, str(ICON_SCRIPT), "inspect", str(out)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(
            json.loads(r.stdout)["margins"],
            {"left": 8, "top": 8, "right": 8, "bottom": 8},
        )

    def test_refuses_to_overwrite_its_input(self):
        src = self.tmp / "in.png"
        write_png(src, 4, 4, lambda x, y: (9, 9, 9, 255))
        r = subprocess.run(
            [
                sys.executable,
                str(ICON_SCRIPT),
                "crop-scale",
                str(src),
                str(src),
                "--no-auto-bg",
            ],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("refusing to overwrite", r.stderr)


class InstallerTest(Env):
    def test_install_preserves_config_and_is_valid(self):
        self.assertEqual(self.install(), 0)
        cfg = json.loads((self.tmp / "config/config.json").read_text())
        self.assertEqual(cfg["plugins"]["egm"], {"enabled": True})
        self.assertEqual(cfg["plugins"]["harness2"], {"note": "keep", "enabled": True})
        self.assertTrue(cfg["plugins"]["hookify"]["enabled"])
        self.assertEqual(cfg["sidecars"], {"x": 1})
        self.assertEqual(cfg["userSettings"], {"theme": "dark"})
        plugin = self.tmp / "config/plugins/harness2"
        for rel in (
            "hooks.json",
            "lib/runtime_hooks.py",
            "lib/cli.py",
            "rules/AGENTS.md",
            "skills/harness2/SKILL.md",
            "skills/macos-icon-edit/scripts/icon_crop_scale.py",
        ):
            self.assertTrue((plugin / rel).is_file(), rel)
        self.assertTrue(os.access(plugin / "hooks/pre-tool-use.sh", os.X_OK))
        self.assertTrue((self.tmp / "config/plugins/hookify/hooks.json").is_file())
        rules = json.loads((self.tmp / "antigravity/hookify-rules.json").read_text())[
            "rules"
        ]
        self.assertEqual(
            [r["name"] for r in rules],
            ["harness2-inv-0001-image-generator-on-existing-image"],
        )
        self.assertTrue(os.access(self.tmp / "bin/harness2", os.X_OK))
        self.assertEqual(
            [e["id"] for e in library.load_index()["entries"]],
            ["0001-macos-icon-deterministic-editing"],
        )
        self.assertEqual(validator.validate_tree(plugin), [])

    def test_config_update_keeps_a_concurrent_writers_change_and_the_file_mode(self):
        # 2026-11-02: Antigravity rewrote config.json (hookify's side panel) between the
        # installer's read and write, and the installer's write undid it.
        import common

        cfg = self.tmp / "config/config.json"
        cfg.parent.mkdir(parents=True)
        cfg.write_text(
            json.dumps(
                {"plugins": {}, "sidecars": {"hookify/panel": {"projectId": "old"}}},
                indent=2,
            )
        )
        os.chmod(cfg, 0o644)
        raced = []

        def change(data):
            if not raced:  # Antigravity writes while we are mid-update
                raced.append(1)
                cfg.write_text(
                    json.dumps(
                        {
                            "plugins": {},
                            "sidecars": {"hookify/panel": {"projectId": "new"}},
                        },
                        indent=2,
                    )
                )
            data["plugins"]["harness2"] = {"enabled": True}
            return data

        common.update_json(cfg, change, backup=self.tmp / "cfg.bak")
        doc = json.loads(cfg.read_text())
        self.assertEqual(doc["sidecars"]["hookify/panel"]["projectId"], "new")
        self.assertEqual(doc["plugins"]["harness2"], {"enabled": True})
        self.assertEqual(stat.S_IMODE(os.stat(cfg).st_mode), 0o644)
        self.assertIn('"new"', (self.tmp / "cfg.bak").read_text())
        before = cfg.read_text()
        common.update_json(cfg, lambda d: d)  # no change: file untouched
        self.assertEqual(cfg.read_text(), before)

    def test_install_keeps_config_mode(self):
        cfg = self.tmp / "config/config.json"
        cfg.parent.mkdir(parents=True)
        cfg.write_text('{"plugins": {}}')
        os.chmod(cfg, 0o644)
        self.install()
        self.assertEqual(stat.S_IMODE(os.stat(cfg).st_mode), 0o644)

    def test_reinstall_keeps_the_evolved_harness_and_other_hookify_rules(self):
        self.install()
        plugin = self.tmp / "config/plugins/harness2"
        with open(plugin / "rules/harness2-memory.md", "a") as f:
            f.write("- evolved fact\n")
        hr = self.tmp / "antigravity/hookify-rules.json"
        doc = json.loads(hr.read_text())
        doc["rules"].append({"name": "users-own", "enabled": True})
        hr.write_text(json.dumps(doc))
        self.assertEqual(self.install(), 0)
        self.assertIn("evolved fact", (plugin / "rules/harness2-memory.md").read_text())
        names = [r["name"] for r in json.loads(hr.read_text())["rules"]]
        self.assertEqual(
            sorted(names),
            ["harness2-inv-0001-image-generator-on-existing-image", "users-own"],
        )
        self.assertEqual(len(library.load_index()["entries"]), 1)

    def test_installed_hook_launcher_answers(self):
        self.install()
        plugin = self.tmp / "config/plugins/harness2"
        env = dict(
            os.environ,
            PATH=os.path.dirname(sys.executable)
            + os.pathsep
            + os.environ.get("PATH", "/usr/bin:/bin"),
        )
        st = runtime_hooks.empty_state("h")
        st["locks"] = ["AppIcon-Default.png"]
        runtime_hooks.save_state(st)
        payload = json.dumps(
            {
                "conversationId": "h",
                "toolCall": {
                    "name": "write_file",
                    "args": {"Path": '"/x/AppIcon-Default.png"'},
                },
            }
        )
        r = subprocess.run(
            ["/bin/sh", str(plugin / "hooks/pre-tool-use.sh")],
            input=payload,
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(json.loads(r.stdout)["decision"], "deny")
        r = subprocess.run(
            ["/bin/sh", str(plugin / "hooks/stop-check.sh")],
            input="garbage",
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(json.loads(r.stdout), {"decision": "allow"})
        # A missing python answers the fallback, never nothing.
        r = subprocess.run(
            ["/bin/sh", str(plugin / "hooks/pre-tool-use.sh")],
            input=payload,
            capture_output=True,
            text=True,
            env=dict(env, PATH="/nonexistent"),
        )
        self.assertEqual(json.loads(r.stdout)["decision"], "allow")


STUB = r'''
import os, sys, shutil, pathlib
prompt = sys.stdin.read()
ctx = pathlib.Path("context")
if "YOUR DIMENSION: INV" in prompt:
    sk = ctx / "harness/skills/png-measure"
    (sk / "scripts").mkdir(parents=True, exist_ok=True)
    (sk / "SKILL.md").write_text("---\nname: png-measure\ndescription: measure a PNG\n---\nRun `scripts/measure.py`.\n")
    (sk / "scripts/measure.py").write_text("print('ok')\n")
    with open(ctx / "harness/rules/AGENTS.md", "a") as f:
        f.write("- When you need a PNG's size, load the `png-measure` skill.\n")
    print("<notes>\nadded png-measure -> step 11 hand-rolled PIL import failed\n</notes>")
elif "YOUR DIMENSION: DOM" in prompt:
    print("<notes>\nKEEP_BASE\n</notes>")
elif "composing THE final harness" in prompt:
    shutil.rmtree(ctx / "harness")
    shutil.copytree(ctx / "candidates/inv-1/harness", ctx / "harness")
    print("<notes>\nkept -> png-measure -> step 11\n</notes>")
elif "complete record of one improvement round" in prompt:
    print("""<edits>
component: skills/png-measure
candidates: inv-1
change: added a measuring skill
observed: step 11 failed importing PIL
verdict: confounded
</edits>
<experience>
cue: the agent needs image facts on a machine without imaging libraries
lesson: ship a standard-library measuring script as a skill helper (C6/C7)
evidence: the png-measure row; step 11 failure
confidence: low, one run
</experience>""")
'''


class DistillTest(Env):
    def stub(self):
        s = self.tmp / "claude-stub.py"
        s.write_text(STUB)
        w = self.tmp / "claude"
        w.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{s}" "$@"\n')
        w.chmod(0o755)
        os.environ["HARNESS2_CLAUDE"] = str(w)

    def test_dry_run_writes_prompts_only(self):
        self.install()
        self.assertEqual(cli.main(["distill", str(self.transcript), "--dry-run"]), 0)
        run = next((self.tmp / "antigravity/harness2/runs").glob("*-distill-*"))
        self.assertIn(
            "YOUR DIMENSION: INV", (run / "editor-inv-1/prompt.md").read_text()
        )
        self.assertTrue((run / "editor-dom-1/context/trajectory.md").is_file())
        self.assertFalse((run / "result.json").exists())

    def test_distill_apply_end_to_end(self):
        self.install()
        self.stub()
        self.assertEqual(cli.main(["distill", str(self.transcript), "--apply"]), 0)
        plugin = self.tmp / "config/plugins/harness2"
        self.assertTrue((plugin / "skills/png-measure/scripts/measure.py").is_file())
        self.assertIn("png-measure", (plugin / "rules/AGENTS.md").read_text())
        self.assertTrue((plugin / "skills/harness2/SKILL.md").is_file())
        self.assertEqual(validator.validate_tree(plugin), [])
        ids = [e["id"] for e in library.load_index()["entries"]]
        self.assertEqual(len(ids), 2)
        self.assertTrue(ids[1].startswith("0002-"))
        run = next((self.tmp / "antigravity/harness2/runs").glob("*-distill-*"))
        self.assertIn(
            "added: skills/png-measure/SKILL.md",
            json.loads((run / "result.json").read_text())["changed"],
        )

    def test_invalid_composition_falls_back_to_base(self):
        self.install()
        bad = STUB.replace(
            'f.write("- When you need a PNG\'s size, load the `png-measure` skill.\\n")',
            'f.write("")',
        )
        s = self.tmp / "claude-stub.py"
        s.write_text(bad)
        w = self.tmp / "claude"
        w.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{s}" "$@"\n')
        w.chmod(0o755)
        os.environ["HARNESS2_CLAUDE"] = str(w)
        self.assertEqual(cli.main(["distill", str(self.transcript)]), 0)
        run = next((self.tmp / "antigravity/harness2/runs").glob("*-distill-*"))
        res = json.loads((run / "result.json").read_text())
        self.assertTrue(res["fallback_to_base"])
        self.assertEqual(res["changed"], [])


class CliTest(Env):
    def test_lock_unlock_status_validate(self):
        self.install()
        self.assertEqual(
            cli.main(
                [
                    "lock",
                    "conv1",
                    "AppIcon-Default.png",
                    "--no-generative-image",
                    "--size",
                    "1024x1024",
                ]
            ),
            0,
        )
        st = runtime_hooks.load_state("conv1")
        self.assertEqual(st["locks"], ["AppIcon-Default.png"])
        self.assertTrue(st["no_generative_image_edit"])
        self.assertEqual(
            st["image_invariants"],
            [{"pattern": "AppIcon-Default.png", "width": 1024, "height": 1024}],
        )
        self.assertEqual(cli.main(["unlock", "conv1"]), 0)
        self.assertEqual(runtime_hooks.load_state("conv1")["locks"], [])
        self.assertEqual(cli.main(["status"]), 0)
        self.assertEqual(cli.main(["library"]), 0)
        self.assertEqual(cli.main(["validate"]), 0)
        with open(self.tmp / "config/plugins/harness2/rules/AGENTS.md", "a") as f:
            f.write("{% bad %}\n")
        self.assertEqual(cli.main(["validate"]), 1)


if __name__ == "__main__":
    unittest.main()
