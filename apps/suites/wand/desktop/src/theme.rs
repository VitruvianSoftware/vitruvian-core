// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify,
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
// PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
// OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

//! Vitruvian design system tokens mapped into [`egui::Style`] and [`egui::Visuals`].
//!
//! All colour, type-scale, radius, and spacing values come directly from
//! `packages/design-system/src/tokens.json` (Codex Folium — Warm Parchment &
//! Slate Ink). Note: `tokens.json` does not define separate radial-slot preset
//! swatches beyond the semantic/brand palette (`accent`, `ok`, `warn`, `crit`,
//! `sanguine`, `slate-400`, `slate-600`, `neutral-500`), so named radial slot
//! colours map onto those exact tokens (or parse `#RRGGBB` hex when user-entered).

use egui::{Color32, CornerRadius, FontFamily, FontId, Margin, Stroke, Style, TextStyle, Visuals, vec2};

use crate::config::ThemePreference;

/// Spacing scale from `packages/design-system/src/tokens.json` (`spacing.1` .. `spacing.6`).
pub mod spacing {
    pub const S1: f32 = 3.0;
    pub const S2: f32 = 5.0;
    pub const S3: f32 = 8.0;
    pub const S4: f32 = 13.0;
    pub const S5: f32 = 21.0;
    pub const S6: f32 = 34.0;
}

/// Type scale from `packages/design-system/src/tokens.json` (`font.size.*`).
pub mod type_scale {
    pub const H3: f32 = 22.0;
    pub const H4: f32 = 17.0;
    pub const H5: f32 = 14.0;
    pub const H6: f32 = 11.0;
    pub const BODY: f32 = 15.0;
    pub const SMALL: f32 = 12.0;
    pub const LABEL: f32 = 10.0;
    pub const MONO: f32 = 13.0;
}

/// Semantic colour palette resolved for either Dark or Light mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Palette {
    pub bg: Color32,
    pub surface: Color32,
    pub surface_2: Color32,
    pub text: Color32,
    pub text_dim: Color32,
    pub divider: Color32,
    pub line: Color32,
    pub accent: Color32,
    pub accent_text: Color32,
    pub accent_quiet: Color32,
    pub on_accent: Color32,
    pub ok: Color32,
    pub warn: Color32,
    pub crit: Color32,
    pub neutral_500: Color32,
}

/// Dark theme tokens from `packages/design-system/src/tokens.json` (`color.dark` + `color.brand`).
#[must_use]
pub fn dark_palette() -> Palette {
    Palette {
        bg: Color32::from_rgb(0x0e, 0x13, 0x17),
        surface: Color32::from_rgb(0x14, 0x1b, 0x20),
        surface_2: Color32::from_rgb(0x1b, 0x24, 0x29),
        text: Color32::from_rgb(0xe7, 0xe4, 0xdd),
        text_dim: Color32::from_rgb(0x9a, 0xa3, 0xa9),
        divider: Color32::from_rgba_unmultiplied(0xe7, 0xe4, 0xdd, 0x26),
        line: Color32::from_rgba_unmultiplied(0xe7, 0xe4, 0xdd, 0x0f),
        accent: Color32::from_rgb(0x59, 0x80, 0xa6),
        accent_text: Color32::from_rgb(0x93, 0xb0, 0xca),
        accent_quiet: Color32::from_rgba_unmultiplied(0x59, 0x80, 0xa6, 0x2e),
        on_accent: Color32::from_rgb(0x0e, 0x13, 0x17),
        ok: Color32::from_rgb(0x5b, 0x9c, 0x78),
        warn: Color32::from_rgb(0xc8, 0x9a, 0x3c),
        crit: Color32::from_rgb(0xb4, 0x55, 0x3c),
        neutral_500: Color32::from_rgb(0x77, 0x80, 0x87),
    }
}

