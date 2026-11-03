# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Structural validation of a harness tree before it is adopted (paper App. H).

A proposal that breaks any rule is thrown away whole (or retried once with
these messages, App. D.2):

  1. Every skill needs a verbatim trigger line in always-on text
     ("When <situation>, load the `<name>` skill.") and frontmatter whose
     `name:` matches its folder and which has a `description:`.
  2. No template braces (a doubled opening brace, or brace-percent) in
     always-on text.
  3. Every script a SKILL.md or always-on file names exists and compiles
     (`py_compile` for .py, `bash -n` for .sh); a skill's helpers live in
     `skills/<name>/scripts/`, not loose in the skill folder.
  4. Always-on text stays within a budget, so it never crowds out the
     executor's own reasoning.

Plus the plumbing the runtime needs: hooks.json in the shape Antigravity
loads, and parseable guardrails.json / hookify-rules.json.

The tree is the installed plugin folder: always-on files are `rules/*.md`.
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import List, Optional

ALWAYS_ON_GLOB = "rules/*.md"
# ~2,000 tokens across every always-on file: the paper's point is that each
# word is paid on every call. Override per call for experiments.
MAX_ALWAYS_ON_CHARS = 8000
MAX_ALWAYS_ON_LINES = 160

_SCRIPT_REF = re.compile(r"(?<![\w/.-])((?:[\w.~-]+/)*scripts/[\w./-]+?\.(?:py|sh))\b")
_BRACES = re.compile(r"\{\{|\{%")
GROUPED = ("PreToolUse", "PostToolUse")
FLAT = ("SessionStart", "PreInvocation", "PostInvocation", "Stop")


