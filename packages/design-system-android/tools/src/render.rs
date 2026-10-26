// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! gen_tokens.py's `render`: tokens.json in, VitruvianTokens.kt out.
//!
//! Each function here is the Python function of the same name, step for
//! step, so that a token tree the script chokes on stops this at the same
//! place with the same exception.

use crate::pyerr::Exc;
use crate::pystr::{self, ps, PyStr};
use crate::value::{Dict, Value};

/// Semantic colours the theme exposes, in the order of the generated data
/// class (gen_tokens.py's SEMANTIC_COLORS).
pub const SEMANTIC_COLORS: [(&str, &str); 44] = [
    ("bg", "color.bg"),
    ("surface", "color.surface"),
    ("surface2", "color.surface-2"),
    ("text", "color.text"),
    ("textDim", "color.text-dim"),
    ("divider", "color.divider"),
    ("line", "color.line"),
    ("accent", "color.accent"),
    ("accent100", "color.accent.100"),
    ("accent200", "color.accent.200"),
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
    ("sanguine100", "color.sanguine.100"),
    ("sanguine200", "color.sanguine.200"),
    ("sanguine300", "color.sanguine.300"),
    ("sanguine400", "color.sanguine.400"),
    ("sanguine500", "color.sanguine.500"),
    ("sanguine600", "color.sanguine.600"),
    ("sanguine700", "color.sanguine.700"),
    ("sanguine800", "color.sanguine.800"),
    ("sanguine900", "color.sanguine.900"),
    ("sanguineText", "color.sanguine-text"),
    ("ok", "color.ok"),
    ("warn", "color.warn"),
    ("crit", "color.crit"),
    ("neutral100", "color.neutral.100"),
    ("neutral200", "color.neutral.200"),
    ("neutral300", "color.neutral.300"),
    ("neutral400", "color.neutral.400"),
    ("neutral500", "color.neutral.500"),
    ("neutral600", "color.neutral.600"),
    ("neutral700", "color.neutral.700"),
    ("neutral800", "color.neutral.800"),
    ("neutral900", "color.neutral.900"),
    ("glass", "glass.bg"),
];

/// How many `resolve` calls may be on the stack at once before Python stops
/// with RecursionError (each `{alias}` hop is one more): the interpreter's
/// limit of 1000 frames, less the ones beneath when gen_tokens-py runs
/// (Bazel's bootstrap, runpy, the module, main, render, color_lines).
/// Measured; the parity test holds both sides of the edge.
pub const RESOLVE_MAX_DEPTH: usize = 990;

/// `resolve(tokens, dotted)`: the `$value` at a dotted path, following
/// `{alias}` values (which are resolved in the same tree, as often as they
/// chain).
fn resolve(tokens: &Value, dotted: &[u32], depth: usize) -> Result<Value, Exc> {
    if depth > RESOLVE_MAX_DEPTH {
        return Err(Exc::recursion(""));
    }
    let mut node = tokens;
    for part in pystr::split(dotted, '.') {
        node = node.index_str(&part)?;
    }
    let value = node.index_str(&ps("$value"))?;
    if let Value::Str(s) = value {
        if pystr::starts_with(s, "{") && pystr::ends_with(s, "}") {
            let inner = if s.len() >= 2 {
                &s[1..s.len() - 1]
            } else {
                &s[..0]
            };
            return resolve(tokens, inner, depth + 1);
        }
    }
    Ok(value.clone())
}

/// `argb(hex_value)`: `#rrggbb` / `#rrggbbaa` to a Compose `0xAARRGGBB`.
fn argb(hex_value: &Value) -> Result<PyStr, Exc> {
    let s = hex_value.str_attr("lstrip")?;
    let skip = s.iter().take_while(|&&c| c == '#' as u32).count();
    let raw = &s[skip..];
    let (alpha, rgb): (PyStr, &[u32]) = match raw.len() {
        6 => (ps("FF"), raw),
        8 => (raw[6..8].to_vec(), &raw[0..6]),
        _ => {
            let mut msg = ps("unexpected colour literal: ");
            msg.extend_from_slice(s);
            return Err(Exc {
                class: "ValueError",
                msg,
            });
        }
    };
    let mut out = ps("0x");
    out.extend(pystr::upper(&alpha));
    out.extend(pystr::upper(rgb));
    Ok(out)
}

/// `px(value)` and `ms(value)`: `value.removesuffix(suffix)`.
fn strip_unit(value: &Value, suffix: &str) -> Result<PyStr, Exc> {
    Ok(pystr::remove_suffix(
        value.str_attr("removesuffix")?,
        suffix,
    ))
}

