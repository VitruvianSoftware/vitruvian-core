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

package dev.vitruvian.design

import android.provider.Settings
import androidx.compose.foundation.Indication
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.invalidateDraw
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

/** JetBrains Mono - the display and mono family. Headings never go above weight 500. */
public val VitruvianMono: FontFamily =
    FontFamily(
        Font(R.font.jetbrains_mono_regular, FontWeight.Normal),
        Font(R.font.jetbrains_mono_medium, FontWeight.Medium),
        Font(R.font.jetbrains_mono_bold, FontWeight.Bold),
    )

/** IBM Plex Sans - body copy only. */
public val VitruvianBody: FontFamily =
    FontFamily(
        Font(R.font.ibm_plex_sans_regular, FontWeight.Normal),
        Font(R.font.ibm_plex_sans_medium, FontWeight.Medium),
        Font(R.font.ibm_plex_sans_semibold, FontWeight.SemiBold),
    )

/**
 * The phone type ramp, as the CSS defines it.
 *
 * Every style here is a literal transcription of a rule in
 * `packages/design-system/src/vitruvian.css`; where the CSS sets a size in `px` it is read as `sp`,
 * and `em` tracking carries over unchanged.
 */
@Immutable
public object VitruvianType {
  /** `.label` - 10 sp mono, tracked 0.16em, uppercase. */
  public val label: TextStyle =
      TextStyle(
          fontFamily = VitruvianMono,
          fontSize = FontSize.label,
          fontWeight = FontWeight.Medium,
          letterSpacing = 0.16.em,
      )

  /** The 9 sp variant the tab bar and rail use. */
  public val tabLabel: TextStyle = label.copy(fontSize = 9.sp, letterSpacing = 0.14.em)

  /** `.m-bar-title` - 17 sp display 500. */
  public val barTitle: TextStyle =
      TextStyle(
          fontFamily = VitruvianMono,
          fontSize = FontSize.mobileH3,
          fontWeight = FontWeight.Medium,
          letterSpacing = (-0.01).em,
      )

  /** Section heading - 22 sp display 500. */
  public val h2: TextStyle =
      TextStyle(
          fontFamily = VitruvianMono,
          fontSize = FontSize.mobileH2,
          fontWeight = FontWeight.Medium,
          letterSpacing = (-0.02).em,
      )

  /** `.metric-value` - tabular, tracked in. Size is set per use (26 / 32 / 38 sp). */
  public val metricValue: TextStyle =
      TextStyle(
          fontFamily = VitruvianMono,
          fontSize = 26.sp,
          fontWeight = FontWeight.Medium,
          letterSpacing = (-0.03).em,
      )

  /** `.btn` - mono 12 sp, tracked 0.08em, uppercase. */
  public val button: TextStyle =
      TextStyle(
          fontFamily = VitruvianMono,
          fontSize = FontSize.small,
          fontWeight = FontWeight.Medium,
          letterSpacing = 0.08.em,
      )

  /** `.btn-touch` raises the button ramp to 13 sp. */
  public val buttonTouch: TextStyle = button.copy(fontSize = FontSize.mono)

  /** Body copy - IBM Plex Sans 15 sp. */
  public val body: TextStyle =
      TextStyle(
          fontFamily = VitruvianBody,
          fontSize = FontSize.mobileBody,
      )

  /** `.list-title`. */
  public val listTitle: TextStyle = body

  /** `.list-sub` - mono 11 sp dim. */
  public val listSub: TextStyle = TextStyle(fontFamily = VitruvianMono, fontSize = FontSize.h6)

  /** `.mono` - tabular figures, size set per use. */
  public val mono: TextStyle = TextStyle(fontFamily = VitruvianMono, fontSize = FontSize.mono)

  /** `.status` and `.seg-opt` - mono 11 sp, tracked 0.06em, uppercase. */
  public val status: TextStyle =
      TextStyle(
          fontFamily = VitruvianMono,
          fontSize = FontSize.h6,
          letterSpacing = 0.06.em,
      )

  /** `.tag` - mono 10 sp 500, tracked 0.1em, uppercase. */
  public val tag: TextStyle =
      TextStyle(
          fontFamily = VitruvianMono,
          fontSize = FontSize.label,
          fontWeight = FontWeight.Medium,
          letterSpacing = 0.1.em,
      )

