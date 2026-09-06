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

"""Emit VitruvianTokens.kt from the web design system's tokens.json.

ANDROID.md is explicit that the Android token layer is *generated*, never
hand-copied, so that web and Android cannot drift. This is that generator:
`bazel run //packages/design-system-android/tools:gen_tokens` rewrites the
checked-in Kotlin, and `//packages/design-system-android:tokens_are_current`
diffs the two in CI.

The mapping follows ANDROID.md exactly: px are read as dp, font sizes as sp,
8-digit hex keeps its alpha (those are the color-mix tints), and `light.*`
overrides the same paths for the parchment theme.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

# Semantic colours the theme exposes. Order is the order they appear in the
# generated data class, so it is also the review order.
SEMANTIC_COLORS = [
    ("bg", "color.bg"),
    ("surface", "color.surface"),
    ("surface2", "color.surface-2"),
    ("text", "color.text"),
    ("textDim", "color.text-dim"),
    ("divider", "color.divider"),
    ("line", "color.line"),
    ("accent", "color.accent"),
    ("accent100", "color.accent.100"),
    ("accent300", "color.accent.300"),
    ("accent400", "color.accent.400"),
    ("accent500", "color.accent.500"),
    ("accent600", "color.accent.600"),
    ("accent700", "color.accent.700"),
    ("accent800", "color.accent.800"),
    ("accent900", "color.accent.900"),
    ("accentText", "color.accent-text"),
    ("accentQuiet", "color.accent-quiet"),
    ("onAccent", "color.on-accent"),
    ("sanguine", "color.sanguine"),
    ("sanguineText", "color.sanguine-text"),
    ("ok", "color.ok"),
    ("warn", "color.warn"),
    ("crit", "color.crit"),
    ("neutral500", "color.neutral.500"),
    ("neutral900", "color.neutral.900"),
    ("glass", "glass.bg"),
]

HEADER = pathlib.Path(__file__).with_name("kt_license_header.txt")


def resolve(tokens: dict, dotted: str) -> str:
    """Read a `$value` at a dotted token path, following one alias hop."""
    node = tokens
    for part in dotted.split("."):
        node = node[part]
    value = node["$value"]
    if isinstance(value, str) and value.startswith("{") and value.endswith("}"):
        return resolve(tokens, value[1:-1])
    return value


def argb(hex_value: str) -> str:
    """`#rrggbb` / `#rrggbbaa` -> a Compose `0xAARRGGBB` literal."""
    raw = hex_value.lstrip("#")
    if len(raw) == 6:
        alpha = "FF"
        rgb = raw
    elif len(raw) == 8:
        alpha = raw[6:8]
        rgb = raw[0:6]
    else:
        raise ValueError(f"unexpected colour literal: {hex_value}")
    return f"0x{alpha.upper()}{rgb.upper()}"


def px(value: str) -> str:
    """`13px` -> `13` (read as dp on Android, per ANDROID.md)."""
    return value.removesuffix("px")


def ms(value: str) -> str:
    return value.removesuffix("ms")


def color_lines(tokens: dict, light: bool) -> list[str]:
    overrides = tokens.get("light", {}) if light else {}
    lines = []
    for name, path in SEMANTIC_COLORS:
        source = tokens
        head, _, tail = path.partition(".")
        if light and head in overrides:
            try:
                resolve({head: overrides[head]}, path)
                source = overrides
            except KeyError:
                source = tokens
        if source is overrides:
            value = resolve({head: overrides[head]}, path)
        else:
            value = resolve(tokens, path)
        lines.append(f"        {name} = Color({argb(value)}),")
    return lines


def render(tokens: dict, header: str) -> str:
    out: list[str] = [header]
    out.append(
        "\n".join(
            [
                "// GENERATED FILE - DO NOT EDIT.",
                "//",
                "// Source: packages/design-system/src/tokens.json",
                "// Regenerate: bazel run //packages/design-system-android/tools:gen_tokens",
                "//",
                "// px are read as dp and font sizes as sp, per",
                "// packages/design-system/ANDROID.md.",
                "",
                '@file:Suppress("MagicNumber")',
                "",
                "package dev.vitruvian.design",
                "",
                "import androidx.compose.animation.core.CubicBezierEasing",
                "import androidx.compose.runtime.Immutable",
                "import androidx.compose.ui.graphics.Color",
                "import androidx.compose.ui.unit.Dp",
                "import androidx.compose.ui.unit.TextUnit",
                "import androidx.compose.ui.unit.dp",
                "import androidx.compose.ui.unit.sp",
                "",
                "/**",
                " * The semantic colour roles of the Vitruvian language.",
                " *",
                " * Deliberately NOT mapped onto [androidx.compose.material3.ColorScheme]:",
                " * Material's roles do not match this language (ANDROID.md).",
                " */",
                "@Immutable",
                "public data class VitruvianColors(",
            ]
        )
    )
    for name, _ in SEMANTIC_COLORS:
        out.append(f"    public val {name}: Color,")
    out.append(")")
    out.append("")
    out.append("/** Dark is the default mode - the board. */")
    out.append("public fun darkColors(): VitruvianColors =")
    out.append("    VitruvianColors(")
    out.extend(color_lines(tokens, light=False))
    out.append("    )")
    out.append("")
    out.append("/** Light is parchment. */")
    out.append("public fun lightColors(): VitruvianColors =")
    out.append("    VitruvianColors(")
    out.extend(color_lines(tokens, light=True))
    out.append("    )")
    out.append("")

    space = tokens["space"]
    out.append(
        "/** The Fibonacci spacing scale. Nothing else is used for padding or gaps. */"
    )
    out.append("public object Space {")
    for key in sorted(space, key=int):
        out.append(f"    public val s{key}: Dp = {px(space[key]['$value'])}.dp")
    out.append("}")
    out.append("")

    hit = tokens["hit"]
    out.append(
        "/** Touch-target floors: every clickable is at least [Hit.h1]; rows and bars are [Hit.h2]. */"
    )
    out.append("public object Hit {")
    for key in sorted(hit, key=int):
        out.append(f"    public val h{key}: Dp = {px(hit[key]['$value'])}.dp")
    out.append("}")
    out.append("")

    size = tokens["font"]["size"]
    out.append("/** The type ramp. `mobile*` is the phone ramp used by this app. */")
    out.append("public object FontSize {")
    for key, node in size.items():
        name = "".join(p.capitalize() if i else p for i, p in enumerate(key.split("-")))
        out.append(f"    public val {name}: TextUnit = {px(node['$value'])}.sp")
    out.append("}")
    out.append("")

    dur = tokens["motion"]["duration"]
    out.append("/** Motion durations, in milliseconds. No springs, ever. */")
    out.append("public object Duration {")
    for key in sorted(dur, key=int):
        out.append(f"    public const val D{key}: Int = {ms(dur[key]['$value'])}")
    out.append("}")
    out.append("")

    easing = tokens["motion"]["easing"]
    out.append("/** The two easing curves of the language. */")
    out.append("public object Easing {")
    for key, node in easing.items():
        a, b, c, d = node["$value"]
        out.append(
            f"    public val {key}: CubicBezierEasing = CubicBezierEasing({a}f, {b}f, {c}f, {d}f)"
        )
    out.append("}")
    out.append("")

    out.append("/**")
    out.append(
        " * Elevations for the things that float - menu, dialog, sheet. Board content is flat."
    )
    out.append(" *")
    out.append(
        " * Compose has one elevation scalar where CSS has offset+blur+colour, so the"
    )
    out.append(
        " * token's vertical offset is what carries over; the renderer derives its own"
    )
    out.append(" * blur from it.")
    out.append(" */")
    out.append("public object Shadow {")
    for key in ("sm", "md", "lg"):
        offset = px(tokens["shadow"][key]["$value"]["offsetY"])
        out.append(f"    public val {key}: Dp = {offset}.dp")
    out.append("}")
    out.append("")
    out.append("/** Backdrop blur radius for glass surfaces (API 31+). */")
    out.append("public const val GLASS_BLUR_RADIUS: Float = 16f")
    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tokens", required=True)
    parser.add_argument("--header", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    tokens = json.loads(pathlib.Path(args.tokens).read_text(encoding="utf-8"))
    header = pathlib.Path(args.header).read_text(encoding="utf-8")
    pathlib.Path(args.out).write_text(render(tokens, header), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