def frontmatter(text: str) -> Optional[dict]:
    """The `key: value` pairs of a leading `---` block, or None."""
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end < 0:
        return None
    out = {}
    for line in text[3:end].splitlines():
        m = re.match(r"^([A-Za-z_][\w-]*)\s*:\s*(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).strip().strip("'\"")
    return out


def always_on_files(root: Path) -> List[Path]:
    return sorted(root.glob(ALWAYS_ON_GLOB))


def trigger_line(name: str) -> "re.Pattern[str]":
    return re.compile(
        r"\bwhen\b[^\n]*?\bload the [`'\"]?" + re.escape(name) + r"[`'\"]? skill\b",
        re.I,
    )


def compiles(path: Path) -> Optional[str]:
    """None if the script compiles, else the error."""
    if path.suffix == ".py":
        try:
            compile(path.read_text(encoding="utf-8"), str(path), "exec")
        except (SyntaxError, ValueError, UnicodeDecodeError) as e:
            return f"{type(e).__name__}: {e}"
        return None
    if path.suffix == ".sh":
        try:
            r = subprocess.run(
                ["bash", "-n", str(path)], capture_output=True, text=True, timeout=20
            )
        except (OSError, subprocess.TimeoutExpired) as e:
            return f"bash -n could not run: {e}"
        return (
            None
            if r.returncode == 0
            else (r.stderr.strip() or f"bash -n exited {r.returncode}")
        )
    return None


def _resolve_script(ref: str, root: Path, base: Optional[Path]) -> List[Path]:
    ref = ref.replace("~/.gemini/config/plugins/harness2/", "")
    marker = "/plugins/harness2/"
    if marker in ref:
        ref = ref.split(marker, 1)[1]
    cands = []
    if base is not None:
        cands.append(base / ref)
    cands.append(root / ref)
    return cands


def validate_tree(
    root: Path,
    max_chars: int = MAX_ALWAYS_ON_CHARS,
    max_lines: int = MAX_ALWAYS_ON_LINES,
) -> List[str]:
    """Every rule violation in the harness tree at `root` (empty = valid)."""
    root = Path(root)
    problems: List[str] = []
    if not root.is_dir():
        return [f"{root}: harness tree does not exist"]

    on = always_on_files(root)
    on_text = {p: p.read_text(encoding="utf-8", errors="replace") for p in on}
    joined = "\n".join(on_text.values())

    # Rule 1: skills.
    skills_dir = root / "skills"
    for sk in (
        sorted(p for p in skills_dir.glob("*") if p.is_dir())
        if skills_dir.is_dir()
        else []
    ):
        md = sk / "SKILL.md"
        rel = md.relative_to(root)
        if not md.is_file():
            problems.append(f"rule 1: {sk.relative_to(root)}/ has no SKILL.md")
            continue
        fm = frontmatter(md.read_text(encoding="utf-8", errors="replace"))
        if fm is None:
            problems.append(f"rule 1: {rel} has no YAML frontmatter")
        else:
            if fm.get("name") != sk.name:
                problems.append(
                    f"rule 1: {rel} frontmatter name {fm.get('name')!r} does not match its folder {sk.name!r}"
                )
            if not fm.get("description"):
                problems.append(f"rule 1: {rel} frontmatter has no description")
        if not trigger_line(sk.name).search(joined):
            problems.append(
                f"rule 1: skill {sk.name!r} has no trigger line in always-on text "
                f"({ALWAYS_ON_GLOB}); add: When <situation>, load the `{sk.name}` skill."
            )
        for loose in sorted(sk.glob("*.py")) + sorted(sk.glob("*.sh")):
            problems.append(
                f"rule 3: {loose.relative_to(root)} is loose in the skill folder; "
                f"helpers belong in {sk.relative_to(root)}/scripts/"
            )

    # Subagents: Antigravity's own frontmatter needs a description.
    sub_dir = root / "sub_agents"
    if sub_dir.is_dir():
        for sa in sorted(sub_dir.glob("*.md")) + sorted(sub_dir.glob("*/AGENT.md")):
            if sa.name.upper() == "README.MD":
                continue
            fm = frontmatter(sa.read_text(encoding="utf-8", errors="replace"))
            if not fm or not fm.get("description"):
                problems.append(
                    f"subagent: {sa.relative_to(root)} needs frontmatter with a description"
                )

    # Rule 2: template braces.
    for p, text in on_text.items():
        for n, line in enumerate(text.splitlines(), 1):
            if _BRACES.search(line):
                problems.append(
                    f"rule 2: {p.relative_to(root)}:{n} has template braces; use a single brace or words"
                )

    # Rule 3: every named script exists and compiles.
    referers = [(p, None) for p in on] + [
        (md, md.parent)
        for md in sorted(skills_dir.glob("*/SKILL.md"))
        if skills_dir.is_dir()
    ]
    for p, base in referers:
        text = p.read_text(encoding="utf-8", errors="replace")
        for ref in dict.fromkeys(m.group(1) for m in _SCRIPT_REF.finditer(text)):
            found = next(
                (c for c in _resolve_script(ref, root, base) if c.is_file()), None
            )
            if found is None:
                problems.append(
                    f"rule 3: {p.relative_to(root)} names {ref}, which does not exist in the tree"
                )
                continue
            err = compiles(found)
            if err:
                problems.append(
                    f"rule 3: {found.relative_to(root)} does not compile: {err}"
                )
    for script in sorted(root.glob("scripts/*")) + sorted(
        root.glob("skills/*/scripts/*")
    ):
        if script.suffix in (".py", ".sh"):
            err = compiles(script)
            if err:
                msg = f"rule 3: {script.relative_to(root)} does not compile: {err}"
                if msg not in problems:
                    problems.append(msg)

    # Rule 4: always-on budget.
    chars = sum(len(t) for t in on_text.values())
    lines = sum(len(t.splitlines()) for t in on_text.values())
    if chars > max_chars:
        problems.append(
            f"rule 4: always-on text is {chars} chars (~{chars // 4} tokens), over the {max_chars}-char budget; cut before adding"
        )
    if lines > max_lines:
        problems.append(
            f"rule 4: always-on text is {lines} lines, over the {max_lines}-line budget"
        )

    problems += json_problems(root)
    problems += symlink_problems(root)
    return problems


def json_problems(root: Path) -> List[str]:
    out: List[str] = []
    for name in ("guardrails.json", "hookify-rules.json", "plugin.json"):
        p = root / name
        if p.exists():
            try:
                json.loads(p.read_text(encoding="utf-8"))
            except ValueError as e:
                out.append(f"plugin: {name} is not valid JSON: {e}")
    out += hook_rule_problems(root)
    hj = root / "hooks.json"
    if hj.exists():
        try:
            out += hooks_json_problems(json.loads(hj.read_text(encoding="utf-8")), root)
        except ValueError as e:
            out.append(f"plugin: hooks.json is not valid JSON: {e}")
    return out


# What a harness may put in the tool loop. Rules can only ask or refuse; an
# `overwrite` rule would rewrite every matching tool call's arguments in every
# later session, which is too much power for text an editor wrote from a
# transcript that may carry injected instructions.
HOOK_ACTIONS = {"warn", "ask", "block", "deny"}
HOOK_RULE_KEYS = {
    "name",
    "enabled",
    "event",
    "tool",
    "matcher",
    "action",
    "conditions",
    "pattern",
    "message",
}
GUARDRAIL_KEYS = {"generative_image_tools", "stop_nag_limit"}


def hook_rule_problems(root: Path) -> List[str]:
    out: List[str] = []
    hr = root / "hookify-rules.json"
    if hr.exists():
        try:
            doc = json.loads(hr.read_text(encoding="utf-8"))
        except ValueError:
            return out
        rules = doc.get("rules") if isinstance(doc, dict) else None
        if not isinstance(rules, list):
            out.append('hook rules: hookify-rules.json must be {"rules": [...]}')
            rules = []
        for i, r in enumerate(rules):
            if not isinstance(r, dict):
                out.append(f"hook rules: rule {i} must be an object")
                continue
            name = str(r.get("name", ""))
            if not name.startswith("harness2-"):
                out.append(
                    f"hook rules: rule {i} name {name!r} must start with harness2-"
                )
            action = str(r.get("action", "warn")).lower()
            if action not in HOOK_ACTIONS:
                out.append(
                    f"hook rules: {name or i} action {action!r} is not allowed (only {', '.join(sorted(HOOK_ACTIONS))})"
                )
            extra = set(r) - HOOK_RULE_KEYS
            if extra:
                out.append(
                    f"hook rules: {name or i} has unsupported keys {sorted(extra)} (no overwrite/rewrite)"
                )
    gr = root / "guardrails.json"
    if gr.exists():
        try:
            g = json.loads(gr.read_text(encoding="utf-8"))
        except ValueError:
            return out
        if not isinstance(g, dict):
            out.append("guardrails: guardrails.json must be an object")
        else:
            extra = set(g) - GUARDRAIL_KEYS
            if extra:
                out.append(f"guardrails: unknown keys {sorted(extra)}")
            n = g.get("stop_nag_limit", 2)
            if not isinstance(n, int) or isinstance(n, bool) or not 0 <= n <= 5:
                out.append(
                    "guardrails: stop_nag_limit must be a whole number from 0 to 5"
                )
    return out


def symlink_problems(root: Path) -> List[str]:
    """A symlink in a proposal could pull any file (a secret) into always-on text."""
    out = []
    for p in sorted(root.rglob("*")):
        if p.is_symlink():
            out.append(
                f"plugin: {p.relative_to(root)} is a symlink; a harness tree holds only regular files"
            )
    return out


def _handler_problems(h, at: str, root: Optional[Path]) -> List[str]:
    if not isinstance(h, dict):
        return [f"hooks.json {at}: a handler must be an object"]
    out = []
    if "hooks" in h or "matcher" in h:
        out.append(f"hooks.json {at}: a handler, but has hooks/matcher (a group)")
    if "type" in h and h["type"] != "command":
        out.append(f'hooks.json {at}: type must be "command"')
    cmd = h.get("command")
    if not isinstance(cmd, str) or not cmd.strip():
        out.append(f"hooks.json {at}: needs a command string")
    elif (
        root is not None
        and cmd.startswith("./")
        and not (root / cmd.split()[0]).exists()
    ):
        out.append(f"hooks.json {at}: {cmd} does not exist")
    t = h.get("timeout")
    if t is not None and not (isinstance(t, int) and not isinstance(t, bool) and t > 0):
        out.append(
            f"hooks.json {at}: timeout must be a positive whole number of seconds"
        )
    return out


def hooks_json_problems(doc, root: Optional[Path] = None) -> List[str]:
    """Mirrors //apps/desktop/antigravity:hooks_json_test's shape check."""
    if not isinstance(doc, dict):
        return ["hooks.json must be an object of named hook sets"]
    out: List[str] = []
    for set_name, events in doc.items():
        if not isinstance(events, dict):
            out.append(f"hooks.json {set_name}: must map event names to lists")
            continue
        for event, lst in events.items():
            at = f"{set_name}.{event}"
            if event == "enabled":
                continue
            if event not in GROUPED and event not in FLAT:
                out.append(f"hooks.json {at}: unknown event")
                continue
            if not isinstance(lst, list) or not lst:
                out.append(f"hooks.json {at}: must be a non-empty list")
                continue
            for i, entry in enumerate(lst):
                where = f"{at}[{i}]"
                if event in FLAT:
                    out += _handler_problems(entry, where, root)
                    continue
                hooks = entry.get("hooks") if isinstance(entry, dict) else None
                if not isinstance(hooks, list):
                    out.append(
                        f"hooks.json {where}: {event} takes groups with matcher and hooks"
                    )
                    continue
                m = entry.get("matcher")
                if m is not None and m != "*":
                    try:
                        re.compile(m)
                    except (re.error, TypeError):
                        out.append(f"hooks.json {where}: matcher is not a valid regex")
                if not hooks:
                    out.append(f"hooks.json {where}: hooks is empty")
                for j, h in enumerate(hooks):
                    out += _handler_problems(h, f"{where}.hooks[{j}]", root)
    return out


def validate_library(root: Path) -> List[str]:
    """Index rows point at entries; every entry has a parseable EXPERIENCE.md."""
    from library import load_index, parse_experience

    root = Path(root)
    if not root.exists():
        return []
    problems = []
    idx = load_index(root)
    ids = set()
    for e in idx["entries"]:
        eid = e.get("id", "")
        ids.add(eid)
        if not (root / e.get("path", eid)).is_dir():
            problems.append(f"library: index entry {eid!r} has no folder")
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        exp = d / "EXPERIENCE.md"
        if not exp.is_file():
            problems.append(f"library: {d.name}/ has no EXPERIENCE.md")
            continue
        parsed = parse_experience(exp.read_text(encoding="utf-8", errors="replace"))
        if parsed["experience"] is None and "NO_ENTRY" not in exp.read_text(
            encoding="utf-8", errors="replace"
        ):
            problems.append(
                f"library: {d.name}/EXPERIENCE.md has neither an <experience> entry nor NO_ENTRY"
            )
        if d.name not in ids:
            problems.append(f"library: {d.name}/ is not in index.json")
        if (d / "harness").is_dir():
            problems += [
                f"library: {d.name}/harness: {p}"
                for p in validate_tree(d / "harness")
                if not p.startswith("hooks.json")
            ]
    return problems
