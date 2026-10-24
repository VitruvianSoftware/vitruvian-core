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

import dev.vitruvian.design.SafeArea.Edges
import dev.vitruvian.design.SafeArea.Rect
import org.junit.Assert.assertEquals
import org.junit.Test

class SafeAreaTest {
  // A Pixel Fold's outer screen, as measured on the emulator: 1080 x 2342, a 152 px status bar
  // and a 59 px gesture bar.
  private val screen = Rect(0, 0, 1080, 2342)
  private val bars = Edges(left = 0, top = 152, right = 0, bottom = 59)

  @Test
  fun theSafeAreaIsTheWindowLessItsBars() {
    assertEquals(Rect(0, 152, 1080, 2283), SafeArea.of(screen, bars))
  }

  @Test
  fun aDialogWindowThatRunsUnderTheGestureBarIsPaddedClearOfIt() {
    // What the emulator showed: the dialog window starts below the status bar and runs to the
    // bottom of the screen, so the top costs nothing and the bottom costs the whole bar.
    val dialog = Rect(0, 152, 1080, 2342)
    assertEquals(Edges(0, 0, 0, 59), SafeArea.padding(dialog, SafeArea.of(screen, bars)))
  }

  @Test
  fun aFullScreenDialogIsPaddedOnBothEdges() {
    assertEquals(Edges(0, 152, 0, 59), SafeArea.padding(screen, SafeArea.of(screen, bars)))
  }

  @Test
  fun aKeyboardTheWindowWasAlreadyResizedAwayFromIsNotCountedTwice() {
    val withKeyboard = Edges(left = 0, top = 152, right = 0, bottom = 900)
    val resized = Rect(0, 152, 1080, 1442)
    assertEquals(Edges(0, 0, 0, 0), SafeArea.padding(resized, SafeArea.of(screen, withKeyboard)))
  }

  @Test
  fun aKeyboardOverAnUnresizedWindowIsPaddedFor() {
    val withKeyboard = Edges(left = 0, top = 152, right = 0, bottom = 900)
    val dialog = Rect(0, 152, 1080, 2342)
    assertEquals(Edges(0, 0, 0, 900), SafeArea.padding(dialog, SafeArea.of(screen, withKeyboard)))
  }

  @Test
  fun aLandscapeNavigationBarAndCutoutPadTheSides() {
    val landscape = Rect(0, 0, 2342, 1080)
    val sideBars = Edges(left = 120, top = 60, right = 90, bottom = 0)
    assertEquals(
        Edges(120, 60, 90, 0),
        SafeArea.padding(landscape, SafeArea.of(landscape, sideBars)),
    )
  }

  @Test
  fun aWindowOffsetOnScreenIsMeasuredInScreenCoordinates() {
    // A host window in the lower half of a split screen: its bars are relative to it.
    val lowerHalf = Rect(0, 1200, 1080, 2342)
    val safe = SafeArea.of(lowerHalf, Edges(0, 0, 0, 59))
    assertEquals(Edges(0, 0, 0, 59), SafeArea.padding(lowerHalf, safe))
    assertEquals(Edges(0, 1200, 0, 59), SafeArea.padding(screen, safe))
  }
}