/// Light theme tokens from `packages/design-system/src/tokens.json` (`color.light` + `color.brand`).
#[must_use]
pub fn light_palette() -> Palette {
    Palette {
        bg: Color32::from_rgb(0xee, 0xeb, 0xe4),
        surface: Color32::from_rgb(0xf5, 0xf3, 0xee),
        surface_2: Color32::from_rgb(0xe5, 0xe1, 0xd8),
        text: Color32::from_rgb(0x1a, 0x20, 0x24),
        text_dim: Color32::from_rgb(0x5c, 0x66, 0x6d),
        divider: Color32::from_rgba_unmultiplied(0x1a, 0x20, 0x24, 0x2e),
        line: Color32::from_rgba_unmultiplied(0x1a, 0x20, 0x24, 0x14),
        accent: Color32::from_rgb(0x59, 0x80, 0xa6),
        accent_text: Color32::from_rgb(0x3b, 0x57, 0x76),
        accent_quiet: Color32::from_rgba_unmultiplied(0x59, 0x80, 0xa6, 0x29),
        on_accent: Color32::from_rgb(0xf5, 0xf3, 0xee),
        ok: Color32::from_rgb(0x3f, 0x7a, 0x5b),
        warn: Color32::from_rgb(0x94, 0x70, 0x2a),
        crit: Color32::from_rgb(0xb4, 0x55, 0x3c),
        neutral_500: Color32::from_rgb(0x77, 0x80, 0x87),
    }
}

/// Resolve the active [`Palette`] for the current [`egui::Context`] and user preference.
#[must_use]
pub fn active_palette(ctx: &egui::Context, pref: ThemePreference) -> Palette {
    let is_dark = match pref {
        ThemePreference::Dark => true,
        ThemePreference::Light => false,
        ThemePreference::System => ctx.theme() == egui::Theme::Dark,
    };
    if is_dark {
        dark_palette()
    } else {
        light_palette()
    }
}

/// Build [`egui::Visuals`] for a given [`Palette`].
#[must_use]
pub fn visuals_for_palette(p: Palette, dark_mode: bool) -> Visuals {
    let mut v = if dark_mode {
        Visuals::dark()
    } else {
        Visuals::light()
    };

    v.dark_mode = dark_mode;
    v.override_text_color = Some(p.text);
    v.panel_fill = p.bg;
    v.window_fill = p.surface;
    v.faint_bg_color = p.surface;
    v.extreme_bg_color = p.surface_2;
    v.code_bg_color = p.surface_2;
    v.warn_fg_color = p.warn;
    v.error_fg_color = p.crit;
    v.hyperlink_color = p.accent_text;

    // Sharp architectural geometry (`radius.sm/md/lg = 0px` in tokens.json).
    v.window_corner_radius = CornerRadius::ZERO;
    v.menu_corner_radius = CornerRadius::ZERO;
    v.window_stroke = Stroke::new(1.0, p.divider);

    v.selection.bg_fill = p.accent;
    v.selection.stroke = Stroke::new(1.0, p.on_accent);

    v.widgets.noninteractive.bg_fill = p.surface;
    v.widgets.noninteractive.weak_bg_fill = p.surface;
    v.widgets.noninteractive.bg_stroke = Stroke::new(1.0, p.divider);
    v.widgets.noninteractive.fg_stroke = Stroke::new(1.0, p.text);
    v.widgets.noninteractive.corner_radius = CornerRadius::ZERO;

    v.widgets.inactive.bg_fill = p.surface_2;
    v.widgets.inactive.weak_bg_fill = p.surface;
    v.widgets.inactive.bg_stroke = Stroke::new(1.0, p.divider);
    v.widgets.inactive.fg_stroke = Stroke::new(1.0, p.text);
    v.widgets.inactive.corner_radius = CornerRadius::ZERO;

    v.widgets.hovered.bg_fill = p.surface_2;
    v.widgets.hovered.weak_bg_fill = p.surface_2;
    v.widgets.hovered.bg_stroke = Stroke::new(1.0, p.accent);
    v.widgets.hovered.fg_stroke = Stroke::new(1.0, p.text);
    v.widgets.hovered.corner_radius = CornerRadius::ZERO;

    v.widgets.active.bg_fill = p.accent;
    v.widgets.active.weak_bg_fill = p.accent;
    v.widgets.active.bg_stroke = Stroke::new(1.0, p.accent_text);
    v.widgets.active.fg_stroke = Stroke::new(1.0, p.on_accent);
    v.widgets.active.corner_radius = CornerRadius::ZERO;

    v.widgets.open.bg_fill = p.surface_2;
    v.widgets.open.weak_bg_fill = p.surface_2;
    v.widgets.open.bg_stroke = Stroke::new(1.0, p.accent);
    v.widgets.open.fg_stroke = Stroke::new(1.0, p.text);
    v.widgets.open.corner_radius = CornerRadius::ZERO;

    v
}

