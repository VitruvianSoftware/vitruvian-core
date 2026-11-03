# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Harness² for Antigravity, with Claude Code (Opus) as the harness improver.

  harness2 install [--reseed] [--hookify-src DIR]   install/refresh the live plugin, hookify, wrapper, library
  harness2 status                                   what is installed, enabled, locked and learned
  harness2 validate [DIR]                           the four structural rules (default: the installed plugin + library)
  harness2 library                                  Continual Improvement Library entries
  harness2 distill [CONVERSATION|TRANSCRIPT] [--apply] [--dry-run] [--k N]
                                                    INV + DOM editors -> composer -> validate -> reflector
  harness2 apply RUN_DIR                            adopt a distill/probe proposal
  harness2 probe "TASK" [--workspace DIR] [--apply] teacher-student probe for a task
  harness2 lock CONVERSATION FILE... [--no-generative-image] [--size WxH]
  harness2 unlock CONVERSATION [FILE...]

Run it as `bazel run //tools/harness2 -- <command>` from the repo, or as
`harness2 <command>` once installed (~/.local/bin/harness2).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import difflib
import json
import os
import shutil
import subprocess
import sys
import threading
from pathlib import Path
from typing import Dict, List, Optional, Tuple

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import library  # noqa: E402
import prompts  # noqa: E402
import runtime_hooks  # noqa: E402
import trajectory  # noqa: E402
import validator  # noqa: E402
from common import (  # noqa: E402
    antigravity_home,
    gemini_config,
    harness2_home,
    library_dir,
    plugin_dir,
    read_json,
    runs_dir,
    safe_id,
    state_dir,
)

SURFACE = (
    "rules",
    "skills",
    "scripts",
    "sub_agents",
    "guardrails.json",
    "hookify-rules.json",
)
OWNED_SKILL = "skills/harness2"


# ---- harness trees -----------------------------------------------------------


def copy_surface(src: Path, dst: Path) -> None:
    """Copies the editable surface of a harness tree (not its code)."""
    dst.mkdir(parents=True, exist_ok=True)
    for rel in SURFACE:
        s = src / rel
        if s.is_dir():
            shutil.copytree(
                s,
                dst / rel,
                symlinks=True,  # kept as links, so the validator can reject them
                dirs_exist_ok=True,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
            )
        elif s.is_file() or s.is_symlink():
            shutil.copyfile(s, dst / rel, follow_symlinks=False)


def tree_files(root: Path) -> Dict[str, Path]:
    out = {}
    for rel in SURFACE:
        p = root / rel
        if p.is_file():
            out[rel] = p
        elif p.is_dir():
            for f in p.rglob("*"):
                if f.is_file() and not f.is_symlink() and "__pycache__" not in f.parts:
                    out[str(f.relative_to(root))] = f
    return out


def diff_trees(base: Path, new: Path) -> Tuple[List[str], str]:
    a, b = tree_files(base), tree_files(new)
    changed, chunks = [], []
    for rel in sorted(set(a) | set(b)):
        ta = (
            a[rel].read_text(encoding="utf-8", errors="replace").splitlines(True)
            if rel in a
            else []
        )
        tb = (
            b[rel].read_text(encoding="utf-8", errors="replace").splitlines(True)
            if rel in b
            else []
        )
        if ta != tb:
            kind = "added" if rel not in a else "removed" if rel not in b else "changed"
            changed.append(f"{kind}: {rel}")
            chunks.append(
                "".join(difflib.unified_diff(ta, tb, f"base/{rel}", f"new/{rel}"))
            )
    return changed, "\n".join(chunks)


# ---- Claude sessions ---------------------------------------------------------


