# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Harness²'s live Antigravity hooks: the PLUGIN component (C8).

  runtime_hooks.py pre-invocation   < payload   -> {"injectSteps": [...]} or {}
  runtime_hooks.py pre-tool-use     < payload   -> {"decision": "allow"|"deny", ...}
  runtime_hooks.py stop             < payload   -> {"decision": "allow"|"continue", ...}

PreInvocation reads the user's latest message, records hard constraints in
per-conversation state (state/<conversationId>.json) and, once per new
message, pins them plus any matching library lessons right before the turn.
PreToolUse enforces that state inside the tool loop, where the model cannot
skip it. Stop checks the finished turn against it.

Every entry point prints valid JSON and exits 0 whatever goes wrong: a
PreToolUse answer without a "decision" would let the call through silently,
so the failure answer is an explicit allow (fail open, logged).
"""

from __future__ import annotations

import contextlib
import datetime as _dt
import fcntl
import fnmatch
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import traceback
from pathlib import Path
from typing import List, Optional

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import constraints  # noqa: E402
import library  # noqa: E402
import trajectory  # noqa: E402
from common import (
    harness2_home,
    library_dir,
    normalize_args,
    plugin_dir,
    read_json,
    safe_id,
    state_dir,
    write_json,
)  # noqa: E402

WRITE_TOOLS = {
    "write_file",
    "edit_file",
    "write_to_file",
    "replace_file_content",
    "multi_replace_file_content",
    "notebook_edit",
    "Write",
    "Edit",
    "MultiEdit",
}
SHELL_TOOLS = {"run_command", "shell_exec", "Bash"}
PATH_KEYS = (
    "Path",
    "TargetFile",
    "AbsolutePath",
    "FilePath",
    "file_path",
    "path",
    "target_file",
)
COMMAND_KEYS = ("CommandLine", "command", "cmd")
# A shell command that names a locked file AND does one of these writes it.
_WRITE_CMD = re.compile(
    r"(?:^|[\s;&|(])(?:rm|mv|sips|tee|truncate|dd|touch|install|ln|convert|magick|mogrify|pngcrush|optipng|chmod|chown)\b"
    r"|\bsed\s+-i|\bperl\s+-[a-z]*i|\bgit\s+(?:checkout|restore|rm|mv|reset|clean|stash)\b|\bunlink\b"
    r"|\bfind\b.*\s-(?:delete|exec)\b"
    r"|open\([^)]*['\"][wa+]b?['\"]|\.save\(|write_bytes|write_text"
    r"|\bos\.(?:remove|unlink|rename|replace|truncate)\b|\bshutil\.(?:copy\w*|move|rmtree)\b"
)
# A redirection and its target: `> f`, `>> f`, `2> f`, `&> f`. Only a redirection
# INTO the locked file writes it (`2>/dev/null` next to a read does not).
_REDIRECT = re.compile(r"(?:\d|&)?>>?\|?\s*(['\"]?)([^\s;&|'\"]+)\1")
# Adopting a harness change or lifting a user's lock is the user's decision.
_USER_ONLY = re.compile(
    r"\bharness2\b[^;&|\n]*?(?:\s(?:apply|unlock)\b|\s--apply\b|\s--reseed\b)"
)
# The harness's own files. The agent may read them; changing them is what
# `harness2 apply` (run by the user) is for.
PROTECTED_MARKERS = (
    ".gemini/config/plugins/harness2",
    ".gemini/config/plugins/hookify",
    ".gemini/antigravity/hookify-rules.json",
    ".gemini/antigravity/harness2/",
)


def _protected(path: str) -> bool:
    norm = os.path.expanduser(path.replace("\\", "/"))
    return any(m in norm for m in PROTECTED_MARKERS)


def _command_writes_protected(cmd: str) -> bool:
    home = os.path.expanduser("~")
    expanded = (
        cmd.replace("~/", home + "/")
        .replace("$HOME/", home + "/")
        .replace("${HOME}/", home + "/")
    )
    for segment in re.split(r"&&|\|\||;|\|", expanded):
        if not any(m in segment for m in PROTECTED_MARKERS):
            continue
        if any(_protected(m.group(2)) for m in _REDIRECT.finditer(segment)):
            return True
        rest = _REDIRECT.sub(" ", segment)
        if not any(m in rest for m in PROTECTED_MARKERS):
            continue
        if _COPY_CMD.match(rest) or re.match(r"^\s*ln\b", rest):
            try:
                parts = [w for w in shlex.split(rest) if not w.startswith("-")]
            except ValueError:
                parts = [w for w in rest.split() if not w.startswith("-")]
            if parts and _protected(parts[-1]):
                return True  # copying ONTO a harness file; copying one out is a read
            continue
        if _WRITE_CMD.search(rest) or re.match(r"^\s*mv\b", rest):
            return True
    return False


_COPY_CMD = re.compile(r"^\s*(?:cp|ditto|rsync|scp)\b")

DEFAULT_GUARDRAILS = {
    "generative_image_tools": [
        {
            "tool": "invoke_subagent",
            "field": "TypeName",
            "pattern": "image-generator|image_generator|imagen|nano-?banana",
        },
        {
            "tool": "generate_image|image_generation|create_image|edit_image",
            "field": "",
            "pattern": "",
        },
    ],
    "stop_nag_limit": 2,
}

INV_0001 = (
    "Harness² Guardrail (INV-0001): Do not use generative AI ('image-generator') to crop, resize, "
    "or remove borders from existing images. Load the 'macos-icon-edit' skill and run its deterministic "
    "Python/sips script instead."
)


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def log_event(kind: str, conv: str, detail: dict) -> None:
    try:
        p = harness2_home() / "events.jsonl"
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(p, "a", encoding="utf-8") as f:
            f.write(
                json.dumps(
                    {"ts": _now(), "event": kind, "conversationId": conv, **detail}
                )
                + "\n"
            )
    except OSError:
        pass


# ---- state -----------------------------------------------------------------


def empty_state(conv: str) -> dict:
    return {
        "conversationId": conv,
        "locks": [],
        "no_generative_image_edit": False,
        "deterministic_image_edit": False,
        "high_alert": False,
        "image_invariants": [],
        "last_input_hash": "",
        "stop_nags": 0,
        "updated_at": _now(),
    }


def state_path(conv: str) -> Path:
    return state_dir() / f"{safe_id(conv)}.json"


def load_state(conv: str) -> dict:
    st = read_json(state_path(conv), None)
    base = empty_state(conv)
    if isinstance(st, dict):
        base.update(st)
    return base


@contextlib.contextmanager
def state_lock(conv: str):
    """Serialises read-modify-write of one conversation's state (the hooks and
    `harness2 lock` can run at the same moment)."""
    path = state_path(conv).with_suffix(".lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def save_state(st: dict) -> None:
    st["updated_at"] = _now()
    write_json(state_path(st["conversationId"]), st)


def apply_signals(st: dict, sig: "constraints.Signals") -> None:
    for f in sig.locks:
        if f not in st["locks"]:
            st["locks"].append(f)
    if sig.no_generative_explicit:
        st["no_generative_image_edit"] = True
    elif sig.generative_ask:
        # A later, explicit ask to generate lifts the earlier "without modifying".
        st["no_generative_image_edit"] = False
    st["deterministic_image_edit"] = sig.deterministic_image_edit
    st["high_alert"] = sig.high_alert
    if sig.sizes and sig.image_files:
        w, h = sig.sizes[-1]
        for f in sig.image_files:
            inv = {"pattern": f, "width": w, "height": h}
            if inv not in st["image_invariants"]:
                st["image_invariants"].append(inv)


def guardrails() -> dict:
    g = read_json(plugin_dir() / "guardrails.json", None)
    out = dict(DEFAULT_GUARDRAILS)
    if isinstance(g, dict):
        out.update(g)
    return out


# ---- PreInvocation -----------------------------------------------------------


def _payload_text(p: dict) -> str:
    for k in ("lastUserInput", "userInput", "userMessage", "prompt", "lastUserMessage"):
        v = p.get(k)
        if isinstance(v, str) and v.strip():
            return trajectory.user_text(v)
        if isinstance(v, dict):
            for kk in ("text", "content", "items"):
                if isinstance(v.get(kk), str):
                    return trajectory.user_text(v[kk])
    tp = p.get("transcriptPath")
    if isinstance(tp, str) and tp:
        return trajectory.last_user_input_from_file(Path(tp))
    return ""


def pre_invocation(p: dict) -> dict:
    conv = str(p.get("conversationId") or "default")
    text = _payload_text(p)
    if not text:
        log_event(
            "pre-invocation",
            conv,
            {"payload_keys": sorted(p), "user_text": "none found"},
        )
        return {}
    digest = hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:16]
    with state_lock(conv):
        st = load_state(conv)
        if st.get("last_input_hash") == digest:
            return {}  # already handled this message; PreInvocation fires every model call
        st["last_input_hash"] = digest
        st["stop_nags"] = 0
        sig = constraints.extract(text)
        apply_signals(st, sig)
        save_state(st)

    lines: List[str] = []
    if st["locks"]:
        lines.append(
            "WRITE-LOCKED by the user for this conversation (any write is refused by a hook): "
            + ", ".join(f"`{x}`" for x in st["locks"])
            + ". Read them if needed; never modify, replace, move or regenerate them."
        )
    if st["no_generative_image_edit"] or st["deterministic_image_edit"]:
        lines.append(
            "This is an edit of EXISTING pixels: crop, scale, pad or remove a border deterministically "
            "(load the `macos-icon-edit` skill). Generative image tools are refused for this request."
        )
    if st["image_invariants"]:
        lines.append(
            "Declared sizes: "
            + ", ".join(
                f"`{i['pattern']}` must be {i['width']}x{i['height']}"
                for i in st["image_invariants"]
            )
            + "."
        )
    if st["high_alert"]:
        lines.append(
            "The user is CORRECTING you. Before any tool call, restate in one line: the target file, the exact "
            "operation, and what must stay untouched. Then do only that; if they asked you to repeat it back, stop and wait."
        )
    matched = library.match(text, library.load_index(library_dir())["entries"])
    for e in matched:
        lines.append(
            f"Library lesson {e['id']} (cue: {e.get('cue', '')}): {e.get('lesson', '')}"
        )
    log_event(
        "pre-invocation",
        conv,
        {
            "payload_keys": sorted(p),
            "locks": st["locks"],
            "deterministic": st["deterministic_image_edit"],
            "no_gen": st["no_generative_image_edit"],
            "high_alert": st["high_alert"],
            "lessons": [e["id"] for e in matched],
        },
    )
    if not lines:
        return {}
    msg = (
        "HARNESS² (pinned from the user's own words and the improvement library):\n- "
        + "\n- ".join(lines)
    )
    return {"injectSteps": [{"ephemeralMessage": msg}]}


# ---- PreToolUse --------------------------------------------------------------


def _matches_lock(path_or_text: str, lock: str) -> bool:
    if not path_or_text:
        return False
    norm = path_or_text.replace("\\", "/")
    base = norm.rsplit("/", 1)[-1]
    if any(ch in lock for ch in "*?["):
        return (
            fnmatch.fnmatch(base, lock)
            or fnmatch.fnmatch(norm, lock)
            or fnmatch.fnmatch(norm, "*/" + lock)
        )
    if "/" in lock:
        return norm.endswith(lock.lstrip("./~")) or norm == lock
    return base == lock


def _command_writes_lock(cmd: str, lock: str) -> bool:
    try:
        words = shlex.split(cmd, posix=True)
    except ValueError:
        words = cmd.split()
    named = [w for w in words if _matches_lock(w.strip("'\";,()"), lock)]
    if not named and not (lock in cmd and not any(ch in lock for ch in "*?[")):
        return False
    for segment in re.split(r"&&|\|\||;|\|", cmd):
        seg_words = segment.split()
        if not any(
            _matches_lock(w.strip("'\";,()"), lock) or lock in w for w in seg_words
        ):
            continue
        if any(_matches_lock(m.group(2), lock) for m in _REDIRECT.finditer(segment)):
            return True
        if re.match(r"^\s*sips\b", segment):
            sw = segment.split()
            if "--out" in sw or "-o" in sw:
                i = sw.index("--out") if "--out" in sw else sw.index("-o")
                if i + 1 < len(sw) and _matches_lock(sw[i + 1].strip("'\""), lock):
                    return True
                continue
            flags = {w for w in sw[1:] if w.startswith("-")}
            if flags and flags <= {"-g", "--getProperty", "-1", "--oneLine"}:
                continue  # sips -g only reads
            return True
        if _COPY_CMD.match(segment):
            try:
                parts = [w for w in shlex.split(segment) if not w.startswith("-")]
            except ValueError:
                parts = [w for w in seg_words if not w.startswith("-")]
            if parts and _matches_lock(parts[-1], lock):
                return True  # copying ONTO the locked file
            continue
        if _WRITE_CMD.search(_REDIRECT.sub(" ", segment)):
            return True
    return False


PROTECTED_REASON = (
    "Harness² Guardrail: the harness's own files (the harness2 and hookify plugins, hookify-rules.json, "
    "~/.gemini/antigravity/harness2/) are changed only by `harness2 apply`, which the user runs after "
    "reading the diff. Propose the change with `harness2 distill` or describe it to the user."
)


def _deny(reason: str, conv: str, tool: str, logged: Optional[str] = None) -> dict:
    """Refuses a call. `logged` replaces the reason in events.jsonl when the
    reason quotes tool output, which may hold secrets."""
    log_event("deny", conv, {"tool": tool, "reason": logged or reason})
    return {"decision": "deny", "reason": reason}


def _is_generative(name: str, args: dict, g: dict) -> bool:
    for spec in g.get("generative_image_tools") or []:
        try:
            if not re.fullmatch(spec.get("tool", ""), name):
                continue
            field = spec.get("field") or ""
            pat = spec.get("pattern") or ""
            if not field or not pat:
                return True
            if re.search(pat, str(args.get(field, "")), re.I):
                return True
        except re.error:
            continue
    return False


def pre_tool_use(p: dict) -> dict:
    tc = p.get("toolCall") if isinstance(p.get("toolCall"), dict) else {}
    name = str(tc.get("name") or p.get("tool_name") or "")
    args = normalize_args(tc.get("args") if tc else p.get("tool_input"))
    conv = str(p.get("conversationId") or "default")
    st = load_state(conv)

    if name in WRITE_TOOLS:
        for k in PATH_KEYS:
            if _protected(str(args.get(k, ""))):
                return _deny(PROTECTED_REASON, conv, name)
    if name in SHELL_TOOLS:
        cmd = next((str(args[k]) for k in COMMAND_KEYS if k in args), "")
        if _command_writes_protected(cmd):
            return _deny(PROTECTED_REASON, conv, name)
    if name in SHELL_TOOLS:
        cmd = next((str(args[k]) for k in COMMAND_KEYS if k in args), "")
        if _USER_ONLY.search(cmd):
            return _deny(
                "Harness² Guardrail: adopting a harness change (`harness2 apply`, `--apply`, `--reseed`) or "
                "lifting a lock (`harness2 unlock`) is the user's decision. Show them the command and the diff, "
                "and let them run it.",
                conv,
                name,
            )

    for lock in st["locks"]:
        if name in WRITE_TOOLS:
            for k in PATH_KEYS:
                if _matches_lock(str(args.get(k, "")), lock):
                    return _deny(
                        f"Harness² Guardrail: File '{lock}' is locked by user negative constraint ('DO NOT TOUCH'). "
                        f"Write somewhere else, or ask the user; unlock with `harness2 unlock {conv}`.",
                        conv,
                        name,
                    )
        if name in SHELL_TOOLS:
            cmd = next((str(args[k]) for k in COMMAND_KEYS if k in args), "")
            if cmd and _command_writes_lock(cmd, lock):
                return _deny(
                    f"Harness² Guardrail: File '{lock}' is locked by user negative constraint ('DO NOT TOUCH'); "
                    f"this command would modify it. Read it, or write to a different file.",
                    conv,
                    name,
                )

    if (
        st["no_generative_image_edit"] or st["deterministic_image_edit"]
    ) and _is_generative(name, args, guardrails()):
        return _deny(INV_0001, conv, name)

    tp = p.get("transcriptPath")
    if isinstance(tp, str) and tp:
        last = trajectory.last_tool_step_from_file(Path(tp))
        if (
            last
            and last.failed
            and trajectory.call_key(last.name, last.args)
            == trajectory.call_key(name, args)
        ):
            tail = " | ".join((last.result or "").strip().splitlines()[-2:])[:300]
            return _deny(
                "Harness² loop guard: this exact call just failed ("
                + tail
                + "). Do not retry it blind. "
                "Decide which it was: bad input, timeout, missing capability, permission, or unread output; "
                "change the input or take one fallback, and stop if that fails too.",
                conv,
                name,
                logged="Harness² loop guard: identical retry of a call that just failed",
            )
    return {"decision": "allow"}


# ---- Stop --------------------------------------------------------------------


def png_size(path: Path) -> Optional[tuple]:
    try:
        with open(path, "rb") as f:
            head = f.read(24)
    except OSError:
        return None
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def _changed_files(ws: Path) -> List[Path]:
    try:
        r = subprocess.run(
            ["git", "-C", str(ws), "status", "--porcelain", "--untracked-files=all"],
            capture_output=True,
            text=True,
            timeout=3,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if r.returncode != 0:
        return []
    out = []
    for line in r.stdout.splitlines():
        rel = line[3:].split(" -> ")[-1].strip().strip('"')
        if rel:
            out.append(ws / rel)
    return out


def stop(p: dict) -> dict:
    conv = str(p.get("conversationId") or "default")
    st = load_state(conv)
    if not st["locks"] and not st["image_invariants"]:
        return {"decision": "allow"}
    limit = int(guardrails().get("stop_nag_limit", 2))
    if st.get("stop_nags", 0) >= limit:
        return {"decision": "allow"}
    workspaces = [
        Path(w) for w in (p.get("workspacePaths") or []) if isinstance(w, str)
    ]
    if not workspaces and p.get("cwd"):
        workspaces = [Path(str(p["cwd"]))]
    problems = []
    for ws in workspaces:
        for f in _changed_files(ws):
            for lock in st["locks"]:
                if _matches_lock(str(f), lock):
                    problems.append(
                        f"locked file {f} has uncommitted changes; restore it (`git -C {ws} restore -- {f}`) unless the user lifted the lock"
                    )
            for inv in st["image_invariants"]:
                if _matches_lock(str(f), inv["pattern"]):
                    size = png_size(f)
                    if size and size != (inv["width"], inv["height"]):
                        problems.append(
                            f"{f} is {size[0]}x{size[1]} but the user asked for {inv['width']}x{inv['height']}"
                        )
    if not problems:
        return {"decision": "allow"}
    with state_lock(conv):
        st = load_state(conv)
        st["stop_nags"] = st.get("stop_nags", 0) + 1
        save_state(st)
    reason = (
        "Harness² stop check: "
        + "; ".join(problems)
        + ". Fix this before finishing, or tell the user why not."
    )
    log_event("stop-continue", conv, {"problems": problems})
    return {"decision": "continue", "reason": reason}


# ---- entry -------------------------------------------------------------------

HANDLERS = {
    "pre-invocation": (pre_invocation, {}),
    "pre-tool-use": (pre_tool_use, {"decision": "allow"}),
    "stop": (stop, {"decision": "allow"}),
}


def run(event: str, raw: str) -> dict:
    handler, fallback = HANDLERS[event]
    try:
        payload = json.loads(raw) if raw.strip() else {}
        if not isinstance(payload, dict):
            payload = {}
        out = handler(payload)
        if event != "pre-invocation" and not isinstance(out.get("decision"), str):
            return dict(fallback)
        return out
    except Exception:  # noqa: BLE001 - a hook must always answer
        try:
            log = harness2_home() / "hooks.log"
            log.parent.mkdir(parents=True, exist_ok=True)
            with open(log, "a", encoding="utf-8") as f:
                f.write(
                    f"{_now()} {event} failed; answering {fallback}\n{traceback.format_exc()}\n"
                )
        except OSError:
            pass
        return dict(fallback)


def main(argv: List[str]) -> int:
    event = argv[1] if len(argv) > 1 else ""
    if event not in HANDLERS:
        print(json.dumps({"decision": "allow"}))
        return 0
    try:
        raw = sys.stdin.read()
    except Exception:  # noqa: BLE001
        raw = ""
    print(json.dumps(run(event, raw)))
    return 0


if __name__ == "__main__":
    os.umask(0o077)
    sys.exit(main(sys.argv))
