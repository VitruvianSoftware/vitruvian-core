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

package dev.vitruvian.remote.shell

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.window.core.layout.WindowSizeClass
import androidx.window.core.layout.WindowWidthSizeClass
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker

/**
 * The postures the shell draws for.
 *
 * Half-open comes in two orientations and they are different layouts, not one: with the hinge
 * horizontal (a laptop on a table) the dock belongs below the crease; with the hinge vertical (a
 * book, or a laptop-shaped fold on a phone whose rotation is locked to portrait -- which is how the
 * real Fold first presented it) the dock belongs to the right of the crease. Either way the split
 * must sit ON the hinge; content straddling a fold is the one thing a foldable layout is for
 * avoiding.
 */
public enum class Posture {
  Folded,
  Unfolded,
  Tabletop,
  Book,
}

/** What the shell needs to know about the window it is in. */
@Immutable
public data class DeviceLayout(
    val posture: Posture,
    /** Where a horizontal hinge ends, in window pixels, when the device is half-opened. */
    val hingeBottomPx: Int?,
    /** Where a vertical hinge ends, in window pixels, when the device is half-opened. */
    val hingeRightPx: Int? = null,
) {
  /** Compact width gets the tab bar; anything wider gets the rail. */
  public val showRail: Boolean
    get() = posture != Posture.Folded

  public val showTabBar: Boolean
    get() = posture == Posture.Folded

  public val isTabletop: Boolean
    get() = posture == Posture.Tabletop

  public val isBook: Boolean
    get() = posture == Posture.Book
}

/**
 * Resolves the posture from the window size class and the folding feature.
 *
 * Width decides the shell (compact -> one column and a tab bar, medium or expanded -> the rail),
 * and the folding feature decides whether the rail layout is the flat one or the tabletop one. A
 * horizontal hinge that is half-opened is tabletop; everything else that is wide is simply
 * unfolded.
 */
@Composable
public fun rememberDeviceLayout(): DeviceLayout {
  val context = LocalContext.current
  val activity = remember(context) { context.findActivity() }
  val configuration = LocalConfiguration.current
  val widthClass =
      remember(configuration.screenWidthDp, configuration.screenHeightDp) {
        WindowSizeClass.compute(
                configuration.screenWidthDp.toFloat(),
                configuration.screenHeightDp.toFloat(),
            )
            .windowWidthSizeClass
      }
  val fold by
      produceState<FoldingFeature?>(initialValue = null, activity) {
        val current = activity ?: return@produceState
        WindowInfoTracker.getOrCreate(current).windowLayoutInfo(current).collect { info ->
          value = info.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()
        }
      }

  val wide = widthClass != WindowWidthSizeClass.COMPACT
  val halfOpen = fold?.state == FoldingFeature.State.HALF_OPENED
  val horizontal = fold?.orientation == FoldingFeature.Orientation.HORIZONTAL
  val tabletop = halfOpen && horizontal
  val book = halfOpen && !horizontal

  return DeviceLayout(
      posture =
          when {
            tabletop && wide -> Posture.Tabletop
            book && wide -> Posture.Book
            wide -> Posture.Unfolded
            else -> Posture.Folded
          },
      hingeBottomPx = if (tabletop) fold?.bounds?.bottom else null,
      hingeRightPx = if (book) fold?.bounds?.right else null,
  )
}

/** Unwraps the `Activity` a Compose `Context` is hosted in, if there is one. */
private tailrec fun Context.findActivity(): Activity? =
    when (this) {
      is Activity -> this
      is ContextWrapper -> baseContext.findActivity()
      else -> null
    }