# Environment a session keeps: enough to run and authenticate Claude Code,
# nothing else (no GH_TOKEN, cloud credentials or other secrets).
_ENV_KEEP = (
    "HOME",
    "PATH",
    "USER",
    "LOGNAME",
    "SHELL",
    "TMPDIR",
    "LANG",
    "LC_ALL",
    "TERM",
)
_ENV_KEEP_PREFIX = ("ANTHROPIC_", "CLAUDE_CODE_", "CLAUDE_CONFIG_DIR")
# Tools a session may use, each scoped by claude_command(): read anywhere it
# is given, edit only inside its own folder. No shell, web, subagents or MCP.
SESSION_DENIED = (
    "Bash",
    "WebFetch",
    "WebSearch",
    "Task",
    "NotebookEdit",
    "KillShell",
    "BashOutput",
    "mcp__*",
)


def session_env() -> Dict[str, str]:
    return {
        k: v
        for k, v in os.environ.items()
        if k in _ENV_KEEP or k.startswith(_ENV_KEEP_PREFIX)
    }


def _abs_variants(path: str) -> List[str]:
    """Both spellings of a path (macOS /tmp is a symlink to /private/tmp)."""
    a, r = os.path.abspath(path), os.path.realpath(path)
    return [a] if a == r else [a, r]


def claude_command(
    exe: str, model: str, cwd: Path, read_dirs: Optional[List[str]] = None
) -> List[str]:
    """A confined session: the transcript it reads may carry injected text.

    Default permission mode in print mode denies anything not allowed below;
    edits are allowed only under `cwd`; `read_dirs` are readable, not
    writable; user/project settings (and so plugins, their MCP servers and
    hooks) are not loaded; no MCP server is configured."""
    allowed: List[str] = []
    for d in _abs_variants(str(cwd)):
        for tool in ("Read", "Glob", "Grep", "LS", "Edit", "Write", "MultiEdit"):
            allowed.append(f"{tool}(/{d}/**)")
    for rd in read_dirs or []:
        for d in _abs_variants(rd):
            allowed += [
                f"Read(/{d}/**)",
                f"Glob(/{d}/**)",
                f"Grep(/{d}/**)",
                f"LS(/{d}/**)",
            ]
    return [
        exe,
        "--model",
        model,
        "-p",
        "--output-format",
        "text",
        "--permission-mode",
        "default",
        "--setting-sources",
        "",
        "--strict-mcp-config",
        "--mcp-config",
        '{"mcpServers": {}}',
        "--allowedTools",
        *allowed,
        "--disallowedTools",
        *SESSION_DENIED,
    ]


def run_claude(
    prompt: str,
    cwd: Path,
    model: str,
    timeout: int,
    read_dirs: Optional[List[str]] = None,
) -> str:
    """One confined Claude Code session in `cwd`; returns its final reply."""
    exe = os.environ.get("HARNESS2_CLAUDE", "claude")
    cmd = claude_command(exe, model, cwd, read_dirs)
    (cwd / "prompt.md").write_text(prompt, encoding="utf-8")
    try:
        r = subprocess.run(
            cmd,
            input=prompt,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=timeout,
            env=session_env(),
        )
    except FileNotFoundError:
        raise SystemExit(
            f"harness2: `{exe}` not found; install Claude Code or set HARNESS2_CLAUDE"
        )
    except subprocess.TimeoutExpired:
        (cwd / "reply.md").write_text(
            f"(timed out after {timeout}s)\n", encoding="utf-8"
        )
        return ""
    reply = r.stdout
    (cwd / "reply.md").write_text(
        reply + (f"\n\n(stderr)\n{r.stderr}" if r.returncode else ""), encoding="utf-8"
    )
    if r.returncode != 0:
        print(
            f"  ! claude exited {r.returncode} in {cwd.name}: {r.stderr.strip()[:300]}",
            file=sys.stderr,
        )
    return reply


def notes_of(reply: str) -> str:
    m = library._block(reply, "notes")
    return m if m is not None else reply.strip()


# ---- distill -----------------------------------------------------------------


def _stamp() -> str:
    return _dt.datetime.now().strftime("%Y%m%dT%H%M%S")


