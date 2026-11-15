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

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp

/** One line of terminal output: a prefix glyph, the text, and its colour role. */
public data class TerminalLine(val prefix: String, val text: String, val tone: TerminalTone)

/** The colour roles terminal output uses. */
public enum class TerminalTone {
  Text,
  Dim,
  Ok,
  Warn,
  Err,
}

/** Fixed dark background used by terminal surfaces in both light and dark themes. */
public fun terminalBackgroundColor(): Color = darkColors().neutral900

/**
 * Fixed light-on-dark colour for a [TerminalTone] in both themes so terminal output always meets
 * contrast against `neutral900`.
 */
public fun TerminalTone.terminalColor(dark: VitruvianColors = darkColors()): Color =
    when (this) {
      TerminalTone.Text -> dark.text
      TerminalTone.Dim -> dark.textDim
      TerminalTone.Ok -> dark.ok
      TerminalTone.Warn -> dark.warn
      TerminalTone.Err -> dark.sanguineText
    }

@Composable
private fun terminalColor(tone: TerminalTone, dark: VitruvianColors = darkColors()): Color =
    tone.terminalColor(dark)

/**
 * `.term` - the terminal ground.
 *
 * The prefix column is always `accent-400`, which is what makes a `$` or a `>` read as a prompt
 * rather than as content. Terminal surfaces always use the fixed light-on-dark palette in both
 * themes.
 */
@Composable
public fun Terminal(
    lines: List<TerminalLine>,
    modifier: Modifier = Modifier,
    fontSize: TextUnit = FontSize.mono,
    cursor: Boolean = false,
    bottomAnchored: Boolean = false,
) {
  val colors = Vitruvian
  val dark = remember { darkColors() }
  Column(
      modifier =
          modifier
              .fillMaxWidth()
              .background(dark.neutral900)
              .border(1.dp, colors.divider)
              .padding(horizontal = Space.s4, vertical = Space.s3),
      verticalArrangement = if (bottomAnchored) Arrangement.Bottom else Arrangement.Top,
  ) {
    lines.forEach { line ->
      Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
        VText(
            text = line.prefix,
            style = VitruvianType.terminal.copy(fontSize = fontSize),
            color = dark.accent400,
            softWrap = false,
        )
        VText(
            text = line.text,
            style = VitruvianType.terminal.copy(fontSize = fontSize),
            color = terminalColor(line.tone, dark),
        )
      }
    }
    if (cursor) {
      BlinkingCursor()
    }
  }
}

/** `.code` - a framed monospace snippet block with optional title header and [CopyButton]. */
@Composable
public fun Code(
    code: String,
    modifier: Modifier = Modifier,
    title: String? = null,
    copyable: Boolean = false,
) {
  val colors = Vitruvian
  val dark = remember { darkColors() }
  Column(
      modifier = modifier.fillMaxWidth().background(dark.neutral900).border(1.dp, colors.divider),
  ) {
    if (title != null || copyable) {
      Row(
          modifier =
              Modifier.fillMaxWidth()
                  .bottomHairline(dark.divider)
                  .padding(horizontal = Space.s4, vertical = Space.s2),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.SpaceBetween,
      ) {
        Label(text = title ?: "SNIPPET", color = dark.textDim)
        if (copyable) {
          CopyButton(value = code, colors = dark)
        }
      }
    }
    VText(
        text = code,
        modifier = Modifier.fillMaxWidth().padding(horizontal = Space.s4, vertical = Space.s3),
        style = VitruvianType.terminal,
        color = dark.text,
    )
  }
}

/**
 * The 7x13 accent block that marks a live agent or shell.
 *
 * A hard on/off step rather than a fade - the CSS animation is `steps(1)`, and under reduce-motion
 * the block simply stays lit.
 */
@Composable
public fun BlinkingCursor(modifier: Modifier = Modifier) {
  val dark = remember { darkColors() }
  val lit =
      if (LocalReduceMotion.current) {
        true
      } else {
        val transition = rememberInfiniteTransition(label = "cursor")
        val phase by
            transition.animateFloat(
                initialValue = 0f,
                targetValue = 1f,
                animationSpec =
                    infiniteRepeatable(
                        animation = tween(durationMillis = CURSOR_PERIOD_MS, easing = LinearEasing),
                        repeatMode = RepeatMode.Restart,
                    ),
                label = "cursorPhase",
            )
        phase < HALF
      }
  Box(
      modifier =
          modifier
              .width(CURSOR_WIDTH)
              .height(CURSOR_HEIGHT)
              .alpha(if (lit) 1f else 0f)
              .background(dark.accentText),
  )
}

private const val HALF = 0.5f
private const val CURSOR_PERIOD_MS = 1000
private val CURSOR_WIDTH = 7.dp
private val CURSOR_HEIGHT = 13.dp
