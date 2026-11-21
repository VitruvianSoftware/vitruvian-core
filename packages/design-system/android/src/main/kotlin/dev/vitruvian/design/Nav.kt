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
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** One navigation destination, as both the tab bar and the rail render it. */
public data class NavItem(
    val key: String,
    val label: String,
    val iconPath: String,
    val onSelect: () -> Unit,
    val iconOnly: Boolean = false,
)

private val RAIL_WIDTH = 89.dp
private val ACTIVE_RULE = 2.dp

/** The share of a tab's width the active rule spans - `left:25%; right:25%` in the CSS. */
private const val RULE_INSET = 0.25f

/** Mirror of `VitruvianIcons.CHEVRON_RIGHT` kept private so `Icons.kt` stays in web parity. */
private const val BACK_CHEVRON_PATH = "M15 18l-6-6 6-6"

private val TOP_BAR_TRAILING_FLOOR = 96.dp

/**
 * `.m-bar` - the 55 dp top bar.
 *
 * The VMark is hidden when the rail is showing it instead or when a leading back action is shown,
 * which is why [showMark] and [onBack] are parameters rather than something the bar guesses.
 *
 * Uses a custom [Layout] so the title has width priority over [trailing] (such as [HostChip]):
 * single-word titles keep their full width before the chip shrinks and ellipsizes, and multi-word
 * titles keep at least their first word visible at large accessibility text scales.
 */