def shared_context(ctx: Path, transcript: Path, traj: "trajectory.Trajectory") -> None:
    ctx.mkdir(parents=True, exist_ok=True)
    task = ["# The user's messages, verbatim", ""]
    for step, text in traj.user_messages:
        task += [f"## step {step}", text, ""]
    (ctx / "task.md").write_text("\n".join(task), encoding="utf-8")
    (ctx / "trajectory.md").write_text(trajectory.summarize(traj), encoding="utf-8")
    shutil.copyfile(transcript, ctx / "transcript.jsonl")
    lib = library_dir()
    if lib.is_dir():
        shutil.copytree(lib, ctx / "library", dirs_exist_ok=True)


def new_session(
    run: Path, name: str, transcript: Path, traj, harness_from: Path
) -> Path:
    s = run / name
    shared_context(s / "context", transcript, traj)
    copy_surface(harness_from, s / "context" / "harness")
    return s


def distill(args) -> int:
    transcript = trajectory.resolve_transcript(args.conversation)
    traj = trajectory.load(transcript)
    conv = (
        transcript.parent.parent.parent.name
        if transcript.name == "transcript.jsonl"
        else transcript.stem
    )
    run = runs_dir() / f"{_stamp()}-distill-{safe_id(conv)[:8]}"
    run.mkdir(parents=True, exist_ok=True)
    base = run / "base_harness"
    copy_surface(plugin_dir(), base)
    print(
        f"harness2 distill: {transcript}\n  {len(traj.user_messages)} user turns, {len(traj.tool_steps)} tool calls; run dir {run}"
    )
    budget = validator.MAX_ALWAYS_ON_CHARS

    # Stage 1: k INV and k DOM editors, in parallel, each on its own copy.
    labels = [(f"{d}-{i}", d, i) for d in ("inv", "dom") for i in range(1, args.k + 1)]
    sessions = {
        lab: new_session(run, f"editor-{lab}", transcript, traj, base)
        for lab, _, _ in labels
    }
    for lab, d, i in labels:
        (sessions[lab] / "prompt.md").write_text(
            prompts.editor_prompt(d, i, args.k, budget), encoding="utf-8"
        )
    if args.dry_run:
        compose = new_session(run, "composer", transcript, traj, base)
        (compose / "prompt.md").write_text(
            prompts.composer_prompt(args.k, budget), encoding="utf-8"
        )
        (run / "reflector-prompt.md").write_text(
            prompts.reflector_prompt(), encoding="utf-8"
        )
        print(
            f"  dry run: prompts and contexts written under {run}; no Claude session started"
        )
        return 0

    replies: Dict[str, str] = {}

    def work(lab: str, d: str, i: int) -> None:
        print(f"  editor {lab}: running claude --model {args.model} …")
        replies[lab] = run_claude(
            prompts.editor_prompt(d, i, args.k, budget),
            sessions[lab],
            args.model,
            args.timeout,
        )

    threads = [threading.Thread(target=work, args=t) for t in labels]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    # Stage 2: compose from base + candidates; validate; retry once with the validator's message.
    compose = new_session(run, "composer", transcript, traj, base)
    ctx = compose / "context"
    copy_surface(base, ctx / "base_harness")
    for lab, _, _ in labels:
        cdir = ctx / "candidates" / lab
        copy_surface(sessions[lab] / "context" / "harness", cdir / "harness")
        problems = validator.validate_tree(cdir / "harness")
        note = notes_of(replies.get(lab, ""))
        if problems:
            note += (
                "\n\n(validator: this candidate FAILS validation as written)\n- "
                + "\n- ".join(problems)
            )
        (cdir / "notes.md").write_text(note + "\n", encoding="utf-8")
    print("  composer: running …")
    reply = run_claude(
        prompts.composer_prompt(args.k, budget), compose, args.model, args.timeout
    )
    final = ctx / "harness"
    problems = validator.validate_tree(final)
    fallback = False
    if problems:
        print(
            "  composer harness failed validation; retrying once with the validator's message"
        )
        reply = run_claude(
            prompts.composer_prompt(args.k, budget, "\n".join(problems)),
            compose,
            args.model,
            args.timeout,
        )
        problems = validator.validate_tree(final)
    if problems:
        fallback = True
        print("  still invalid: inheriting the base harness (fallback recorded)")
        shutil.rmtree(final)
        copy_surface(base, final)
    composer_notes = notes_of(reply)
    changed, patch = diff_trees(base, final)
    (run / "composer_notes.md").write_text(composer_notes + "\n", encoding="utf-8")
    (run / "harness.diff").write_text(patch, encoding="utf-8")

    # Stage 3: experience reflector.
    refl = run / "reflector"
    shared_context(refl / "context", transcript, traj)
    copy_surface(base, refl / "context" / "base_harness")
    copy_surface(final, refl / "context" / "adopted")
    shutil.copytree(ctx / "candidates", refl / "context" / "candidates")
    (refl / "context" / "composer_notes.md").write_text(
        composer_notes + "\n", encoding="utf-8"
    )
    print("  experience reflector: running …")
    rreply = run_claude(prompts.reflector_prompt(), refl, args.model, args.timeout)
    parsed = library.parse_experience(rreply)
    title = (parsed["experience"] or {}).get("cue", "") or f"distill of {conv}"
    exp_md = library.render_experience(
        parsed, title[:100], f"Antigravity conversation {conv}; run {run.name}"
    )
    (run / "EXPERIENCE.md").write_text(exp_md, encoding="utf-8")

    result = {
        "conversation": conv,
        "transcript": str(transcript),
        "final": str(final),
        "changed": changed,
        "fallback_to_base": fallback,
        "experience": parsed["experience"],
        "kind": "distill",
    }
    (run / "result.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"\n  composer notes:\n    " + "\n    ".join(composer_notes.splitlines()[:40])
    )
    print(
        f"\n  changes ({len(changed)}): "
        + ("\n    " + "\n    ".join(changed) if changed else "none (KEEP_BASE)")
    )
    if parsed["experience"]:
        print(f"  lesson: {parsed['experience'].get('lesson', '')}")
    else:
        print("  reflector: NO_ENTRY")
    if args.apply:
        return apply_run(run)
    print(
        f"\n  proposal only. Review {run / 'harness.diff'}, then: harness2 apply {run}"
    )
    return 0


