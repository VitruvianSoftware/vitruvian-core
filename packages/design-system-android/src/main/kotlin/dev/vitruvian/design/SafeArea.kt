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

/**
 * The geometry that keeps an overlay clear of the system bars, cutout and keyboard, in screen px.
 *
 * Plain Kotlin so a JVM test can pin it. See `OverlayWindow` in Overlay.kt for why the overlay
 * cannot simply read `WindowInsets` inside its own window.
 */
public object SafeArea {
  /** A rectangle in screen coordinates, px; [right] and [bottom] are exclusive. */
  public data class Rect(val left: Int, val top: Int, val right: Int, val bottom: Int)

  /** How far into each edge of a rectangle something unsafe reaches, px. */
  public data class Edges(val left: Int, val top: Int, val right: Int, val bottom: Int)

  /**
   * The safe area of a window at [window] on screen whose insets are [insets]: the window less the
   * bars, cutout and keyboard on each edge.
   */
  public fun of(window: Rect, insets: Edges): Rect =
      Rect(
          left = window.left + insets.left,
          top = window.top + insets.top,
          right = window.right - insets.right,
          bottom = window.bottom - insets.bottom,
      )

  /**
   * The padding [content] needs on each edge to stay inside [safe]: how far [content] reaches past
   * it, and zero on an edge where [content] already stops short.
   */
  public fun padding(content: Rect, safe: Rect): Edges =
      Edges(
          left = (safe.left - content.left).coerceAtLeast(0),
          top = (safe.top - content.top).coerceAtLeast(0),
          right = (content.right - safe.right).coerceAtLeast(0),
          bottom = (content.bottom - safe.bottom).coerceAtLeast(0),
      )
}