@Composable
public fun TopBar(
    title: String,
    modifier: Modifier = Modifier,
    showMark: Boolean = true,
    onBack: (() -> Unit)? = null,
    backContentDescription: String? = null,
    trailing: @Composable (RowScope.() -> Unit)? = null,
) {
  val colors = Vitruvian
  val density = LocalDensity.current
  val gapPx = with(density) { Space.s4.roundToPx() }
  val trailingFloorPx = with(density) { TOP_BAR_TRAILING_FLOOR.roundToPx() }
  val hasTrailing = trailing != null
  val singleWord = A11y.isSingleWordTitle(title)
  Layout(
      modifier =
          modifier
              .fillMaxWidth()
              .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top))
              .defaultMinSize(minHeight = Hit.h2)
              .bottomHairline(colors.divider)
              .padding(horizontal = Space.s4),
      content = {
        if (onBack != null) {
          val backDesc = A11y.topBarBackDescription(backContentDescription)
          Box(
              modifier =
                  Modifier.layoutId("leading")
                      .size(Hit.h1)
                      .clickable(role = Role.Button, onClick = onBack)
                      .semantics { contentDescription = backDesc },
              contentAlignment = Alignment.Center,
          ) {
            VIcon(
                path = BACK_CHEVRON_PATH,
                color = colors.text,
                contentDescription = null,
            )
          }
        } else if (A11y.topBarShowMark(showMark = showMark, hasBackAction = false)) {
          Box(modifier = Modifier.layoutId("leading")) { VMark(markSize = 17.dp) }
        }
        VText(
            text = title,
            modifier = Modifier.layoutId("title"),
            style = VitruvianType.barTitle,
            color = colors.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            softWrap = false,
        )
        if (trailing != null) {
          Row(
              modifier = Modifier.layoutId("trailing"),
              verticalAlignment = Alignment.CenterVertically,
              horizontalArrangement = Arrangement.spacedBy(Space.s4),
              content = trailing,
          )
        }
      },
  ) { measurables, constraints ->
    val leadingMeasurable = measurables.firstOrNull { it.layoutId == "leading" }
    val titleMeasurable = measurables.first { it.layoutId == "title" }
    val trailingMeasurable = measurables.firstOrNull { it.layoutId == "trailing" }

    val leadingPlaceable = leadingMeasurable?.measure(constraints.copy(minWidth = 0, minHeight = 0))
    val leadingWidth = leadingPlaceable?.width ?: 0
    val leadingGap = if (leadingPlaceable != null) gapPx else 0

    val titleIntrinsic = titleMeasurable.maxIntrinsicWidth(constraints.maxHeight).coerceAtLeast(0)
    val trailingIntrinsic =
        trailingMeasurable?.maxIntrinsicWidth(constraints.maxHeight)?.coerceAtLeast(0) ?: 0
    val trailingGap = if (trailingMeasurable != null && trailingIntrinsic > 0) gapPx else 0

    val layoutWidth =
        if (constraints.hasBoundedWidth) {
          constraints.maxWidth
        } else {
          (leadingWidth + leadingGap + titleIntrinsic + trailingGap + trailingIntrinsic)
              .coerceAtLeast(constraints.minWidth)
        }
    val availableAfterLeading = (layoutWidth - leadingWidth - leadingGap).coerceAtLeast(0)
    val minTitleWidth =
        if (singleWord) titleIntrinsic else A11y.estimateFirstWordWidthPx(titleIntrinsic, title)

    val allocation =
        A11y.allocateTopBarWidths(
            availableAfterLeadingPx = availableAfterLeading,
            gapPx = gapPx,
            titleIntrinsicWidthPx = titleIntrinsic,
            minTitleWidthPx = minTitleWidth,
            hasTrailing = hasTrailing && trailingMeasurable != null,
            trailingIntrinsicWidthPx = trailingIntrinsic,
            isSingleWordTitle = singleWord,
            minTrailingFloorPx = trailingFloorPx,
        )

    val trailingPlaceable =
        if (trailingMeasurable != null && allocation.trailingMaxWidthPx > 0) {
          trailingMeasurable.measure(
              constraints.copy(
                  minWidth = 0,
                  maxWidth = allocation.trailingMaxWidthPx,
                  minHeight = 0,
              ),
          )
        } else {
          null
        }
    val actualTrailingWidth = trailingPlaceable?.width ?: 0
    val actualTrailingGap = if (trailingPlaceable != null && actualTrailingWidth > 0) gapPx else 0
    val actualTitleWidth =
        (availableAfterLeading - actualTrailingGap - actualTrailingWidth).coerceAtLeast(0)

    val titlePlaceable =
        titleMeasurable.measure(
            constraints.copy(
                minWidth = actualTitleWidth,
                maxWidth = actualTitleWidth,
                minHeight = 0,
            ),
        )

    val layoutHeight =
        maxOf(
            constraints.minHeight,
            leadingPlaceable?.height ?: 0,
            titlePlaceable.height,
            trailingPlaceable?.height ?: 0,
        )
    layout(layoutWidth, layoutHeight) {
      leadingPlaceable?.placeRelative(
          x = 0,
          y = (layoutHeight - leadingPlaceable.height) / 2,
      )
      titlePlaceable.placeRelative(
          x = leadingWidth + leadingGap,
          y = (layoutHeight - titlePlaceable.height) / 2,
      )
      trailingPlaceable?.placeRelative(
          x = layoutWidth - actualTrailingWidth,
          y = (layoutHeight - trailingPlaceable.height) / 2,
      )
    }
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
    hostName: String = text,
    stateLabel: String = A11y.toneStateWord(tone),
) {
  val fontScale = LocalConfiguration.current.fontScale
  Box(
      modifier =
          modifier
              .widthIn(max = 160.dp)
              .widthIn(max = A11y.hostChipMaxWidthDp(fontScale).dp)
              .defaultMinSize(minHeight = Hit.h1)
              .clickable(role = Role.Button, onClick = onClick)
              .semantics {
                contentDescription = A11y.hostChipDescription(name = hostName, state = stateLabel)
              },
      contentAlignment = Alignment.Center,
  ) {
    Box(
        modifier =
            Modifier.defaultMinSize(minHeight = 32.dp)
                .border(1.dp, Vitruvian.divider)
                .padding(horizontal = Space.s3, vertical = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
      Status(
          tone = tone,
          text = text,
          modifier = Modifier.clearAndSetSemantics {},
      )
    }
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
              .selectableGroup()
              // No blur here. The shell stacks this bar BELOW the body in a Column, so there is
              // nothing behind it to frost -- and a self-blur would only smudge the bar's own five
              // icons and labels, which is exactly what it used to do. See Glass.kt.
              .background(colors.glass)
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
  Left,
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
  val iconDescription = A11y.navIconDescription(label = item.label, iconOnly = item.iconOnly)
  Column(
      modifier =
          modifier
              .defaultMinSize(minHeight = Hit.h2)
              .selectable(
                  selected = selected,
                  role = Role.Tab,
                  onClick = item.onSelect,
              )
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
    VIcon(path = item.iconPath, color = content, contentDescription = iconDescription)
    if (!item.iconOnly) {
      val isRail = rule == NavRule.Left
      val fontScale = LocalConfiguration.current.fontScale
      // Both the rail and the bottom bar cap the label's scaled size: a five-tab bar at 200 %
      // text otherwise truncates every label ("MODUL…"). The icon still names each tab.
      val labelStyle =
          VitruvianType.tabLabel.copy(
              fontSize =
                  A11y.railLabelFontSizeSp(
                          baseSp = VitruvianType.tabLabel.fontSize.value,
                          fontScale = fontScale,
                          maxScaledDp = FontSize.label.value,
                      )
                      .sp,
              textAlign = TextAlign.Center,
          )
      VText(
          text = item.label.uppercase(),
          style = labelStyle,
          color = content,
          modifier = Modifier.padding(horizontal = Space.s1),
          maxLines = if (isRail) 2 else 1,
          overflow = if (isRail) TextOverflow.Clip else TextOverflow.Ellipsis,
          softWrap = isRail,
      )
    }
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
              .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Vertical))
              .drawBehind {
                drawRect(
                    color = colors.divider,
                    topLeft = Offset(size.width - 1.dp.toPx(), 0f),
                    size = Size(1.dp.toPx(), size.height),
                )
              }
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
          modifier = Modifier.padding(horizontal = Space.s1),
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
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

/** One item in a [Crumbs] trail. */
public data class CrumbItem(val label: String, val onClick: (() -> Unit)? = null)

/** `.crumbs` - a mono slash-separated breadcrumb trail. */
@Composable
public fun Crumbs(
    items: List<CrumbItem>,
    modifier: Modifier = Modifier,
) {
  val colors = Vitruvian
  Row(
      modifier = modifier,
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s2),
  ) {
    items.forEachIndexed { index, item ->
      if (index > 0) {
        VText(text = "/", style = VitruvianType.listSub, color = colors.textDim)
      }
      val isLast = index == items.lastIndex
      VText(
          text = item.label.uppercase(),
          modifier =
              if (item.onClick != null && !isLast) {
                Modifier.clickable(onClick = item.onClick)
              } else {
                Modifier
              },
          style = VitruvianType.status,
          color = if (isLast) colors.text else colors.textDim,
          maxLines = 1,
      )
    }
  }
}

/** One horizontal tab in [Tabs]. */
public data class TabOption(
    val id: String,
    val label: String,
    val count: Int? = null,
)

/** `.tabs` - horizontal section tabs underlined by a 2 dp accent rule when active. */
@Composable
public fun Tabs(
    tabs: List<TabOption>,
    activeId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
  val colors = Vitruvian
  Row(
      modifier = modifier.fillMaxWidth().selectableGroup().bottomHairline(colors.divider),
      horizontalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    tabs.forEach { tab ->
      val active = tab.id == activeId
      Row(
          modifier =
              Modifier.defaultMinSize(minHeight = Hit.h1)
                  .selectable(
                      selected = active,
                      role = Role.Tab,
                      onClick = { onSelect(tab.id) },
                  )
                  .drawBehind {
                    if (active) {
                      drawRect(
                          color = colors.accent,
                          topLeft = Offset(0f, size.height - ACTIVE_RULE.toPx()),
                          size = Size(size.width, ACTIVE_RULE.toPx()),
                      )
                    }
                  }
                  .padding(horizontal = Space.s2, vertical = Space.s3),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(Space.s2),
      ) {
        VText(
            text = tab.label.uppercase(),
            style = VitruvianType.status,
            color = if (active) colors.text else colors.textDim,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            softWrap = false,
        )
        if (tab.count != null) {
          VText(
              text = tab.count.toString(),
              style = VitruvianType.listSub,
              color = if (active) colors.accentText else colors.textDim,
              maxLines = 1,
              softWrap = false,
          )
        }
      }
    }
  }
}

/** `.pagination` - page index readout with Prev/Next controls. */
@Composable
public fun Pagination(
    page: Int,
    totalPages: Int,
    onPageChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    totalItems: Int? = null,
) {
  val colors = Vitruvian
  Row(
      modifier = modifier.fillMaxWidth().padding(vertical = Space.s2),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.SpaceBetween,
  ) {
    VText(
        text =
            buildString {
              append("PAGE ")
              append(page.toString().padStart(2, '0'))
              append(" / ")
              append(totalPages.coerceAtLeast(1).toString().padStart(2, '0'))
              if (totalItems != null) {
                append(" · ")
                append(totalItems)
                append(" ITEMS")
              }
            },
        style = VitruvianType.listSub,
        color = colors.textDim,
    )
    Row(horizontalArrangement = Arrangement.spacedBy(Space.s2)) {
      VButton(
          label = "← Prev",
          onClick = { onPageChange((page - 1).coerceAtLeast(1)) },
          enabled = page > 1,
          contentPadding = PaddingValues(horizontal = Space.s3),
      )
      VButton(
          label = "Next →",
          onClick = { onPageChange((page + 1).coerceAtMost(totalPages)) },
          enabled = page < totalPages,
          contentPadding = PaddingValues(horizontal = Space.s3),
      )
    }
  }
}

/**
 * `.avatar` - a square monogram plate for users, agents, or nodes, with an optional corner [Status]
 * indicator.
 */
@Composable
public fun Avatar(
    name: String,
    modifier: Modifier = Modifier,
    initials: String? = null,
    status: StatusTone? = null,
    avatarSize: Dp = 32.dp,
) {
  val colors = Vitruvian
  val letters =
      initials
          ?: name
              .trim()
              .split(Regex("[\\s-_]+"))
              .filter { it.isNotEmpty() }
              .take(2)
              .joinToString("") { it.take(1).uppercase() }
              .ifEmpty { "?" }

  Box(modifier = modifier.size(avatarSize), contentAlignment = Alignment.Center) {
    Box(
        modifier =
            Modifier.size(avatarSize).background(colors.surface2).border(1.dp, colors.divider),
        contentAlignment = Alignment.Center,
    ) {
      VText(
          text = letters,
          style = VitruvianType.status,
          color = colors.accentText,
          maxLines = 1,
          softWrap = false,
      )
    }
    if (status != null) {
      Box(
          modifier =
              Modifier.align(Alignment.BottomEnd)
                  .offset(x = 2.dp, y = 2.dp)
                  .background(colors.bg)
                  .padding(1.dp),
      ) {
        Status(tone = status)
      }
    }
  }
}
