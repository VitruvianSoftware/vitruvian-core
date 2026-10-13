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

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Collects the children of an [AutoGrid], each with its column span. */
public class AutoGridScope internal constructor() {
  internal val items: MutableList<AutoGridItem> = mutableListOf()

  /** Adds one cell. [span] is clamped to the grid's actual column count. */
  public fun item(span: Int = 1, content: @Composable () -> Unit) {
    items += AutoGridItem(span, content)
  }
}

internal data class AutoGridItem(val span: Int, val content: @Composable () -> Unit)

/**
 * `repeat(auto-fit, minmax(minItemWidth, 1fr))`.
 *
 * This is the layout every board on every screen uses, and the reason the same composition reads
 * correctly folded, unfolded and in the dock: the column count falls out of the width it is given,
 * so nothing has to know which posture it is in.
 *
 * A lazy grid would be the wrong tool - these boards are a handful of items inside an
 * already-scrolling column, and nesting a lazy scroller in one is both a measurement error and a
 * needless one.
 */
@Composable
public fun AutoGrid(
    minItemWidth: Dp,
    modifier: Modifier = Modifier,
    gap: Dp = Space.s3,
    content: AutoGridScope.() -> Unit,
) {
  val scope = AutoGridScope().apply(content)
  if (scope.items.isEmpty()) return
  BoxWithConstraints(modifier = modifier.fillMaxWidth()) {
    val columns = ((maxWidth + gap) / (minItemWidth + gap)).toInt().coerceAtLeast(1)
    val rows = packRows(scope.items, columns)
    Column(verticalArrangement = Arrangement.spacedBy(gap)) {
      rows.forEach { row ->
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(gap),
            verticalAlignment = Alignment.Top,
        ) {
          row.forEach { item ->
            Row(modifier = Modifier.weight(item.span.coerceAtMost(columns).toFloat())) {
              item.content()
            }
          }
          val used = row.sumOf { it.span.coerceAtMost(columns) }
          if (used < columns) {
            Row(modifier = Modifier.weight((columns - used).toFloat())) {}
          }
        }
      }
    }
  }
}

/** Greedy row packing - the same order CSS grid auto-placement produces. */
private fun packRows(items: List<AutoGridItem>, columns: Int): List<List<AutoGridItem>> {
  val rows = mutableListOf<List<AutoGridItem>>()
  var current = mutableListOf<AutoGridItem>()
  var used = 0
  items.forEach { item ->
    val span = item.span.coerceIn(1, columns)
    if (used + span > columns && current.isNotEmpty()) {
      rows += current
      current = mutableListOf()
      used = 0
    }
    current += item
    used += span
  }
  if (current.isNotEmpty()) rows += current
  return rows
}

/** One entry in a [KeyValue] description list. */
public data class KeyValueEntry(
    val key: String,
    val value: String,
    val mono: Boolean = true,
)

/** `.kv` - a hairline-separated key-value specification table for node/pod/session metadata. */
@Composable
public fun KeyValue(
    items: List<KeyValueEntry>,
    modifier: Modifier = Modifier,
) {
  val colors = Vitruvian
  Column(modifier = modifier.fillMaxWidth()) {
    items.forEach { entry ->
      Row(
          modifier =
              Modifier.fillMaxWidth().bottomHairline(colors.line).padding(vertical = Space.s2),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.SpaceBetween,
      ) {
        Label(text = entry.key)
        VText(
            text = entry.value,
            style = if (entry.mono) VitruvianType.mono else VitruvianType.body,
            color = colors.text,
            maxLines = 1,
        )
      }
    }
  }
}

/** One collapsible section in an [Accordion]. */
public data class AccordionSection(
    val id: String,
    val title: String,
    val meta: String? = null,
    val defaultOpen: Boolean = false,
    val content: @Composable () -> Unit,
)

/** `.accordion` - a bordered stack of collapsible specification sections. */
@Composable
public fun Accordion(
    sections: List<AccordionSection>,
    modifier: Modifier = Modifier,
) {
  val colors = Vitruvian
  val openMap = remember {
    mutableStateMapOf<String, Boolean>().apply { sections.forEach { put(it.id, it.defaultOpen) } }
  }

  Column(modifier = modifier.fillMaxWidth().border(1.dp, colors.divider)) {
    sections.forEachIndexed { index, section ->
      val isOpen = openMap[section.id] ?: section.defaultOpen
      val isLast = index == sections.lastIndex
      Column(
          modifier =
              Modifier.fillMaxWidth()
                  .then(if (!isLast) Modifier.bottomHairline(colors.divider) else Modifier),
      ) {
        Row(
            modifier =
                Modifier.fillMaxWidth()
                    .defaultMinSize(minHeight = Hit.h1)
                    .clickable { openMap[section.id] = !isOpen }
                    .padding(horizontal = Space.s4, vertical = Space.s3),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.s3),
        ) {
          VIcon(
              path = if (isOpen) VitruvianIcons.CHEVRON_DOWN else VitruvianIcons.CHEVRON_RIGHT,
              iconSize = 16.dp,
              color = if (isOpen) colors.accentText else colors.textDim,
          )
          VText(
              text = section.title,
              modifier = Modifier.weight(1f),
              style = VitruvianType.mono,
              color = colors.text,
          )
          if (section.meta != null) {
            VText(
                text = section.meta,
                style = VitruvianType.listSub,
                color = colors.textDim,
            )
          }
        }
        if (isOpen) {
          Column(
              modifier =
                  Modifier.fillMaxWidth()
                      .padding(start = Space.s4, end = Space.s4, bottom = Space.s4),
          ) {
            section.content()
          }
        }
      }
    }
  }
}
