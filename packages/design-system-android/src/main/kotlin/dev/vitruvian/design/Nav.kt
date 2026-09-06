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

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/** One navigation destination, as both the tab bar and the rail render it. */
public data class NavItem(
    val key: String,
    val label: String,
    val iconPath: String,
    val onSelect: () -> Unit,
)

private val RAIL_WIDTH = 89.dp
private val ACTIVE_RULE = 2.dp

/** The share of a tab's width the active rule spans - `left:25%; right:25%` in the CSS. */
private const val RULE_INSET = 0.25f

/**
 * `.m-bar` - the 55 dp top bar.
 *
 * The VMark is hidden when the rail is showing it instead, which is why [showMark] is a parameter
 * rather than something the bar decides.
 */
@Composable
public fun TopBar(
    title: String,
    modifier: Modifier = Modifier,
    showMark: Boolean = true,
    trailing: @Composable (RowScope.() -> Unit)? = null,
) {
  val colors = Vitruvian
  Row(
      modifier =
          modifier
              .fillMaxWidth()
              .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top))
              .defaultMinSize(minHeight = Hit.h2)
              .bottomHairline(colors.divider)
              .padding(horizontal = Space.s4),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    if (showMark) {
      VMark(markSize = 17.dp)
    }
    VText(
        text = title,
        modifier = Modifier.weight(1f),
        style = VitruvianType.barTitle,
        color = colors.text,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        softWrap = false,
    )
    trailing?.invoke(this)
  }
}

/**
 * The host chip: a [Status] inside a divider border.
 *
 * Tapping it always goes to Hosts, in every posture - it is the only way to reach that destination
 * when the tab bar is showing.
 */
@Composable
public fun HostChip(
    text: String,
    tone: StatusTone,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
  Box(
      modifier =
          modifier
              .defaultMinSize(minHeight = 32.dp)
              .border(1.dp, Vitruvian.divider)
              .clickable(onClick = onClick)
              .padding(horizontal = Space.s3, vertical = 6.dp),
      contentAlignment = Alignment.Center,
  ) {
    Status(tone = tone, text = text)
  }
}

/**
 * `.m-tabbar` - the folded shell's five-tab glass bar.
 *
 * The active tab is marked by a 2 dp accent rule on its **top** edge; the rail marks the same state
 * on the **left** edge instead.
 */
@Composable
public fun TabBar(
    items: List<NavItem>,
    selectedKey: String,
    modifier: Modifier = Modifier,
) {
  val colors = Vitruvian
  Row(
      modifier =
          modifier
              .fillMaxWidth()
              .then(if (supportsGlass) Modifier.glassBlur() else Modifier)
              .background(if (supportsGlass) colors.glass else colors.surface)
              .drawBehind { drawRect(color = colors.divider, size = Size(size.width, 1.dp.toPx())) }
              .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom)),
  ) {
    items.forEach { item ->
      NavCell(
          item = item,
          selected = item.key == selectedKey,
          modifier = Modifier.weight(1f),
          rule = NavRule.Top,
      )
    }
  }
}

/** Where a nav cell draws its active rule. */
private enum class NavRule {
  Top,
  Left
}

@Composable
private fun NavCell(
    item: NavItem,
    selected: Boolean,
    rule: NavRule,
    modifier: Modifier = Modifier,
) {
  val colors = Vitruvian
  val content = if (selected) colors.accentText else colors.textDim
  Column(
      modifier =
          modifier
              .defaultMinSize(minHeight = Hit.h2)
              .clickable(onClick = item.onSelect)
              .drawBehind {
                if (!selected) return@drawBehind
                when (rule) {
                  NavRule.Top ->
                      drawRect(
                          color = colors.accent,
                          topLeft = Offset(size.width * RULE_INSET, 0f),
                          size = Size(size.width * (1f - 2 * RULE_INSET), ACTIVE_RULE.toPx()),
                      )
                  NavRule.Left ->
                      drawRect(
                          color = colors.accent,
                          size = Size(ACTIVE_RULE.toPx(), size.height),
                      )
                }
              }
              .padding(vertical = Space.s2),
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.spacedBy(Space.s1, Alignment.CenterVertically),
  ) {
    VIcon(path = item.iconPath, color = content)
    VText(
        text = item.label.uppercase(),
        style = VitruvianType.tabLabel,
        color = content,
        maxLines = 1,
        softWrap = false,
    )
  }
}

/**
 * The unfolded shell's 89 dp rail.
 *
 * Carries every destination including Hosts, then the Dock toggle and the host status square at the
 * bottom.
 */
@Composable
public fun Rail(
    items: List<NavItem>,
    selectedKey: String,
    dockOpen: Boolean,
    onToggleDock: () -> Unit,
    hostLabel: String,
    hostTone: StatusTone,
    modifier: Modifier = Modifier,
) {
  val colors = Vitruvian
  Column(
      modifier =
          modifier
              .width(RAIL_WIDTH)
              .fillMaxHeight()
              .drawBehind {
                drawRect(
                    color = colors.divider,
                    topLeft = Offset(size.width - 1.dp.toPx(), 0f),
                    size = Size(1.dp.toPx(), size.height),
                )
              }
              .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Vertical))
              .padding(top = Space.s3),
      horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Box(
        modifier = Modifier.fillMaxWidth().height(Hit.h2),
        contentAlignment = Alignment.Center,
    ) {
      VMark(markSize = 18.dp)
    }
    items.forEach { item ->
      NavCell(
          item = item,
          selected = item.key == selectedKey,
          modifier = Modifier.fillMaxWidth(),
          rule = NavRule.Left,
      )
    }
    Box(modifier = Modifier.weight(1f))
    NavCell(
        item =
            NavItem(
                key = "dock",
                label = "Dock",
                iconPath = VitruvianIcons.PANEL_RIGHT,
                onSelect = onToggleDock,
            ),
        selected = dockOpen,
        modifier = Modifier.fillMaxWidth(),
        rule = NavRule.Left,
    )
    Column(
        modifier = Modifier.padding(Space.s4),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Space.s2),
    ) {
      Status(tone = hostTone)
      VText(
          text = hostLabel.uppercase(),
          style = VitruvianType.tabLabel,
          color = colors.textDim,
          maxLines = 1,
          softWrap = false,
      )
    }
  }
}

/** `.m-section` - the 21/13/8 padding every section header sits in. */
@Composable
public fun Section(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
  Column(
      modifier =
          modifier
              .fillMaxWidth()
              .padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3),
      content = content,
  )
}

/** A section header that carries a trailing control on the same baseline. */
@Composable
public fun SectionHeader(
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit,
) {
  Row(
      modifier =
          modifier
              .fillMaxWidth()
              .padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s4),
      content = content,
  )
}
