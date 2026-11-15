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

import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp
import java.io.File
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

  @Test
  fun terminalPaletteMeetsWcagContrastInBothThemes() {
    val dark = darkColors()
    val bg = terminalBackgroundColor().toArgb()
    assertEquals(dark.neutral900.toArgb(), bg)

    val tones =
        mapOf(
            "text" to dark.text.toArgb(),
            "textDim" to dark.textDim.toArgb(),
            "ok" to dark.ok.toArgb(),
            "warn" to dark.warn.toArgb(),
            "sanguineText" to dark.sanguineText.toArgb(),
        )
    tones.forEach { (name, fg) ->
      val ratio = A11y.contrastRatio(fgArgb = fg, bgArgb = bg)
      assertTrue("Expected dark $name on neutral900 >= 4.5:1, was $ratio", ratio >= 4.5)
    }
  }

  @Test
  fun lightThemeWarnOkAndPrimaryButtonMeetWcagAA() {
    val light = lightColors()
    val primaryRatio =
        A11y.contrastRatio(fgArgb = light.onAccent.toArgb(), bgArgb = light.accent.toArgb())
    assertTrue("Expected light onAccent on accent >= 4.5:1, was $primaryRatio", primaryRatio >= 4.5)

    val surfaces =
        listOf(
            "bg" to light.bg.toArgb(),
            "surface" to light.surface.toArgb(),
            "surface2" to light.surface2.toArgb(),
        )
    surfaces.forEach { (surfaceName, bg) ->
      val okRatio = A11y.contrastRatio(fgArgb = light.ok.toArgb(), bgArgb = bg)
      assertTrue("Expected light ok on $surfaceName >= 4.5:1, was $okRatio", okRatio >= 4.5)
      val warnRatio = A11y.contrastRatio(fgArgb = light.warn.toArgb(), bgArgb = bg)
      assertTrue("Expected light warn on $surfaceName >= 4.5:1, was $warnRatio", warnRatio >= 4.5)
    }
  }

  @Test
  fun statusLabelDoesNotRepeatStateWordAlreadyInCaption() {
    assertEquals("Idle", A11y.statusLabel(StatusTone.Neutral, text = "Idle"))
    assertEquals("OK", A11y.statusLabel(StatusTone.Ok, text = "OK"))
    assertEquals(
        "Warning: high CPU",
        A11y.statusLabel(StatusTone.Warn, text = "Warning: high CPU"),
    )
    assertEquals("Running, mac-mini", A11y.statusLabel(StatusTone.Run, text = "mac-mini"))
    assertEquals(
        "Degraded node",
        A11y.statusLabel(StatusTone.Warn, text = "Degraded node", label = "Degraded"),
    )
  }

  @Test
  fun hostChipDescriptionFormatsNameAndState() {
    assertEquals(
        "mac-mini, Connected. Opens settings.",
        A11y.hostChipDescription(name = "mac-mini", state = "Connected"),
    )
    assertEquals(
        "Mac, Unknown. Opens settings.",
        A11y.hostChipDescription(name = " ", state = ""),
    )
    assertEquals(
        "Trackpad. Drag to move the pointer, tap to click.",
        A11y.TRACKPAD_DESCRIPTION,
    )
  }

  @Test
  fun allIconsParseCleanlyAndIncludeGearMediaAndMic() {
    assertEquals(34, VitruvianIcons.ALL.size)
    listOf("SETTINGS", "PLAY", "PAUSE", "PLAY_PAUSE", "PREVIOUS", "NEXT", "MIC").forEach { name ->
      assertTrue("Missing icon $name", VitruvianIcons.ALL.containsKey(name))
    }
    VitruvianIcons.ALL.forEach { (name, pathData) ->
      val nodes = PathParser().parsePathString(pathData).toNodes()
      assertTrue("Icon $name produced no path nodes", nodes.isNotEmpty())
    }
  }

  @Test
  fun designSystemPrimitivesExposeAccessibilityRolesAndMinTargets() {
    val formSrc = readDesignSource("Form.kt")
    assertTrue("VSwitch must use Role.Switch toggleable", formSrc.contains("role = Role.Switch"))
    assertTrue("VSwitch must use .toggleable", formSrc.contains(".toggleable("))
    assertTrue("Segmented must use selectableGroup", formSrc.contains(".selectableGroup()"))
    assertTrue("Segmented must use Role.Tab selectable", formSrc.contains("role = Role.Tab"))
    assertTrue(
        "Segmented labels must ellipsize cleanly",
        formSrc.contains("overflow = TextOverflow.Ellipsis"),
    )

    val tagSrc = readDesignSource("Tag.kt")
    assertTrue(
        "Clickable Kbd keys must enforce 44 dp minWidth and minHeight",
        tagSrc.contains("minWidth = Hit.h1, minHeight = Hit.h1"),
    )

    val navSrc = readDesignSource("Nav.kt")
    assertTrue("HostChip must cap width at 160.dp", navSrc.contains("widthIn(max = 160.dp)"))
    assertTrue(
        "HostChip must use A11y.hostChipDescription",
        navSrc.contains("A11y.hostChipDescription("),
    )
    val railSrc = navSrc.substringAfter("public fun Rail(")
    val insetsIndex =
        railSrc.indexOf(
            ".windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Vertical))")
    val drawBehindIndex = railSrc.indexOf(".drawBehind {")
    assertTrue("Rail insetsIndex and drawBehind must exist", insetsIndex in 0 until drawBehindIndex)
  }

  private fun readDesignSource(fileName: String): String {
    val candidates =
        listOf(
            "packages/design-system-android/src/main/kotlin/dev/vitruvian/design/$fileName",
            "src/main/kotlin/dev/vitruvian/design/$fileName",
        )
    val path =
        candidates.map(::File).firstOrNull(File::isFile)
            ?: File(System.getenv("TEST_SRCDIR") ?: ".").walkTopDown().firstOrNull {
              it.isFile && it.name == fileName
            }
            ?: error("Unable to locate design-system source $fileName")
    return path.readText()
  }
}
