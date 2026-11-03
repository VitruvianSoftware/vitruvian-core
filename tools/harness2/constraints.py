# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Pulls hard constraints and correction signals out of a user's message.

These are the signals the 2026-11-02 icon conversation shows the agent
reading and then not honouring: "DO NOT TOUCH THE NEW AppIcon-Default.png!!!",
"WITHOUT MODIFYING the image!!!", "NO! Revert again!". They are recorded in
per-conversation state so the hooks can enforce them, not just remind.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import List, Tuple

_FILE = r"[`'\"]?(?P<f>[\w.\-/~]+\.[A-Za-z0-9]{1,6})[`'\"]?"
_QUAL = r"(?:the\s+)?(?:(?:new|old|current|existing|original|other)\s+)?"
_LOCKS = [
    re.compile(
        r"\b(?:do\s+not|don'?t|dont|never|stop)\s+(?:touch|touching|modify|modifying|edit|editing|change|changing|overwrite|overwriting|alter|replace|delete|remove)\s+"
        + _QUAL
        + _FILE,
        re.I,
    ),
    re.compile(r"\bleave\s+" + _QUAL + _FILE + r"\s+(?:alone|as\s+is|untouched)", re.I),
    re.compile(
        r"\bkeep\s+" + _QUAL + _FILE + r"\s+(?:untouched|unchanged|as\s+is)", re.I
    ),
]
_NO_GEN = re.compile(
    r"\bwithout\s+(?:modifying|changing|altering|regenerating|redrawing|re-?generating)\b"
    r"|\b(?:do\s+not|don'?t|never|no)\s+(?:use\s+)?(?:nano\s*banana|image[-\s]?gen\w*|generative|ai\b|regenerat\w*|redraw\w*)",
    re.I,
)
_EDIT_OP = re.compile(
    r"\b(?:remove|strip|delete|get\s+rid\s+of)\b[^.!?\n]{0,40}\b(?:border|margin|background|padding|frame|edge)s?\b"
    r"|\b(?:crop|upscale|downscale|resize|rescale|enlarge|shrink|trim|pad)\w*\b",
    re.I,
)
_IMAGE = re.compile(
    r"\b(?:image|icon|png|jpe?g|picture|photo|logo|button|badge|asset|pixels?|squircle)s?\b|\.(?:png|jpe?g|icns|webp)\b",
    re.I,
)
_GEN_ASK = re.compile(
    r"\b(?:nano\s*banana|imagen|generate|regenerate|redesign|re-?draw|illustrate|dall-?e|midjourney)\w*\b"
    r"|\bcreate\s+(?:a\s+)?new\s+(?:image|icon|design|logo)|\bwith\s+ai\b|\bai[-\s]generated\b",
    re.I,
)
_HIGH_ALERT = re.compile(
    r"\brevert\b|\bundo\b|(?:^|\s)NO!|\bwhy\s+(?:can'?t|didn'?t|did)\s+you\b|\blisten\s+to\s+me\b"
    r"|\bnot\s+what\s+i\s+(?:asked|wanted|said)\b|\bi\s+was\s+(?:very\s+)?clear\b|\bwrong\b|\bdumb\b|\bstupid\b"
    r"|\brepeat\s+(?:that|it)\s+back\b",
    re.I,
)
_SIZE = re.compile(r"\b(\d{2,5})\s*[x×]\s*(\d{2,5})\b")
_ANY_FILE = re.compile(r"[\w.\-]+\.(?:png|jpe?g|icns|webp)\b", re.I)


@dataclass
class Signals:
    locks: List[str] = field(default_factory=list)
    no_generative_explicit: bool = False
    deterministic_image_edit: bool = False
    generative_ask: bool = False
    high_alert: bool = False
    sizes: List[Tuple[int, int]] = field(default_factory=list)
    image_files: List[str] = field(default_factory=list)


def _clean_file(name: str) -> str:
    return name.strip().strip("`'\".,;:!?)(")


def extract(text: str) -> Signals:
    text = text or ""
    s = Signals()
    for rx in _LOCKS:
        for m in rx.finditer(text):
            f = _clean_file(m.group("f"))
            if f and f not in s.locks:
                s.locks.append(f)
    s.no_generative_explicit = bool(_NO_GEN.search(text))
    s.generative_ask = bool(_GEN_ASK.search(text)) and not s.no_generative_explicit
    has_edit = bool(_EDIT_OP.search(text)) and bool(_IMAGE.search(text))
    # An edit of an existing image is deterministic unless the user asked for
    # generation in the same message ("use nano banana and remove the border").
    s.deterministic_image_edit = (
        has_edit and not s.generative_ask
    ) or s.no_generative_explicit
    s.high_alert = bool(_HIGH_ALERT.search(text))
    s.sizes = [(int(a), int(b)) for a, b in _SIZE.findall(text)]
    s.image_files = [
        f for f in dict.fromkeys(_ANY_FILE.findall(text)) if f not in s.locks
    ]
    return s