def _inside(path: Path, root: Path) -> bool:
    p, r = os.path.realpath(path), os.path.realpath(root)
    return p == r or p.startswith(r + os.sep)


def apply_run(run: Path) -> int:
    """Adopts a proposal all-or-nothing.

    The complete new plugin is built and validated beside the live one, then
    swapped in with two renames; the old tree is kept whole in the run folder.
    Any failure puts the old tree back exactly (files the proposal added go
    too)."""
    run = Path(run)
    res = read_json(run / "result.json", None)
    if not res:
        raise SystemExit(f"harness2: {run} has no result.json")
    final = Path(res["final"])
    if not _inside(final, run):
        raise SystemExit(f"harness2 apply: {final} is not inside {run}; refusing")
    problems = validator.validate_tree(final)
    if problems:
        print(
            "harness2 apply: proposal fails validation; not applied:\n  "
            + "\n  ".join(problems)
        )
        return 1
    dest = plugin_dir()
    swap = harness2_home() / "swap"
    if swap.exists():
        shutil.rmtree(swap)
    swap.mkdir(parents=True)
    staged, previous = swap / "staged", swap / "previous"
    shutil.copytree(dest, staged, symlinks=True)
    for rel in SURFACE:
        d = staged / rel
        if d.is_dir() and not d.is_symlink():
            for child in list(d.iterdir()):
                if rel == "skills" and child.name == "harness2":
                    continue
                shutil.rmtree(
                    child
                ) if child.is_dir() and not child.is_symlink() else child.unlink()
        elif d.exists() or d.is_symlink():
            d.unlink()
    for rel, src in tree_files(final).items():
        if rel.startswith(OWNED_SKILL + "/"):
            continue
        (staged / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, staged / rel)
        if src.suffix in (".py", ".sh") and "scripts" in Path(rel).parts:
            os.chmod(staged / rel, 0o755)
    after = validator.validate_tree(staged)
    if after:
        shutil.rmtree(swap)
        print(
            "harness2 apply: the assembled plugin fails validation; nothing changed:\n  "
            + "\n  ".join(after)
        )
        return 1

    import installer

    os.rename(dest, previous)
    try:
        os.rename(staged, dest)
        installer.merge_hookify_rules(dest)
    except BaseException:
        if dest.exists():
            shutil.rmtree(dest)
        os.rename(previous, dest)
        installer.merge_hookify_rules(dest)
        raise
    backup = run / "backup_before_apply"
    if backup.exists():
        shutil.rmtree(backup)
    shutil.move(str(previous), str(backup))
    shutil.rmtree(swap, ignore_errors=True)
    if res.get("kind") == "distill" and (run / "EXPERIENCE.md").is_file():
        title = (res.get("experience") or {}).get("cue") or res.get(
            "conversation", "distill"
        )
        row = library.add_entry(
            (run / "EXPERIENCE.md").read_text(encoding="utf-8"), final, title
        )
        print(f"harness2 apply: library entry {row['id']}")
    print(
        f"harness2 apply: adopted {len(res.get('changed', []))} change(s) into {dest} (previous plugin kept in {backup})"
    )
    return 0