/// One output line, built from literal text and str pieces.
fn line(pieces: &[&[u32]]) -> PyStr {
    pieces.concat()
}

fn color_lines(tokens: &Value, light: bool, out: &mut Vec<PyStr>) -> Result<(), Exc> {
    let overrides = if light {
        match tokens {
            Value::Dict(d) => d
                .get(&ps("light"))
                .cloned()
                .unwrap_or(Value::Dict(Dict::new())),
            other => return Err(other.no_attribute("get")),
        }
    } else {
        Value::Dict(Dict::new())
    };
    for (name, path) in SEMANTIC_COLORS {
        let path = ps(path);
        let head = pystr::split(&path, '.').swap_remove(0);
        // resolve({head: overrides[head]}, path), the light theme's tree.
        let scoped = || -> Result<Value, Exc> {
            let mut d = Dict::new();
            d.insert(head.clone(), overrides.index_str(&head)?.clone());
            Ok(Value::Dict(d))
        };
        let mut from_overrides = false;
        if light && overrides.contains_str(&head)? {
            match resolve(&scoped()?, &path, 1) {
                Ok(_) => from_overrides = true,
                Err(e) if e.class == "KeyError" => {}
                Err(e) => return Err(e),
            }
        }
        let value = if from_overrides {
            resolve(&scoped()?, &path, 1)?
        } else {
            resolve(tokens, &path, 1)?
        };
        out.push(line(&[
            &ps("        "),
            &ps(name),
            &ps(" = Color("),
            &argb(&value)?,
            &ps("),"),
        ]));
    }
    Ok(())
}

/// `sorted(x, key=int)`: every key computed first, in order, then a stable
/// sort on them.
fn sorted_by_int(x: &Value) -> Result<Vec<Value>, Exc> {
    let items = x.iterate()?;
    let mut keyed = Vec::with_capacity(items.len());
    for item in items {
        keyed.push((item.to_int()?, item));
    }
    keyed.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(keyed.into_iter().map(|(_, item)| item).collect())
}

/// A scale whose keys are numbers: Space, Hit, Duration.
fn numbered(
    scale: &Value,
    out: &mut Vec<PyStr>,
    each: impl Fn(&PyStr, &Value) -> Result<PyStr, Exc>,
) -> Result<(), Exc> {
    for key in sorted_by_int(scale)? {
        let key_text = key.py_str();
        let entry = scale.index(&key)?;
        out.push(each(&key_text, entry.index_str(&ps("$value"))?)?);
    }
    Ok(())
}

fn push(out: &mut Vec<PyStr>, text: &str) {
    out.push(ps(text));
}

