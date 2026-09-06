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

// GENERATED FILE - DO NOT EDIT.
//
// Source: packages/design-system/src/tokens.json
// Regenerate: bazel run //packages/design-system-android/tools:gen_tokens
//
// px are read as dp and font sizes as sp, per
// packages/design-system/ANDROID.md.

@file:Suppress("MagicNumber")

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
 * Deliberately NOT mapped onto [androidx.compose.material3.ColorScheme]: Material's roles do not
 * match this language (ANDROID.md).
 */
@Immutable
public data class VitruvianColors(
    public val bg: Color,
    public val surface: Color,
    public val surface2: Color,
    public val text: Color,
    public val textDim: Color,
    public val divider: Color,
    public val line: Color,
    public val accent: Color,
    public val accent100: Color,
    public val accent300: Color,
    public val accent400: Color,
    public val accent500: Color,
    public val accent600: Color,
    public val accent700: Color,
    public val accent800: Color,
    public val accent900: Color,
    public val accentText: Color,
    public val accentQuiet: Color,
    public val onAccent: Color,
    public val sanguine: Color,
    public val sanguineText: Color,
    public val ok: Color,
    public val warn: Color,
    public val crit: Color,
    public val neutral500: Color,
    public val neutral900: Color,
    public val glass: Color,
)

/** Dark is the default mode - the board. */
public fun darkColors(): VitruvianColors =
    VitruvianColors(
        bg = Color(0xFF0E1317),
        surface = Color(0xFF141B20),
        surface2 = Color(0xFF1B2429),
        text = Color(0xFFE7E4DD),
        textDim = Color(0xFF9AA3A9),
        divider = Color(0x26E7E4DD),
        line = Color(0x0FE7E4DD),
        accent = Color(0xFF5980A6),
        accent100 = Color(0xFFEFF4F9),
        accent300 = Color(0xFFBACFE0),
        accent400 = Color(0xFF93B0CA),
        accent500 = Color(0xFF5980A6),
        accent600 = Color(0xFF4A6D90),
        accent700 = Color(0xFF3B5776),
        accent800 = Color(0xFF2C405A),
        accent900 = Color(0xFF1E2C3D),
        accentText = Color(0xFF93B0CA),
        accentQuiet = Color(0x2E5980A6),
        onAccent = Color(0xFF0E1317),
        sanguine = Color(0xFFB4553C),
        sanguineText = Color(0xFFD2907B),
        ok = Color(0xFF5B9C78),
        warn = Color(0xFFC89A3C),
        crit = Color(0xFFB4553C),
        neutral500 = Color(0xFF778087),
        neutral900 = Color(0xFF151A1E),
        glass = Color(0xA8141B20),
    )

/** Light is parchment. */
public fun lightColors(): VitruvianColors =
    VitruvianColors(
        bg = Color(0xFFEEEBE4),
        surface = Color(0xFFF5F3EE),
        surface2 = Color(0xFFE5E1D8),
        text = Color(0xFF1A2024),
        textDim = Color(0xFF5C666D),
        divider = Color(0x2E1A2024),
        line = Color(0x141A2024),
        accent = Color(0xFF5980A6),
        accent100 = Color(0xFFEFF4F9),
        accent300 = Color(0xFFBACFE0),
        accent400 = Color(0xFF93B0CA),
        accent500 = Color(0xFF5980A6),
        accent600 = Color(0xFF4A6D90),
        accent700 = Color(0xFF3B5776),
        accent800 = Color(0xFF2C405A),
        accent900 = Color(0xFF1E2C3D),
        accentText = Color(0xFF3B5776),
        accentQuiet = Color(0x295980A6),
        onAccent = Color(0xFFF5F3EE),
        sanguine = Color(0xFFB4553C),
        sanguineText = Color(0xFF7E3A29),
        ok = Color(0xFF3F7A5B),
        warn = Color(0xFF94702A),
        crit = Color(0xFFB4553C),
        neutral500 = Color(0xFF778087),
        neutral900 = Color(0xFF151A1E),
        glass = Color(0xB3F5F3EE),
    )

/** The Fibonacci spacing scale. Nothing else is used for padding or gaps. */
public object Space {
  public val s1: Dp = 3.dp
  public val s2: Dp = 5.dp
  public val s3: Dp = 8.dp
  public val s4: Dp = 13.dp
  public val s5: Dp = 21.dp
  public val s6: Dp = 34.dp
  public val s7: Dp = 55.dp
  public val s8: Dp = 89.dp
}

/** Touch-target floors: every clickable is at least [Hit.h1]; rows and bars are [Hit.h2]. */
public object Hit {
  public val h1: Dp = 44.dp
  public val h2: Dp = 55.dp
}

/** The type ramp. `mobile*` is the phone ramp used by this app. */
public object FontSize {
  public val h1: TextUnit = 40.sp
  public val h2: TextUnit = 29.sp
  public val h3: TextUnit = 22.sp
  public val h4: TextUnit = 17.sp
  public val h5: TextUnit = 14.sp
  public val h6: TextUnit = 11.sp
  public val body: TextUnit = 15.sp
  public val small: TextUnit = 12.sp
  public val label: TextUnit = 10.sp
  public val mono: TextUnit = 13.sp
  public val mobileH1: TextUnit = 29.sp
  public val mobileH2: TextUnit = 22.sp
  public val mobileH3: TextUnit = 17.sp
  public val mobileBody: TextUnit = 15.sp
}

/** Motion durations, in milliseconds. No springs, ever. */
public object Duration {
  public const val D1: Int = 90
  public const val D2: Int = 140
  public const val D3: Int = 220
  public const val D4: Int = 340
}

/** The two easing curves of the language. */
public object Easing {
  public val mech: CubicBezierEasing = CubicBezierEasing(0.2f, 0f, 0.3f, 1f)
  public val snap: CubicBezierEasing = CubicBezierEasing(0.45f, 0f, 0.15f, 1f)
}

/**
 * Elevations for the things that float - menu, dialog, sheet. Board content is flat.
 *
 * Compose has one elevation scalar where CSS has offset+blur+colour, so the token's vertical offset
 * is what carries over; the renderer derives its own blur from it.
 */
public object Shadow {
  public val sm: Dp = 1.dp
  public val md: Dp = 6.dp
  public val lg: Dp = 24.dp
}

/** Backdrop blur radius for glass surfaces (API 31+). */
public const val GLASS_BLUR_RADIUS: Float = 16f