  /** `.term` - mono 13 sp, line-height 1.65. */
  public val terminal: TextStyle =
      TextStyle(
          fontFamily = VitruvianMono,
          fontSize = FontSize.mono,
          lineHeight = 21.45.sp,
      )

  /** `.log` - mono 12 sp, line-height 1.8. */
  public val log: TextStyle =
      TextStyle(
          fontFamily = VitruvianMono,
          fontSize = FontSize.small,
          lineHeight = 21.6.sp,
      )
}

/** The active colour roles. Defaults to dark - the board. */
public val LocalVitruvianColors: ProvidableCompositionLocal<VitruvianColors> =
    staticCompositionLocalOf {
      darkColors()
    }

/** Defaults to `color.text`; accent body copy opts in to `accentText`, never `accent`. */
public val LocalContentColor: ProvidableCompositionLocal<Color> = staticCompositionLocalOf {
  darkColors().text
}

/**
 * True when the platform asks for reduced motion.
 *
 * Every duration in the language collapses to zero under it and entering elements land at full
 * opacity, so animation call sites read this rather than the raw [Duration] constants.
 */
public val LocalReduceMotion: ProvidableCompositionLocal<Boolean> = staticCompositionLocalOf {
  false
}

/** Shorthand for the ambient colour roles. */
public val Vitruvian: VitruvianColors
  @Composable get() = LocalVitruvianColors.current

/** A duration that respects the reduce-motion setting. */
@Composable
public fun motion(durationMillis: Int): Int = if (LocalReduceMotion.current) 0 else durationMillis

/**
 * A flat press tint in place of the Material ripple.
 *
 * The language has no ripple, no bounded/unbounded distinction and no elevation change on press - a
 * pressed surface simply fills with `accentQuiet`.
 */
@Immutable
public class FlatIndication(private val tint: Color) : IndicationNodeFactory {
  override fun create(interactionSource: InteractionSource): DelegatableNode =
      FlatIndicationNode(interactionSource, tint)

  override fun equals(other: Any?): Boolean = other is FlatIndication && other.tint == tint

  override fun hashCode(): Int = tint.hashCode()
}

private class FlatIndicationNode(
    private val interactionSource: InteractionSource,
    private val tint: Color,
) : Modifier.Node(), DrawModifierNode {
  private var pressCount = 0
  private var pressed = false

  override fun onAttach() {
    coroutineScope.launch {
      interactionSource.interactions.collect { interaction ->
        when (interaction) {
          is PressInteraction.Press -> pressCount++
          is PressInteraction.Release -> pressCount--
          is PressInteraction.Cancel -> pressCount--
          else -> Unit
        }
        val next = pressCount > 0
        if (next != pressed) {
          pressed = next
          invalidateDraw()
        }
      }
    }
  }

  override fun ContentDrawScope.draw() {
    drawContent()
    if (pressed) {
      drawRect(color = tint)
    }
  }
}

/**
 * The theme entry point.
 *
 * Deliberately not a `MaterialTheme`: this language's roles do not map onto Material's, so the
 * colour, type and indication locals are provided directly.
 */
@Composable
public fun VitruvianTheme(
    dark: Boolean = true,
    content: @Composable () -> Unit,
) {
  val colors = if (dark) darkColors() else lightColors()
  val indication: Indication = FlatIndication(colors.accentQuiet)
  val reduceMotion = rememberReduceMotion()
  CompositionLocalProvider(
      LocalVitruvianColors provides colors,
      LocalContentColor provides colors.text,
      LocalIndication provides indication,
      LocalReduceMotion provides reduceMotion,
      content = content,
  )
}

/**
 * Reads the platform's "remove animations" accessibility setting.
 *
 * `ANIMATOR_DURATION_SCALE == 0` is what the system sets when a user turns animations off, and it
 * is the signal the language's reduce-motion rule hangs off.
 */
@Composable
private fun rememberReduceMotion(): Boolean {
  val resolver = LocalContext.current.contentResolver
  return remember(resolver) {
    Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
  }
}