/// `render(tokens, header)`.
pub fn render(tokens: &Value, header: &[u32]) -> Result<PyStr, Exc> {
    let mut out: Vec<PyStr> = vec![header.to_vec()];
    out.push(ps(PREAMBLE));
    for (name, _) in SEMANTIC_COLORS {
        push(&mut out, &format!("    public val {}: Color,", name));
    }
    push(&mut out, ")");
    push(&mut out, "");
    push(&mut out, "/** Dark is the default mode - the board. */");
    push(&mut out, "public fun darkColors(): VitruvianColors =");
    push(&mut out, "    VitruvianColors(");
    color_lines(tokens, false, &mut out)?;
    push(&mut out, "    )");
    push(&mut out, "");
    push(&mut out, "/** Light is parchment. */");
    push(&mut out, "public fun lightColors(): VitruvianColors =");
    push(&mut out, "    VitruvianColors(");
    color_lines(tokens, true, &mut out)?;
    push(&mut out, "    )");
    push(&mut out, "");

    let space = tokens.index_str(&ps("space"))?;
    push(
        &mut out,
        "/** The Fibonacci spacing scale. Nothing else is used for padding or gaps. */",
    );
    push(&mut out, "public object Space {");
    numbered(space, &mut out, |key, value| {
        Ok(line(&[
            &ps("    public val s"),
            key,
            &ps(": Dp = "),
            &strip_unit(value, "px")?,
            &ps(".dp"),
        ]))
    })?;
    push(&mut out, "}");
    push(&mut out, "");

    let hit = tokens.index_str(&ps("hit"))?;
    push(
        &mut out,
        "/** Touch-target floors: every clickable is at least [Hit.h1]; rows and bars are [Hit.h2]. */",
    );
    push(&mut out, "public object Hit {");
    numbered(hit, &mut out, |key, value| {
        Ok(line(&[
            &ps("    public val h"),
            key,
            &ps(": Dp = "),
            &strip_unit(value, "px")?,
            &ps(".dp"),
        ]))
    })?;
    push(&mut out, "}");
    push(&mut out, "");

    let size = tokens.index_str(&ps("font"))?.index_str(&ps("size"))?;
    push(
        &mut out,
        "/** The type ramp. `mobile*` is the phone ramp used by this app. */",
    );
    push(&mut out, "public object FontSize {");
    for (key, node) in size.dict_items()? {
        let mut name = Vec::new();
        for (i, part) in pystr::split(key, '-').iter().enumerate() {
            if i == 0 {
                name.extend_from_slice(part);
            } else {
                name.extend(pystr::capitalize(part));
            }
        }
        out.push(line(&[
            &ps("    public val "),
            &name,
            &ps(": TextUnit = "),
            &strip_unit(node.index_str(&ps("$value"))?, "px")?,
            &ps(".sp"),
        ]));
    }
    push(&mut out, "}");
    push(&mut out, "");

    let motion = tokens.index_str(&ps("motion"))?;
    let dur = motion.index_str(&ps("duration"))?;
    push(
        &mut out,
        "/** Motion durations, in milliseconds. No springs, ever. */",
    );
    push(&mut out, "public object Duration {");
    numbered(dur, &mut out, |key, value| {
        Ok(line(&[
            &ps("    public const val D"),
            key,
            &ps(": Int = "),
            &strip_unit(value, "ms")?,
        ]))
    })?;
    push(&mut out, "}");
    push(&mut out, "");

    let easing = tokens.index_str(&ps("motion"))?.index_str(&ps("easing"))?;
    push(&mut out, "/** The two easing curves of the language. */");
    push(&mut out, "public object Easing {");
    for (key, node) in easing.dict_items()? {
        let [a, b, c, d] = node.index_str(&ps("$value"))?.unpack4()?;
        out.push(line(&[
            &ps("    public val "),
            key,
            &ps(": CubicBezierEasing = CubicBezierEasing("),
            &a.py_str(),
            &ps("f, "),
            &b.py_str(),
            &ps("f, "),
            &c.py_str(),
            &ps("f, "),
            &d.py_str(),
            &ps("f)"),
        ]));
    }
    push(&mut out, "}");
    push(&mut out, "");

    push(&mut out, "/**");
    push(
        &mut out,
        " * Elevations for the things that float - menu, dialog, sheet. Board content is flat.",
    );
    push(&mut out, " *");
    push(
        &mut out,
        " * Compose has one elevation scalar where CSS has offset+blur+colour, so the",
    );
    push(
        &mut out,
        " * token's vertical offset is what carries over; the renderer derives its own",
    );
    push(&mut out, " * blur from it.");
    push(&mut out, " */");
    push(&mut out, "public object Shadow {");
    for key in ["sm", "md", "lg"] {
        let offset = tokens
            .index_str(&ps("shadow"))?
            .index_str(&ps(key))?
            .index_str(&ps("$value"))?
            .index_str(&ps("offsetY"))?;
        out.push(line(&[
            &ps("    public val "),
            &ps(key),
            &ps(": Dp = "),
            &strip_unit(offset, "px")?,
            &ps(".dp"),
        ]));
    }
    push(&mut out, "}");
    push(&mut out, "");
    push(
        &mut out,
        "/** Backdrop blur radius for glass surfaces (API 31+). */",
    );
    push(&mut out, "public const val GLASS_BLUR_RADIUS: Float = 16f");

    let mut text = out.join(&('\n' as u32));
    text.push('\n' as u32);
    Ok(text)
}

/// The fixed block between the header and the colour fields.
const PREAMBLE: &str = "\
// GENERATED FILE - DO NOT EDIT.
//
// Source: packages/design-system/src/tokens.json
// Regenerate: bazel run //packages/design-system-android/tools:gen_tokens
//
// px are read as dp and font sizes as sp, per
// packages/design-system/ANDROID.md.

@file:Suppress(\"MagicNumber\")

package dev.vitruvian.design

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * The semantic colour roles of the Vitruvian language.
 *
 * Deliberately NOT mapped onto [androidx.compose.material3.ColorScheme]:
 * Material's roles do not match this language (ANDROID.md).
 */
@Immutable
public data class VitruvianColors(";
