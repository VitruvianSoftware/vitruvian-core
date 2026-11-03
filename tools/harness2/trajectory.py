# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Reads an Antigravity transcript.jsonl into a trajectory an editor can audit.

A transcript line is one step: USER_INPUT (the user's message, wrapped in
<USER_REQUEST>), PLANNER_RESPONSE (the model's reply and `tool_calls`),
GENERIC (a tool's result), EPHEMERAL_MESSAGE / SYSTEM_MESSAGE (injected
context). Tool arguments are JSON-encoded strings.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, List, Optional

from common import antigravity_home, normalize_args

# Keys that describe a call rather than change what it does.
COSMETIC_ARGS = {"toolSummary", "WaitMsBeforeAsync", "ArtifactMetadata"}

_EXIT = re.compile(r"exited with code (-?\d+)")
_REQUEST = re.compile(r"<USER_REQUEST>\s*(.*?)\s*</USER_REQUEST>", re.S)


@dataclass
class ToolStep:
    step: int
    name: str
    args: dict
    result: str = ""
    failed: bool = False
    result_step: Optional[int] = None


@dataclass
class Trajectory:
    user_messages: List[tuple] = field(default_factory=list)  # (step, text)
    tool_steps: List[ToolStep] = field(default_factory=list)
    replies: List[tuple] = field(default_factory=list)  # (step, text)


def user_text(content: str) -> str:
    """The user's own words: the <USER_REQUEST> body, without metadata."""
    m = _REQUEST.search(content or "")
    if m:
        return m.group(1).strip()
    return (content or "").split("<ADDITIONAL_METADATA>")[0].strip()


def result_failed(record: dict) -> bool:
    if record.get("error"):
        return True
    if record.get("status") not in (None, "DONE"):
        return True
    content = record.get("content") or ""
    m = _EXIT.search(content)
    if m and m.group(1) != "0":
        return True
    head = content.lstrip()[:200].lower()
    return (
        head.startswith("error")
        or "traceback (most recent call last)" in content[:4000].lower()
    )


def iter_records(lines: Iterable[str]):
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if isinstance(rec, dict):
            yield rec


def parse(lines: Iterable[str]) -> Trajectory:
    traj = Trajectory()
    pending: List[ToolStep] = []
    for rec in iter_records(lines):
        kind = rec.get("type")
        step = rec.get("step_index", -1)
        if kind == "USER_INPUT":
            traj.user_messages.append((step, user_text(rec.get("content", ""))))
        elif kind == "PLANNER_RESPONSE":
            if rec.get("content"):
                traj.replies.append((step, rec["content"]))
            for call in rec.get("tool_calls") or []:
                ts = ToolStep(
                    step, call.get("name", ""), normalize_args(call.get("args"))
                )
                traj.tool_steps.append(ts)
                pending.append(ts)
        elif kind == "GENERIC" and pending:
            ts = pending.pop(0)
            ts.result = rec.get("content") or rec.get("error") or ""
            ts.failed = result_failed(rec)
            ts.result_step = step
    return traj


def load(path: Path) -> Trajectory:
    with open(path, encoding="utf-8", errors="replace") as f:
        return parse(f)


def call_key(name: str, args: dict) -> str:
    """Identity of a call, ignoring cosmetic arguments."""
    core = {k: v for k, v in normalize_args(args).items() if k not in COSMETIC_ARGS}
    return name + "\x00" + json.dumps(core, sort_keys=True, default=str)


def describe_args(name: str, args: dict, width: int = 160) -> str:
    for key in ("CommandLine", "Path", "TypeName", "query", "Action", "Recipient"):
        if key in args:
            text = str(args[key])
            break
    else:
        text = json.dumps(args, default=str)
    text = " ".join(text.split())
    return text if len(text) <= width else text[: width - 1] + "…"


def summarize(traj: Trajectory, max_chars: int = 60000) -> str:
    """A markdown digest: user turns, every tool call and its outcome, replies."""
    events = []
    for step, text in traj.user_messages:
        events.append((step, 0, f"\n### step {step} USER\n{text}\n"))
    for ts in traj.tool_steps:
        outcome = "FAILED" if ts.failed else "ok"
        first = (ts.result or "").strip().splitlines()
        tail = ""
        if ts.failed and first:
            tail = " :: " + " | ".join(line.strip() for line in first[-3:])[:240]
        extra = ""
        if ts.name == "invoke_subagent":
            extra = f" [TypeName={ts.args.get('TypeName')}]"
        events.append(
            (
                ts.step,
                1,
                f"- step {ts.step} `{ts.name}`{extra} {describe_args(ts.name, ts.args)} -> {outcome}{tail}",
            )
        )
    for step, text in traj.replies:
        short = " ".join(text.split())
        events.append((step, 2, f"- step {step} ASSISTANT: {short[:400]}"))
    events.sort(key=lambda e: (e[0], e[1]))

    counts = Counter(ts.name for ts in traj.tool_steps)
    fails = sum(1 for ts in traj.tool_steps if ts.failed)
    repeats = Counter(call_key(ts.name, ts.args) for ts in traj.tool_steps)
    repeated = sum(1 for n in repeats.values() if n > 1)
    head = [
        "# Trajectory digest",
        f"user turns: {len(traj.user_messages)}; tool calls: {len(traj.tool_steps)} "
        f"({', '.join(f'{k}={v}' for k, v in counts.most_common())}); failed calls: {fails}; "
        f"identical calls repeated: {repeated}",
    ]
    body = "\n".join(e[2] for e in events)
    text = "\n".join(head) + "\n" + body
    if len(text) > max_chars:
        text = (
            text[: max_chars - 80]
            + "\n\n…(digest truncated; read transcript.jsonl for the rest)\n"
        )
    return text


def last_user_input_from_file(path: Path, chunk: int = 262144) -> str:
    """The latest USER_INPUT in a transcript, reading backwards from the end."""
    try:
        size = path.stat().st_size
    except OSError:
        return ""
    with open(path, "rb") as f:
        read = min(size, chunk)
        while True:
            f.seek(size - read)
            lines = f.read(read).decode("utf-8", errors="replace").splitlines()
            if read < size:
                lines = lines[1:]  # first line may be cut
            for rec in reversed(list(iter_records(lines))):
                if rec.get("type") == "USER_INPUT":
                    return user_text(rec.get("content", ""))
            if read >= size:
                return ""
            read = min(size, read * 4)


def last_tool_step_from_file(path: Path, chunk: int = 262144) -> Optional[ToolStep]:
    """The most recent tool call that has a result, from the transcript's tail."""
    try:
        size = path.stat().st_size
        with open(path, "rb") as f:
            f.seek(max(0, size - chunk))
            lines = f.read().decode("utf-8", errors="replace").splitlines()
    except OSError:
        return None
    if size > chunk:
        lines = lines[1:]
    traj = parse(lines)
    done = [ts for ts in traj.tool_steps if ts.result_step is not None]
    return done[-1] if done else None


def resolve_transcript(ref: Optional[str]) -> Path:
    """A transcript path, a conversation id, or (None) the newest conversation."""
    brain = antigravity_home() / "brain"
    if ref:
        p = Path(ref).expanduser()
        if p.is_file():
            return p
        if p.is_dir() and (p / ".system_generated/logs/transcript.jsonl").is_file():
            return p / ".system_generated/logs/transcript.jsonl"
        cand = brain / ref / ".system_generated/logs/transcript.jsonl"
        if cand.is_file():
            return cand
        raise FileNotFoundError(f"no transcript for {ref!r} (looked for {cand})")
    found = sorted(
        brain.glob("*/.system_generated/logs/transcript.jsonl"),
        key=lambda p: p.stat().st_mtime,
    )
    if not found:
        raise FileNotFoundError(f"no transcripts under {brain}")
    return found[-1]
