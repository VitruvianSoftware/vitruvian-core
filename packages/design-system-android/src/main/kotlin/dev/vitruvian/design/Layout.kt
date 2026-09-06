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

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp

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
