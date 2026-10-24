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

import org.junit.Assert.assertEquals
import org.junit.Test

class OptionListTest {
  @Test
  fun aLongListOpensWithTheCurrentValueInViewBelowTwoRowsOfContext() {
    // Quiet hours "From" at 22:00: 24 slots, the 23rd selected.
    assertEquals(20, OptionList.firstVisibleIndex(selectedIndex = 22, count = 24))
  }

  @Test
  fun aValueNearTheTopDoesNotScrollPastTheStart() {
    assertEquals(0, OptionList.firstVisibleIndex(selectedIndex = 0, count = 24))
    assertEquals(0, OptionList.firstVisibleIndex(selectedIndex = 1, count = 24))
    assertEquals(0, OptionList.firstVisibleIndex(selectedIndex = 2, count = 24))
    assertEquals(1, OptionList.firstVisibleIndex(selectedIndex = 3, count = 24))
  }

  @Test
  fun noCurrentValueOpensAtTheTop() {
    assertEquals(0, OptionList.firstVisibleIndex(selectedIndex = -1, count = 24))
    assertEquals(0, OptionList.firstVisibleIndex(selectedIndex = -1, count = 0))
  }

  @Test
  fun aStaleIndexPastTheEndOpensAtTheTopRatherThanOnNothing() {
    assertEquals(0, OptionList.firstVisibleIndex(selectedIndex = 9, count = 3))
  }

  @Test
  fun leadRowsIsAdjustableAndNeverNegative() {
    assertEquals(10, OptionList.firstVisibleIndex(selectedIndex = 10, count = 24, leadRows = 0))
    assertEquals(10, OptionList.firstVisibleIndex(selectedIndex = 10, count = 24, leadRows = -4))
    assertEquals(5, OptionList.firstVisibleIndex(selectedIndex = 10, count = 24, leadRows = 5))
  }

  @Test
  fun tappingAnAvailableOtherValueAppliesIt() {
    assertEquals(OptionList.Tap.Apply, OptionList.tap(enabled = true, selected = false))
  }

  @Test
  fun tappingTheCurrentValueClosesEvenThoughCallersDisableIt() {
    // android-remote disables the current speaker so it is never re-sent; it must still close.
    assertEquals(OptionList.Tap.Dismiss, OptionList.tap(enabled = false, selected = true))
    assertEquals(OptionList.Tap.Dismiss, OptionList.tap(enabled = true, selected = true))
  }

  @Test
  fun tappingAnUnavailableValueDoesNothing() {
    // It used to close the sheet, which reads as "chosen" when nothing was sent.
    assertEquals(OptionList.Tap.Ignore, OptionList.tap(enabled = false, selected = false))
  }
}
