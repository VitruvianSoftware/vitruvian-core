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

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class A11yTest {
  @Test
  fun hitH1TokenIs44dp() {
    assertEquals(44.dp, Hit.h1)
  }

  @Test
  fun vIconWithNullDescriptionIsDecorativeAndClearsSemantics() {
    val semantics = A11y.iconSemantics(null)
    assertTrue(semantics.isDecorative)
    assertNull(semantics.contentDescription)
  }

  @Test
  fun vIconWithDescriptionExposesImageSemantics() {
    val semantics = A11y.iconSemantics("Settings and hosts")
    assertFalse(semantics.isDecorative)
    assertEquals("Settings and hosts", semantics.contentDescription)
  }

  @Test
  fun statusToneMapsToSpokenWordsIncludesCaptionAndRespectsCustomLabel() {
    assertEquals("OK", A11y.statusLabel(StatusTone.Ok))
    assertEquals("Warning", A11y.statusLabel(StatusTone.Warn))
    assertEquals("Error", A11y.statusLabel(StatusTone.Crit))
    assertEquals("Idle", A11y.statusLabel(StatusTone.Neutral))
    assertEquals("Running", A11y.statusLabel(StatusTone.Run))
    assertEquals("OK, paired", A11y.statusLabel(StatusTone.Ok, text = "paired"))
    assertEquals("Degraded", A11y.statusLabel(StatusTone.Warn, label = "Degraded"))
    assertEquals(
        "Degraded, 2 nodes",
        A11y.statusLabel(StatusTone.Warn, text = "2 nodes", label = "Degraded"))
  }

  @Test
  fun tagSemanticsAppliesInteractiveRoleAndSelectedOnlyWhenClickable() {
    val staticTag = A11y.tagSemantics(clickable = false, selected = null)
    assertFalse(staticTag.interactive)
    assertFalse(staticTag.hasButtonRole)
    assertNull(staticTag.selected)

    val nonClickableWithSelected = A11y.tagSemantics(clickable = false, selected = true)
    assertFalse(nonClickableWithSelected.interactive)
    assertFalse(nonClickableWithSelected.hasButtonRole)
    assertNull(nonClickableWithSelected.selected)

    val clickableTag = A11y.tagSemantics(clickable = true, selected = null)
    assertTrue(clickableTag.interactive)
    assertTrue(clickableTag.hasButtonRole)
    assertNull(clickableTag.selected)

    val selectedTag = A11y.tagSemantics(clickable = true, selected = true)
    assertTrue(selectedTag.interactive)
    assertTrue(selectedTag.hasButtonRole)
    assertEquals(true, selectedTag.selected)
  }

  @Test
  fun navItemUsesLabelAsContentDescriptionOnlyWhenIconOnly() {
    assertNull(A11y.navIconDescription(label = "Home", iconOnly = false))
    assertEquals("Home", A11y.navIconDescription(label = "Home", iconOnly = true))
  }

  @Test
  fun glyphButtonsResolveSpokenDescriptionsAndRespectExplicitOverrides() {
    assertEquals("Previous track", A11y.buttonContentDescription("⏮"))
    assertEquals("Play", A11y.buttonContentDescription("▶"))
    assertEquals("Pause", A11y.buttonContentDescription("⏸"))
    assertEquals("Next track", A11y.buttonContentDescription("⏭"))
    assertNull(A11y.buttonContentDescription("−"))
    assertNull(A11y.buttonContentDescription("+"))
    assertNull(A11y.buttonContentDescription("×"))
    assertEquals(
        "Brightness down",
        A11y.buttonContentDescription("−", contentDescription = "Brightness down"),
    )
    assertNull(A11y.buttonContentDescription("Send"))
  }
}