/// Build an [`egui::Style`] populated with Vitruvian typography, spacing, and visuals.
#[must_use]
pub fn style_for_palette(p: Palette, dark_mode: bool) -> Style {
    let mut style = Style::default();
    style.text_styles.insert(
        TextStyle::Heading,
        FontId::new(type_scale::H4, FontFamily::Proportional),
    );
    style.text_styles.insert(
        TextStyle::Body,
        FontId::new(type_scale::BODY, FontFamily::Proportional),
    );
    style.text_styles.insert(
        TextStyle::Button,
        FontId::new(type_scale::H5, FontFamily::Proportional),
    );
    style.text_styles.insert(
        TextStyle::Small,
        FontId::new(type_scale::SMALL, FontFamily::Proportional),
    );
    style.text_styles.insert(
        TextStyle::Monospace,
        FontId::new(type_scale::MONO, FontFamily::Monospace),
    );

    style.spacing.item_spacing = vec2(spacing::S3, spacing::S3);
    style.spacing.window_margin = Margin::same(spacing::S4 as i8);
    style.spacing.button_padding = vec2(spacing::S3, spacing::S2);
    style.spacing.indent = spacing::S4;
    style.visuals = visuals_for_palette(p, dark_mode);
    style
}

/// Apply the Vitruvian theme to `ctx` according to `pref`.
pub fn apply_theme(ctx: &egui::Context, pref: ThemePreference) {
    ctx.set_style_of(egui::Theme::Dark, style_for_palette(dark_palette(), true));
    ctx.set_style_of(egui::Theme::Light, style_for_palette(light_palette(), false));
    let egui_pref = match pref {
        ThemePreference::System => egui::ThemePreference::System,
        ThemePreference::Light => egui::ThemePreference::Light,
        ThemePreference::Dark => egui::ThemePreference::Dark,
    };
    ctx.set_theme(egui_pref);
}

/// Named radial slot preset colours mapped onto Vitruvian tokens.
pub const RADIAL_COLOR_PRESETS: &[(&str, Color32)] = &[
    ("slate", Color32::from_rgb(0x59, 0x80, 0xa6)),
    ("sky", Color32::from_rgb(0x93, 0xb0, 0xca)),
    ("ok", Color32::from_rgb(0x5b, 0x9c, 0x78)),
    ("warn", Color32::from_rgb(0xc8, 0x9a, 0x3c)),
    ("sanguine", Color32::from_rgb(0xb4, 0x55, 0x3c)),
    ("deep-slate", Color32::from_rgb(0x3b, 0x57, 0x76)),
    ("neutral", Color32::from_rgb(0x77, 0x80, 0x87)),
    ("parchment", Color32::from_rgb(0xc7, 0xc3, 0xbb)),
];

/// Resolve a radial slot colour string (token name or `#RRGGBB` hex) into a [`Color32`].
#[must_use]
pub fn resolve_slot_color(color_str: &str, p: Palette) -> Color32 {
    let trimmed = color_str.trim();
    for (name, c) in RADIAL_COLOR_PRESETS {
        if trimmed.eq_ignore_ascii_case(name) {
            return *c;
        }
    }
    if let Some(hex) = trimmed.strip_prefix('#')
        && hex.len() == 6
        && let (Ok(r), Ok(g), Ok(b)) = (
            u8::from_str_radix(&hex[0..2], 16),
            u8::from_str_radix(&hex[2..4], 16),
            u8::from_str_radix(&hex[4..6], 16),
        )
    {
        return Color32::from_rgb(r, g, b);
    }
    p.accent
}
