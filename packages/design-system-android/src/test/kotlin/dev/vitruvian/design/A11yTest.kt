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
    val bg = terminalBackgroundColor().toArgb()
    assertEquals(darkColors().neutral900.toArgb(), bg)

    for (tone in TerminalTone.entries) {
      val fg = tone.terminalColor().toArgb()
      val ratio = A11y.contrastRatio(fgArgb = fg, bgArgb = bg)
      assertTrue(
          "Expected $tone.terminalColor() on terminalBackgroundColor() >= 4.5:1, was $ratio",
          ratio >= 4.5,
      )
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
    val formSrc = stripKotlinComments(readDesignSource("Form.kt"))
    val vSwitchBody = extractKotlinBlock(formSrc, "public fun VSwitch(")
    assertTrue(
        "VSwitch must use Role.Switch toggleable", vSwitchBody.contains("role = Role.Switch"))
    assertTrue("VSwitch must use .toggleable", vSwitchBody.contains(".toggleable("))
    assertFalse("VSwitch check must not match VCheckbox", vSwitchBody.contains("Role.Checkbox"))

    val segmentedBody = extractKotlinBlock(formSrc, "public fun Segmented(")
    assertTrue("Segmented must use selectableGroup", segmentedBody.contains(".selectableGroup()"))
    assertTrue("Segmented must use .selectable(", segmentedBody.contains(".selectable("))
    assertTrue("Segmented must use Role.Tab selectable", segmentedBody.contains("role = Role.Tab"))
    assertTrue(
        "Segmented labels must ellipsize cleanly",
        segmentedBody.contains("overflow = TextOverflow.Ellipsis"),
    )

    val tagSrc = stripKotlinComments(readDesignSource("Tag.kt"))
    val kbdBody = extractKotlinBlock(tagSrc, "public fun Kbd(")
    assertTrue(
        "Clickable Kbd keys must gate min size on onClick != null",
        kbdBody.contains("if (onClick != null)"),
    )
    assertTrue(
        "Clickable Kbd keys must enforce 44 dp minWidth and minHeight",
        kbdBody.contains("minWidth = Hit.h1, minHeight = Hit.h1"),
    )

    val navSrc = stripKotlinComments(readDesignSource("Nav.kt"))
    val hostChipBody = extractKotlinBlock(navSrc, "public fun HostChip(")
    assertTrue("HostChip must cap width at 160.dp", hostChipBody.contains("widthIn(max = 160.dp)"))
    assertTrue(
        "HostChip must use A11y.hostChipDescription",
        hostChipBody.contains("A11y.hostChipDescription("),
    )

    val railBody = extractKotlinBlock(navSrc, "public fun Rail(")
    val insetsIndex =
        railBody.indexOf(
            ".windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Vertical))")
    val drawBehindIndex = railBody.indexOf(".drawBehind {")
    assertTrue("Rail insetsIndex and drawBehind must exist", insetsIndex in 0 until drawBehindIndex)
  }

  private fun stripKotlinComments(source: String): String {
    val out = StringBuilder(source.length)
    var i = 0
    while (i < source.length) {
      when {
        source.startsWith("//", i) -> {
          while (i < source.length && source[i] != '\n') i++
        }
        source.startsWith("/*", i) -> {
          val end = source.indexOf("*/", i + 2)
          i = if (end == -1) source.length else end + 2
          out.append(' ')
        }
        source.startsWith("\"\"\"", i) -> {
          out.append("\"\"\"")
          i += 3
          val end = source.indexOf("\"\"\"", i)
          if (end == -1) {
            out.append(source.substring(i))
            i = source.length
          } else {
            out.append(source, i, end + 3)
            i = end + 3
          }
        }
        source[i] == '"' || source[i] == '\'' -> {
          val quote = source[i]
          out.append(quote)
          i++
          while (i < source.length) {
            val c = source[i]
            out.append(c)
            i++
            if (c == '\\' && i < source.length) {
              out.append(source[i])
              i++
            } else if (c == quote) {
              break
            }
          }
        }
        else -> {
          out.append(source[i])
          i++
        }
      }
    }
    return out.toString()
  }

  private fun extractKotlinBlock(commentFreeSource: String, anchor: String): String {
    val start = commentFreeSource.indexOf(anchor)
    assertTrue("Anchor `$anchor` not found", start >= 0)
    var i = start + anchor.length
    if (anchor.endsWith("(")) {
      var parenDepth = 1
      while (i < commentFreeSource.length && parenDepth > 0) {
        i =
            skipLiteralOrAdvance(commentFreeSource, i) { c ->
              when (c) {
                '(' -> parenDepth++
                ')' -> parenDepth--
              }
            }
      }
      assertEquals("Unbalanced parameter list for `$anchor`", 0, parenDepth)
    }
    while (i < commentFreeSource.length && commentFreeSource[i] != '{') {
      i = skipLiteralOrAdvance(commentFreeSource, i) {}
    }
    assertTrue("Opening `{` not found for `$anchor`", i < commentFreeSource.length)
    val bodyStart = i + 1
    i = bodyStart
    var braceDepth = 1
    while (i < commentFreeSource.length && braceDepth > 0) {
      i =
          skipLiteralOrAdvance(commentFreeSource, i) { c ->
            when (c) {
              '{' -> braceDepth++
              '}' -> braceDepth--
            }
          }
    }
    assertEquals("Unbalanced body braces for `$anchor`", 0, braceDepth)
    return commentFreeSource.substring(bodyStart, i - 1)
  }

  private inline fun skipLiteralOrAdvance(
      source: String,
      index: Int,
      onCodeChar: (Char) -> Unit,
  ): Int {
    if (source.startsWith("\"\"\"", index)) {
      val end = source.indexOf("\"\"\"", index + 3)
      return if (end == -1) source.length else end + 3
    }
    val ch = source[index]
    if (ch == '"' || ch == '\'') {
      var i = index + 1
      while (i < source.length) {
        if (source[i] == '\\') {
          i += 2
        } else if (source[i] == ch) {
          return i + 1
        } else {
          i++
        }
      }
      return source.length
    }
    onCodeChar(ch)
    return index + 1
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
