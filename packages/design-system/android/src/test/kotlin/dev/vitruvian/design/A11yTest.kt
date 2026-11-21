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
  fun emptyStateActionsUseFlowRowSoButtonsWrapOnNarrowWidths() {
    val src =
        readDesignSource(
            "packages/design-system/android/src/main/kotlin/dev/vitruvian/design/States.kt")
    val emptyStateBlock =
        src.substringAfter("public fun EmptyState(").substringBefore("public fun Skeleton(")
    assertTrue("EmptyState must use FlowRow for actions", emptyStateBlock.contains("FlowRow("))
    assertTrue(
        "EmptyState actions parameter remains RowScope.() -> Unit",
        emptyStateBlock.contains("RowScope.() -> Unit"),
    )
  }

  @Test
  fun topBarBackActionHidesMarkAndResolvesSpokenDescription() {
    assertTrue(A11y.topBarShowMark(showMark = true, hasBackAction = false))
    assertFalse(A11y.topBarShowMark(showMark = true, hasBackAction = true))
    assertFalse(A11y.topBarShowMark(showMark = false, hasBackAction = false))
    assertFalse(A11y.topBarShowMark(showMark = false, hasBackAction = true))

    assertEquals("Back", A11y.topBarBackDescription(null))
    assertEquals("Back", A11y.topBarBackDescription("   "))
    assertEquals("Back to Settings", A11y.topBarBackDescription("Back to Settings"))
  }

  @Test
  fun topBarLeadingBackActionUsesHitH1AndButtonSemantics() {
    val src =
        readDesignSource(
            "packages/design-system/android/src/main/kotlin/dev/vitruvian/design/Nav.kt")
    val topBarBlock =
        src.substringAfter("public fun TopBar(").substringBefore("public fun HostChip(")
    assertTrue(
        "TopBar must accept optional onBack", topBarBlock.contains("onBack: (() -> Unit)? = null"))
    assertTrue("TopBar back button must meet Hit.h1 touch target", topBarBlock.contains("Hit.h1"))
    assertTrue("TopBar back button must expose Role.Button", topBarBlock.contains("Role.Button"))
    assertTrue(
        "TopBar back button must resolve spoken description via A11y",
        topBarBlock.contains("A11y.topBarBackDescription"),
    )
    assertTrue(
        "TopBar must gate VMark visibility via A11y.topBarShowMark",
        topBarBlock.contains("A11y.topBarShowMark"),
    )
  }

  @Test
  fun topBarGivesTitlePriorityOverHostChipAt200PercentScale() {
    // 100% scale on 360dp folded phone (277dp left after outer padding + 44dp back + 13dp gap):
    // both full "Settings" (~82dp) and trailing (~140dp) fit comfortably.
    val normal =
        A11y.allocateTopBarWidths(
            availableAfterLeadingPx = 277,
            gapPx = 13,
            titleIntrinsicWidthPx = 82,
            minTitleWidthPx = 82,
            hasTrailing = true,
            trailingIntrinsicWidthPx = 140,
            isSingleWordTitle = true,
            minTrailingFloorPx = 96,
        )
    assertEquals(140, normal.trailingMaxWidthPx)
    assertTrue(
        "Expected full title width at 100%, was ${normal.titleWidthPx}", normal.titleWidthPx >= 82)

    // 200% scale on 360dp folded phone: "Settings" needs 164dp, trailing wants 177dp (44 + 13 +
    // 120).
    // Title must keep the full word while trailing shrinks and ellipsizes the host chip first.
    val foldedAt200 =
        A11y.allocateTopBarWidths(
            availableAfterLeadingPx = 277,
            gapPx = 13,
            titleIntrinsicWidthPx = 164,
            minTitleWidthPx = 164,
            hasTrailing = true,
            trailingIntrinsicWidthPx = 177,
            isSingleWordTitle = true,
            minTrailingFloorPx = 96,
        )
    assertTrue(
        "Expected full single-word title width >= 164 on 360dp at 200%, was ${foldedAt200.titleWidthPx}",
        foldedAt200.titleWidthPx >= 164,
    )
    assertEquals(100, foldedAt200.trailingMaxWidthPx)

    // 200% scale on 411dp phone (328dp after leading): full "Settings" kept and trailing gets
    // remaining 151dp.
    val widePhoneAt200 =
        A11y.allocateTopBarWidths(
            availableAfterLeadingPx = 328,
            gapPx = 13,
            titleIntrinsicWidthPx = 164,
            minTitleWidthPx = 164,
            hasTrailing = true,
            trailingIntrinsicWidthPx = 177,
            isSingleWordTitle = true,
            minTrailingFloorPx = 96,
        )
    assertTrue(widePhoneAt200.titleWidthPx >= 164)
    assertEquals(151, widePhoneAt200.trailingMaxWidthPx)

    // Multi-word titles shrink trailing down to floor first and always protect the first word.
    val wandFirstWord = A11y.estimateFirstWordWidthPx(360, "VITRUVIAN WAND // AIR MOUSE")
    assertEquals("VITRUVIAN", A11y.firstTitleWord("VITRUVIAN WAND // AIR MOUSE"))
    assertFalse(A11y.isSingleWordTitle("Phone Bridge"))
    assertTrue(A11y.isSingleWordTitle("Settings"))
    val multiWordTight =
        A11y.allocateTopBarWidths(
            availableAfterLeadingPx = 290,
            gapPx = 13,
            titleIntrinsicWidthPx = 360,
            minTitleWidthPx = wandFirstWord,
            hasTrailing = true,
            trailingIntrinsicWidthPx = 200,
            isSingleWordTitle = false,
            minTrailingFloorPx = 96,
        )
    assertTrue(
        "Expected multi-word title to keep at least first word ($wandFirstWord), got ${multiWordTight.titleWidthPx}",
        multiWordTight.titleWidthPx >= wandFirstWord,
    )
    assertEquals(96, multiWordTight.trailingMaxWidthPx)

    // HostChip tightens max width smoothly at large accessibility font scales.
    assertEquals(160f, A11y.hostChipMaxWidthDp(1.0f))
    assertEquals(160f, A11y.hostChipMaxWidthDp(1.15f))
    assertEquals(120f, A11y.hostChipMaxWidthDp(1.6f))
    assertEquals(120f, A11y.hostChipMaxWidthDp(2.0f))

    val navSrc = stripKotlinComments(readDesignSource("Nav.kt"))
    val topBarBody = extractKotlinBlock(navSrc, "public fun TopBar(")
    assertTrue(
        "TopBar must allocate widths via A11y.allocateTopBarWidths",
        topBarBody.contains("A11y.allocateTopBarWidths("))
    val hostChipBody = extractKotlinBlock(navSrc, "public fun HostChip(")
    assertTrue(
        "HostChip must scale cap via A11y.hostChipMaxWidthDp",
        hostChipBody.contains("A11y.hostChipMaxWidthDp("))
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
  fun statusAnnouncementSuppressesBareDotDuplicateOfAdjacentTag() {
    assertNull(A11y.statusAnnouncement(StatusTone.Run, adjacentText = "running"))
    assertNull(A11y.statusAnnouncement(StatusTone.Ok, adjacentText = "ok"))
    assertNull(A11y.statusAnnouncement(StatusTone.Warn, adjacentText = "Warning: high"))
    assertEquals("OK", A11y.statusAnnouncement(StatusTone.Ok, adjacentText = "ready"))
    assertEquals("Warning", A11y.statusAnnouncement(StatusTone.Warn, adjacentText = "1 down"))
    assertEquals(
        "Running, mac-mini",
        A11y.statusAnnouncement(StatusTone.Run, text = "mac-mini", adjacentText = "running"))
  }

  @Test
  fun switchRowDescriptionJoinsNonBlankSegmentsWithoutDuplicateDotWord() {
    assertEquals(
        "Claude Code, Enable hook, ok",
        A11y.switchRowDescription(
            title = "Claude Code",
            subtitle = "Enable hook",
            statusTone = StatusTone.Ok,
            statusAdjacentText = "ok",
            trailingText = "ok",
        ),
    )
    assertEquals(
        "OK, Wake-on-LAN, Send magic packet",
        A11y.switchRowDescription(
            title = "Wake-on-LAN",
            subtitle = "Send magic packet",
            statusTone = StatusTone.Ok,
            statusAdjacentText = null,
            trailingText = null,
        ),
    )
  }

  @Test
  fun railLabelFontSizeScalesDownAt200PercentAndCapsAtLabelToken() {
    assertEquals(9f, A11y.railLabelFontSizeSp(baseSp = 9f, fontScale = 1.0f, maxScaledDp = 10f))
    assertEquals(9f, A11y.railLabelFontSizeSp(baseSp = 9f, fontScale = 1.1f, maxScaledDp = 10f))
    val at200 = A11y.railLabelFontSizeSp(baseSp = 9f, fontScale = 2.0f, maxScaledDp = 10f)
    assertEquals(5f, at200)
    assertEquals(10f, at200 * 2.0f)
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
    assertTrue(
        "Visual-only VSwitch must clear its own semantics when onCheckedChange == null",
        vSwitchBody.contains("clearAndSetSemantics {}"),
    )
    assertTrue(
        "Standalone VSwitch must expose label via contentDescription and clear child VText",
        vSwitchBody.contains("contentDescription = label"),
    )
    assertFalse("VSwitch check must not match VCheckbox", vSwitchBody.contains("Role.Checkbox"))

    val listItemSrc = stripKotlinComments(readDesignSource("ListItem.kt"))
    val listItemBody = extractKotlinBlock(listItemSrc, "public fun ListItem(")
    assertTrue(
        "ListItem must host Role.Switch toggleable when acting as a switch row",
        listItemBody.contains("role = Role.Switch") && listItemBody.contains(".toggleable("),
    )
    assertTrue(
        "ListItem must pass statusAdjacentText to Status",
        listItemBody.contains("Status(tone = status, adjacentText = statusAdjacentText"),
    )
    assertTrue(
        "ListItem switch row must use A11y.switchRowDescription and clear inner semantics",
        listItemBody.contains("A11y.switchRowDescription(") &&
            listItemBody.contains("clearAndSetSemantics {}"),
    )

    val dataDisplaySrc = stripKotlinComments(readDesignSource("DataDisplay.kt"))
    val statusBody = extractKotlinBlock(dataDisplaySrc, "public fun Status(")
    assertTrue(
        "Status must consult A11y.statusAnnouncement",
        statusBody.contains("A11y.statusAnnouncement("),
    )
    assertTrue(
        "Status must clear semantics when announcement is suppressed",
        statusBody.contains("clearAndSetSemantics {}"),
    )

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

    val navCellBody = extractKotlinBlock(navSrc, "private fun NavCell(")
    assertTrue(
        "Rail labels must clamp font size via A11y.railLabelFontSizeSp",
        navCellBody.contains("A11y.railLabelFontSizeSp("),
    )
    assertTrue(
        "Rail labels must allow 2-line wrap without ellipsis truncation",
        navCellBody.contains("maxLines = if (isRail) 2 else 1") &&
            navCellBody.contains("if (isRail) TextOverflow.Clip else TextOverflow.Ellipsis"),
    )
  }

  @Test
  fun vInputPlaceholderClearsChildTextSemanticsAndExposesEmptyHintDescription() {
    assertEquals(
        "e.g. Lock screen",
        A11y.inputPlaceholderDescription(value = "", placeholder = "e.g. Lock screen"),
    )
    assertNull(A11y.inputPlaceholderDescription(value = "", placeholder = "   "))
    assertNull(
        A11y.inputPlaceholderDescription(value = "Sleep", placeholder = "e.g. Lock screen"),
    )

    val formSrc = stripKotlinComments(readDesignSource("Form.kt"))
    val vInputBody = extractKotlinBlock(formSrc, "public fun VInput(")
    assertTrue(
        "VInput must compute empty-field hint description via A11y",
        vInputBody.contains("A11y.inputPlaceholderDescription("),
    )
    assertTrue(
        "VInput placeholder VText must clear semantics so accessibility trees do not read hints as text",
        vInputBody.contains("clearAndSetSemantics {}"),
    )
    assertTrue(
        "VInput placeholder must dim via PLACEHOLDER_ALPHA",
        vInputBody.contains("PLACEHOLDER_ALPHA"),
    )
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
    val shortName = fileName.substringAfterLast('/')
    val directCandidates =
        listOf(
            fileName,
            "packages/design-system/android/src/main/kotlin/dev/vitruvian/design/$shortName",
            "src/main/kotlin/dev/vitruvian/design/$shortName",
        )
    val base = System.getenv("TEST_SRCDIR")
    val runfileCandidates =
        if (base != null) {
          listOf("_main", "vitruvian_core", "").map { sub ->
            if (sub.isEmpty()) File(base, fileName) else File(File(base, sub), fileName)
          }
        } else {
          emptyList()
        }
    val path =
        directCandidates.map(::File).firstOrNull(File::isFile)
            ?: runfileCandidates.firstOrNull(File::isFile)
            ?: File(base ?: ".").walkTopDown().firstOrNull { it.isFile && it.name == shortName }
            ?: error("Unable to locate design-system source $fileName")
    return path.readText()
  }
}
