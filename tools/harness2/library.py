# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""The Continual Improvement Library (paper §D.2).

One folder per entry under ~/.gemini/antigravity/harness2/library/:
`<NNNN>-<slug>/EXPERIENCE.md` (the Experience Reflector's edit rows and its
one transferable lesson) plus `harness/`, the full adopted tree. Executable
components are kept, not summarised. `index.json` lists every entry with its
cue, lesson and match keywords; the PreInvocation hook matches the user's
message against the cues (harnessing-level recursion).
"""

from __future__ import annotations

import datetime as _dt
import re
import shutil
from pathlib import Path
from typing import List, Optional

from common import library_dir, read_json, write_json

_STOP = set(
    """a an and are as at be been but by can for from has have how if in into is it its
    of on or so that the their then there these this to was were when where which while
    with without would should could must not only own any each every other than same such
    agent user task work harness component""".split()
)
_WORD = re.compile(r"[a-z][a-z0-9\-]{2,}")
_FIELD = re.compile(r"^\s*(cue|lesson|evidence|confidence)\s*:\s*(.*)$", re.I)
_EDIT_KEYS = ("component", "candidates", "change", "observed", "verdict")
VERDICTS = ("helped", "hurt", "no observed effect", "confounded")


def tokens(text: str) -> List[str]:
    return [w for w in _WORD.findall((text or "").lower()) if w not in _STOP]


def keywords_from(cue: str, limit: int = 12) -> List[str]:
    return list(dict.fromkeys(tokens(cue)))[:limit]


def _block(text: str, tag: str) -> Optional[str]:
    m = re.search(rf"<{tag}>(.*?)</{tag}>", text or "", re.S | re.I)
    return m.group(1).strip() if m else None


def parse_experience(text: str) -> dict:
    """Parses the reflector's `<edits>` rows and `<experience>` entry.

    Returns {"edits": [...], "experience": {...} or None}. NO_ENTRY (or a
    missing block) means the reflector declined to write a lesson."""
    edits = []
    body = _block(text, "edits") or ""
    row: dict = {}
    for line in body.splitlines():
        m = re.match(
            r"^\s*(component|candidates|change|observed|verdict)\s*:\s*(.*)$",
            line,
            re.I,
        )
        if not m:
            if row and line.strip() and not line.strip().startswith("("):
                last = list(row)[-1]
                row[last] = (row[last] + " " + line.strip()).strip()
            continue
        key, val = m.group(1).lower(), m.group(2).strip()
        if key == "component" and row:
            edits.append(row)
            row = {}
        row[key] = val
    if row:
        edits.append(row)
    for r in edits:
        v = r.get("verdict", "").lower().strip(" .`")
        r["verdict"] = next((x for x in VERDICTS if v.startswith(x)), v)

    exp_text = _block(text, "experience")
    experience = None
    if exp_text and exp_text.strip().upper() != "NO_ENTRY":
        experience = {}
        current = None
        for line in exp_text.splitlines():
            m = _FIELD.match(line)
            if m:
                current = m.group(1).lower()
                experience[current] = m.group(2).strip()
            elif current and line.strip():
                experience[current] += " " + line.strip()
        if not experience.get("cue") or not experience.get("lesson"):
            experience = None
    return {"edits": edits, "experience": experience}


def render_experience(parsed: dict, title: str, source: str) -> str:
    lines = [f"# {title}", "", f"Source: {source}", "", "<edits>"]
    for r in parsed.get("edits", []):
        for k in _EDIT_KEYS:
            lines.append(f"{k}: {r.get(k, '')}")
        lines.append("")
    lines.append("</edits>")
    lines.append("")
    exp = parsed.get("experience")
    if exp:
        lines.append("<experience>")
        for k in ("cue", "lesson", "evidence", "confidence"):
            lines.append(f"{k}: {exp.get(k, '')}")
        lines.append("</experience>")
    else:
        lines.append("NO_ENTRY")
    return "\n".join(lines) + "\n"


def load_index(root: Optional[Path] = None) -> dict:
    root = root or library_dir()
    idx = read_json(root / "index.json", None)
    if not isinstance(idx, dict) or not isinstance(idx.get("entries"), list):
        idx = {"entries": []}
    return idx


def next_number(root: Optional[Path] = None) -> int:
    root = root or library_dir()
    nums = [
        int(e["id"][:4])
        for e in load_index(root)["entries"]
        if str(e.get("id", ""))[:4].isdigit()
    ]
    if root.is_dir():
        nums += [
            int(p.name[:4])
            for p in root.iterdir()
            if p.is_dir() and p.name[:4].isdigit()
        ]
    return max(nums, default=0) + 1


def slugify(text: str, limit: int = 48) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-")
    return slug[:limit].strip("-") or "entry"


def add_entry(
    experience_md: str,
    harness_src: Optional[Path],
    slug: str,
    root: Optional[Path] = None,
    keywords: Optional[List[str]] = None,
    entry_id: Optional[str] = None,
) -> dict:
    """Stores an entry and indexes it. Returns the index row."""
    root = root or library_dir()
    root.mkdir(parents=True, exist_ok=True)
    entry_id = entry_id or f"{next_number(root):04d}-{slugify(slug)}"
    dest = root / entry_id
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "EXPERIENCE.md").write_text(experience_md, encoding="utf-8")
    if harness_src and Path(harness_src).is_dir():
        if (dest / "harness").exists():
            shutil.rmtree(dest / "harness")
        shutil.copytree(
            harness_src,
            dest / "harness",
            ignore=shutil.ignore_patterns("lib", "__pycache__", "*.pyc"),
        )
    parsed = parse_experience(experience_md)
    exp = parsed["experience"] or {}
    row = {
        "id": entry_id,
        "cue": exp.get("cue", ""),
        "lesson": exp.get("lesson", ""),
        "confidence": exp.get("confidence", ""),
        "keywords": keywords or keywords_from(exp.get("cue", "")),
        "created_at": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "path": entry_id,
    }
    idx = load_index(root)
    idx["entries"] = [e for e in idx["entries"] if e.get("id") != entry_id] + [row]
    write_json(root / "index.json", idx)
    return row


def _hit(token: str, kw: str) -> bool:
    if token == kw:
        return True
    # Cheap stemming: "enlarging" ~ "enlarge", "borders" ~ "border".
    n = min(len(token), len(kw))
    return n >= 5 and token[: n - 1] == kw[: n - 1]


def match(
    text: str, entries: List[dict], limit: int = 2, threshold: int = 2
) -> List[dict]:
    """Entries whose cue keywords the text hits at least `threshold` times."""
    toks = set(tokens(text))
    scored = []
    for e in entries:
        if not e.get("lesson"):
            continue
        kws = e.get("keywords") or keywords_from(e.get("cue", ""))
        score = sum(1 for kw in kws if any(_hit(t, kw.lower()) for t in toks))
        if score >= threshold:
            scored.append((score, e))
    scored.sort(key=lambda x: -x[0])
    return [e for _, e in scored[:limit]]