# ---- probe -------------------------------------------------------------------


def probe(args) -> int:
    run = runs_dir() / f"{_stamp()}-probe"
    s = run / "probe"
    ctx = s / "context"
    ctx.mkdir(parents=True, exist_ok=True)
    ws = (
        os.path.abspath(os.path.expanduser(args.workspace))
        if args.workspace
        else os.getcwd()
    )
    (ctx / "task.md").write_text(
        f"# Task\n\n{args.task}\n\nWorkspace: {ws}\n", encoding="utf-8"
    )
    if library_dir().is_dir():
        shutil.copytree(library_dir(), ctx / "library", dirs_exist_ok=True)
    base = run / "base_harness"
    copy_surface(plugin_dir(), base)
    copy_surface(base, ctx / "harness")
    budget = validator.MAX_ALWAYS_ON_CHARS
    if args.dry_run:
        (s / "prompt.md").write_text(prompts.probe_prompt(budget), encoding="utf-8")
        print(f"harness2 probe: dry run; prompt and context under {run}")
        return 0
    print(
        f"harness2 probe: claude --model {args.model} is solving the task on paper and auditing the harness …"
    )
    reply = run_claude(
        prompts.probe_prompt(budget), s, args.model, args.timeout, read_dirs=[ws]
    )
    final = ctx / "harness"
    problems = validator.validate_tree(final)
    if problems:
        fb = (
            prompts.probe_prompt(budget)
            + "\n# YOUR PREVIOUS ATTEMPT FAILED VALIDATION\n\nFix exactly these, in place:\n"
            + "\n".join(problems)
            + "\n"
        )
        reply = run_claude(fb, s, args.model, args.timeout, read_dirs=[ws])
        problems = validator.validate_tree(final)
    fallback = bool(problems)
    if fallback:
        shutil.rmtree(final)
        copy_surface(base, final)
    changed, patch = diff_trees(base, final)
    (run / "harness.diff").write_text(patch, encoding="utf-8")
    (run / "result.json").write_text(
        json.dumps(
            {
                "kind": "probe",
                "task": args.task,
                "final": str(final),
                "changed": changed,
                "fallback_to_base": fallback,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print("  notes:\n    " + "\n    ".join(notes_of(reply).splitlines()[:40]))
    print(
        f"  changes ({len(changed)}): "
        + ("\n    " + "\n    ".join(changed) if changed else "none (KEEP_BASE)")
    )
    if args.apply and changed:
        return apply_run(run)
    if changed:
        print(f"  proposal only: harness2 apply {run}")
    return 0


# ---- locks, status, library, validate ----------------------------------------


def lock(args) -> int:
    with runtime_hooks.state_lock(args.conversation):
        st = runtime_hooks.load_state(args.conversation)
        for f in args.files:
            if f not in st["locks"]:
                st["locks"].append(f)
        if args.no_generative_image:
            st["no_generative_image_edit"] = True
        if args.size:
            w, h = (int(x) for x in args.size.lower().split("x"))
            for f in args.files:
                inv = {"pattern": f, "width": w, "height": h}
                if inv not in st["image_invariants"]:
                    st["image_invariants"].append(inv)
        runtime_hooks.save_state(st)
    print(
        json.dumps(
            {
                k: st[k]
                for k in (
                    "conversationId",
                    "locks",
                    "no_generative_image_edit",
                    "image_invariants",
                )
            },
            indent=2,
        )
    )
    return 0


def unlock(args) -> int:
    with runtime_hooks.state_lock(args.conversation):
        st = runtime_hooks.load_state(args.conversation)
        if args.files:
            st["locks"] = [x for x in st["locks"] if x not in args.files]
            st["image_invariants"] = [
                i for i in st["image_invariants"] if i["pattern"] not in args.files
            ]
        else:
            st.update(
                locks=[],
                no_generative_image_edit=False,
                deterministic_image_edit=False,
                image_invariants=[],
            )
        runtime_hooks.save_state(st)
    print(
        json.dumps(
            {
                k: st[k]
                for k in (
                    "conversationId",
                    "locks",
                    "no_generative_image_edit",
                    "image_invariants",
                )
            },
            indent=2,
        )
    )
    return 0


def status(_args) -> int:
    p = plugin_dir()
    cfg = read_json(gemini_config() / "config.json", {}) or {}
    plugins = cfg.get("plugins", {}) if isinstance(cfg, dict) else {}

    def on(n: str) -> str:
        return (
            "enabled"
            if (plugins.get(n) or {}).get("enabled") is True
            else "NOT enabled"
        )

    print("Harness² status")
    print(
        f"  plugin      {p} ({'installed' if (p / 'hooks.json').is_file() else 'NOT installed'}, {on('harness2')})"
    )
    hooks = read_json(p / "hooks.json", {}) or {}
    events = sorted({e for s in hooks.values() if isinstance(s, dict) for e in s})
    print(f"  hooks       {', '.join(events) or 'none'}")
    hk = gemini_config() / "plugins" / "hookify"
    print(
        f"  hookify     {hk} ({'installed' if (hk / 'hooks.json').is_file() else 'NOT installed'}, {on('hookify')})"
    )
    rules = read_json(antigravity_home() / "hookify-rules.json", {}) or {}
    names = (
        [r.get("name") for r in rules.get("rules", [])]
        if isinstance(rules, dict)
        else []
    )
    print(
        f"  hookify rules  {len(names)} ({sum(1 for n in names if str(n).startswith('harness2-'))} from harness2)"
    )
    w = shutil.which("harness2")
    print(f"  wrapper     {w or 'not on PATH (~/.local/bin/harness2)'}")
    on_files = validator.always_on_files(p)
    chars = sum(len(f.read_text(encoding="utf-8", errors="replace")) for f in on_files)
    print(
        f"  always-on   {len(on_files)} file(s), {chars}/{validator.MAX_ALWAYS_ON_CHARS} chars (~{chars // 4} tokens)"
    )
    skills = (
        sorted(d.name for d in (p / "skills").glob("*") if d.is_dir())
        if (p / "skills").is_dir()
        else []
    )
    print(f"  skills      {', '.join(skills) or 'none'}")
    active = []
    if state_dir().is_dir():
        for f in sorted(state_dir().glob("*.json")):
            st = read_json(f, {}) or {}
            if (
                st.get("locks")
                or st.get("no_generative_image_edit")
                or st.get("image_invariants")
            ):
                active.append(
                    f"{st.get('conversationId')}: locks={st.get('locks')} no_gen={st.get('no_generative_image_edit')} sizes={st.get('image_invariants')}"
                )
    print(
        f"  locks       {len(active)} conversation(s)"
        + ("".join(f"\n    {a}" for a in active[-10:]))
    )
    entries = library.load_index(library_dir())["entries"]
    print(
        f"  library     {len(entries)} entr{'y' if len(entries) == 1 else 'ies'} in {library_dir()}"
    )
    ev = harness2_home() / "events.jsonl"
    if ev.is_file():
        tail = ev.read_text(encoding="utf-8", errors="replace").splitlines()[-5:]
        print("  recent hook events:" + "".join(f"\n    {line[:200]}" for line in tail))
    return 0


def show_library(_args) -> int:
    entries = library.load_index(library_dir())["entries"]
    if not entries:
        print(f"library is empty ({library_dir()})")
    for e in entries:
        print(
            f"{e['id']}  [{e.get('confidence', '').split(' ')[0] or '?'}]\n  cue:    {e.get('cue')}\n  lesson: {e.get('lesson')}\n"
        )
    return 0


def validate(args) -> int:
    root = Path(args.dir) if args.dir else plugin_dir()
    problems = validator.validate_tree(root)
    if not args.dir:
        problems += validator.validate_library(library_dir())
    if problems:
        print(f"INVALID ({len(problems)}):\n  " + "\n  ".join(problems))
        return 1
    print(
        f"valid: {root}"
        + ("" if args.dir else f" and {library_dir()}")
        + " pass rules 1-4"
    )
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="harness2", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("install", help="install or refresh the live plugin")
    p.add_argument(
        "--reseed",
        action="store_true",
        help="overwrite the evolved harness with the seed (backs it up first)",
    )
    p.add_argument(
        "--hookify-src",
        help="hookify plugin folder (default: the repo's, under bazel run)",
    )
    p.add_argument(
        "--no-prewarm", action="store_true", help="do not build hookify's Rust hook now"
    )

    sub.add_parser("status")
    sub.add_parser("library")
    p = sub.add_parser("validate")
    p.add_argument("dir", nargs="?")

    for name in ("distill", "probe"):
        p = sub.add_parser(name)
        if name == "distill":
            p.add_argument(
                "conversation",
                nargs="?",
                help="conversation id or transcript path (default: newest)",
            )
            p.add_argument(
                "--k", type=int, default=1, help="candidates per dimension (paper: k)"
            )
        else:
            p.add_argument("task")
            p.add_argument(
                "--workspace", help="the folder the task runs in (default: cwd)"
            )
        p.add_argument("--apply", action="store_true")
        p.add_argument(
            "--dry-run",
            action="store_true",
            help="write the run folder and prompts; start no session",
        )
        p.add_argument("--model", default=os.environ.get("HARNESS2_MODEL", "opus"))
        p.add_argument(
            "--timeout", type=int, default=1800, help="seconds per Claude session"
        )

    p = sub.add_parser("apply")
    p.add_argument("run")
    p = sub.add_parser("lock")
    p.add_argument("conversation")
    p.add_argument("files", nargs="*")
    p.add_argument("--no-generative-image", action="store_true")
    p.add_argument("--size", help="WxH every locked/listed PNG must have at Stop")
    p = sub.add_parser("unlock")
    p.add_argument("conversation")
    p.add_argument("files", nargs="*")

    args = ap.parse_args(argv)
    try:  # progress lines must show up even when redirected to a log
        sys.stdout.reconfigure(line_buffering=True)
    except (AttributeError, ValueError):
        pass
    if args.cmd == "install":
        import installer

        return installer.install(
            reseed=args.reseed,
            hookify_src=args.hookify_src,
            prewarm=not args.no_prewarm,
        )
    return {
        "status": status,
        "library": show_library,
        "validate": validate,
        "distill": distill,
        "probe": probe,
        "apply": lambda a: apply_run(Path(a.run)),
        "lock": lock,
        "unlock": unlock,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
