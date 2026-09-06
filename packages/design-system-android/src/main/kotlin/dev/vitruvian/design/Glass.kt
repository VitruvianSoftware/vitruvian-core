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

import android.os.Build
import android.view.WindowManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider

/**
 * Glass surfaces.
 *
 * ## The trap this file exists to avoid
 *
 * `Modifier.graphicsLayer { renderEffect = RenderEffect.createBlurEffect(...) }` blurs the layer's
 * OWN subtree. Put it on a glass surface and it blurs that surface's icons, labels and body text --
 * it can never reach the scene behind, because the scene behind is not in the layer. That is the
 * exact inverse of frosted glass, and it is what shipped: the folded shell's tab bar rendered its
 * five icons and labels as unreadable smudges.
 *
 * Compose has no backdrop-blur modifier. Two things behind glass, two mechanisms:
 * - **A surface in its own window** (dialog, sheet) can ask the platform to blur everything behind
 *   the window: [blurBehindWindow]. This is a true backdrop blur and is what the design means.
 * - **A surface in the main window** (the tab bar) has no such API. Reaching the content behind it
 *   means recording that content into a `GraphicsLayer` and re-drawing it blurred, which is a real
 *   feature and not something to fake with a self-blur. The tab bar does not need one anyway: the
 *   shell stacks it BELOW the body in a `Column`, so nothing is behind it but `color.bg`, and the
 *   66%-alpha tint over that ground is the whole effect.
 *
 * So there is deliberately no `Modifier.glassBlur()` any more. A glass surface paints its tint; a
 * glass WINDOW additionally asks for the blur behind it.
 */

/**
 * True when the platform can blur behind a window.
 *
 * API 31+ is necessary but not sufficient: cross-window blur is a system-wide toggle the device can
 * withdraw at runtime (battery saver, or a GPU the compositor has ruled out), which is why this is
 * read per call rather than cached.
 */
public val supportsGlass: Boolean
  get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

/**
 * Asks the platform to blur whatever is behind THIS dialog's window.
 *
 * Call from inside a `Dialog { }`. A no-op off a dialog window, below API 31, or when the device
 * has cross-window blur switched off -- in every one of those cases the surface still paints its
 * tint over the 55% scrim, which is the documented fallback.
 *
 * The flag is removed on dispose so a dismissed dialog does not leave the window blurred.
 */
@Composable
public fun blurBehindWindow(radius: Float = GLASS_BLUR_RADIUS) {
  val view = LocalView.current
  DisposableEffect(view, radius) {
    val window = (view.parent as? DialogWindowProvider)?.window
    if (window == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
      onDispose {}
    } else {
      window.addFlags(WindowManager.LayoutParams.FLAG_BLUR_BEHIND)
      window.attributes =
          window.attributes.also { params -> params.blurBehindRadius = radius.toInt() }
      onDispose {
        window.clearFlags(WindowManager.LayoutParams.FLAG_BLUR_BEHIND)
        window.attributes = window.attributes.also { params -> params.blurBehindRadius = 0 }
      }
    }
  }
}
