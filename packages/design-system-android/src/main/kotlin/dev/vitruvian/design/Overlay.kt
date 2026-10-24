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
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

/** The scrim over which every overlay sits: 55% of `color.bg`. */
private const val SCRIM_ALPHA = 0.55f

private val DIALOG_MAX_WIDTH = 400.dp
private val SHEET_MAX_WIDTH = 560.dp

/** A disabled menu row, at the same strength as a disabled [VButton]. */
private const val DISABLED_ALPHA = 0.4f

/** Every overlay draws its own scrim and keeps its content safe itself; see [OverlayWindow]. */
private val OVERLAY_PROPERTIES =
    DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)

/**
 * `.dialog` - glass over a 55% ink scrim, with registration marks.
 *
 * Destructive variants differ only in their kicker colour and their action button; the typed
 * confirmation is the caller's business, since whether it is required is a host setting.
 *
 * The plate stays inside the safe drawing area (status bar, navigation bar, cutout and keyboard)
 * and scrolls when it is taller than that area -- a prompt dialog on a tabletop half-screen with
 * the keyboard up still reaches its buttons. As with [BottomSheet], [content] is measured with no
 * height limit, so it takes no vertical `weight`, `fillMaxHeight` or `LazyColumn`.
 */
@Composable
public fun VDialog(
    onDismissRequest: () -> Unit,
    kicker: String,
    kickerColor: Color,
    title: String,
    body: String,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
  val colors = Vitruvian
  OverlayWindow(onDismissRequest = onDismissRequest) { safe ->
    Box(
        modifier =
            Modifier.fillMaxSize().background(colors.bg.copy(alpha = SCRIM_ALPHA)).padding(safe),
        contentAlignment = Alignment.Center,
    ) {
      Plate(
          modifier =
              modifier
                  .padding(Space.s5)
                  .widthIn(max = DIALOG_MAX_WIDTH)
                  .shadow(Shadow.lg)
                  .glassGround(),
          marks = true,
      ) {
        Column(
            modifier = Modifier.verticalScroll(rememberScrollState()).padding(Space.s5),
            verticalArrangement = Arrangement.spacedBy(Space.s4),
        ) {
          Label(text = kicker, color = kickerColor)
          VText(text = title, style = VitruvianType.h2, color = colors.text)
          VText(
              text = body,
              style = VitruvianType.body.copy(fontSize = FontSize.h5),
              color = colors.textDim,
          )
          content()
        }
      }
    }
  }
}

/**
 * The bottom glass sheet the macro editor uses.
 *
 * Tapping the scrim dismisses; tapping the sheet does not, which is why the sheet swallows its own
 * clicks with no indication. The sheet grows to fit its content up to the safe drawing area (it
 * never runs under the status bar, the navigation bar or the keyboard) and scrolls past that.
 * Content that needs a pinned header over a scrolling list belongs in an [OptionSheet] instead.
 *
 * Because [content] scrolls, it is measured with no height limit: a vertical `weight` in it
 * collapses, and a `LazyColumn` or `fillMaxHeight` in it fails. Size content by what it holds.
 */
@Composable
public fun BottomSheet(
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
  SheetFrame(onDismissRequest = onDismissRequest, modifier = modifier) {
    Column(
        modifier =
            Modifier.weight(1f, fill = false)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Space.s4, vertical = Space.s5),
        verticalArrangement = Arrangement.spacedBy(Space.s4),
        content = content,
    )
  }
}

/**
 * The scrim, the glass and the insets every bottom sheet shares.
 *
 * The scrim covers the whole window, edge to edge. The sheet keeps [Space.s6] of scrim above it so
 * there is always somewhere to tap to dismiss, and stops short of the status bar and any cutout.
 * Its glass runs down under the navigation bar while its content sits above the bar -- and above
 * the keyboard, which is part of the safe drawing area. The sheet is as tall as its content up to
 * that limit and no taller; [content] decides what scrolls once it hits it.
 */
@Composable
private fun SheetFrame(
    onDismissRequest: () -> Unit,
    modifier: Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
  val colors = Vitruvian
  val swallow = remember { MutableInteractionSource() }
  OverlayWindow(onDismissRequest = onDismissRequest) { safe ->
    val layoutDirection = LocalLayoutDirection.current
    Box(
        modifier =
            Modifier.fillMaxSize()
                .background(colors.bg.copy(alpha = SCRIM_ALPHA))
                .clickable(
                    interactionSource = swallow,
                    indication = null,
                    onClick = onDismissRequest,
                )
                .padding(
                    start = safe.calculateStartPadding(layoutDirection),
                    top = safe.calculateTopPadding() + Space.s6,
                    end = safe.calculateEndPadding(layoutDirection),
                ),
        contentAlignment = Alignment.BottomCenter,
    ) {
      Column(
          modifier =
              modifier
                  // Cap first, then fill: the other way round the fill fixes the width at the
                  // window's and the cap is ignored -- an unfolded sheet ran edge to edge.
                  .widthIn(max = SHEET_MAX_WIDTH)
                  .fillMaxWidth()
                  .shadow(Shadow.lg)
                  .glassGround()
                  .border(1.dp, colors.divider)
                  .clickable(interactionSource = swallow, indication = null) {}
                  .padding(bottom = safe.calculateBottomPadding()),
          content = content,
      )
    }
  }
}

/**
 * A full-window overlay [Dialog] that hands [content] the padding that keeps it clear of the status
 * bar, navigation bar or taskbar, display cutout and keyboard.
 *
 * Not `WindowInsets.safeDrawing` read inside the dialog: under Compose 1.7 (BOM 2024.11.00) every
 * inset reads zero in a dialog window, measured on a Pixel Fold emulator, while the window itself
 * still runs under the navigation bar -- which is how the last option of a long list ended up
 * beneath the gesture bar. So the safe area is read where it is reported, in the host window around
 * the dialog, and turned into padding by where the dialog's content actually sits on screen
 * ([SafeArea]). That is exact whichever way the platform lays the dialog window out: a band the
 * window already avoids (it starts below the status bar today) costs no padding, and a keyboard the
 * window has already been resized away from is not counted twice.
 *
 * An overlay opened from inside another (a select in the macro editor's sheet) inherits the outer
 * overlay's safe area through [LocalOverlaySafeArea], since its host is a dialog window too and
 * reads zero for the same reason.
 *
 * Contract: the host activity draws edge to edge (`enableEdgeToEdge()`). A host that lets its decor
 * fit the system bars consumes the insets before Compose sees them, and every edge reads zero.
 */
@Composable
private fun OverlayWindow(
    onDismissRequest: () -> Unit,
    content: @Composable (safe: PaddingValues) -> Unit,
) {
  // The whole host window, not just the Compose view in it: the insets are the window's.
  val hostWindow = LocalView.current.rootView
  val hostInsets = WindowInsets.safeDrawing
  val outerSafeArea = LocalOverlaySafeArea.current
  Dialog(onDismissRequest = onDismissRequest, properties = OVERLAY_PROPERTIES) {
    // The real frosted-glass effect: the app behind this window is blurred, the overlay's own
    // text stays sharp.
    blurBehindWindow()
    val density = LocalDensity.current
    val layoutDirection = LocalLayoutDirection.current
    val dialogView = LocalView.current
    // Read in composition, so the keyboard opening or the device unfolding recomposes this.
    val insets =
        SafeArea.Edges(
            left = hostInsets.getLeft(density, layoutDirection),
            top = hostInsets.getTop(density),
            right = hostInsets.getRight(density, layoutDirection),
            bottom = hostInsets.getBottom(density),
        )
    var placed by remember { mutableStateOf<Placement?>(null) }
    val safeArea = outerSafeArea ?: placed?.let { placement -> SafeArea.of(placement.host, insets) }
    val safe =
        placed?.let { placement ->
          val px = SafeArea.padding(placement.content, safeArea ?: placement.content)
          with(density) {
            val ltr = layoutDirection == LayoutDirection.Ltr
            PaddingValues(
                start = (if (ltr) px.left else px.right).toDp(),
                top = px.top.toDp(),
                end = (if (ltr) px.right else px.left).toDp(),
                bottom = px.bottom.toDp(),
            )
          }
        } ?: PaddingValues()
    Box(
        modifier =
            Modifier.fillMaxSize().onGloballyPositioned { coordinates ->
              val host = IntArray(2).also(hostWindow::getLocationOnScreen)
              val window = IntArray(2).also(dialogView::getLocationOnScreen)
              val origin = coordinates.positionInRoot()
              val left = window[0] + origin.x.toInt()
              val top = window[1] + origin.y.toInt()
              placed =
                  Placement(
                      host =
                          SafeArea.Rect(
                              left = host[0],
                              top = host[1],
                              right = host[0] + hostWindow.width,
                              bottom = host[1] + hostWindow.height,
                          ),
                      content =
                          SafeArea.Rect(
                              left = left,
                              top = top,
                              right = left + coordinates.size.width,
                              bottom = top + coordinates.size.height,
                          ),
                  )
            },
    ) {
      // Nothing until the safe area is known: laid out once without it, a long list settled its
      // scroll position for a taller sheet and kept it, its current value cut off at the bottom.
      if (placed != null) {
        CompositionLocalProvider(LocalOverlaySafeArea provides safeArea) { content(safe) }
      }
    }
  }
}

/** The safe area an overlay worked out, for an overlay opened inside it; null outside any. */
private val LocalOverlaySafeArea = compositionLocalOf<SafeArea.Rect?> { null }

/** Where the host window and the overlay's content sit on screen. */
private data class Placement(val host: SafeArea.Rect, val content: SafeArea.Rect)

/** One row of an [OptionSheet]. */
public data class SheetOption(
    val label: String,
    /** The current value: accent-marked, tagged [meta] or `ACTIVE`, and scrolled into view. */
    val selected: Boolean = false,
    /** False greys the row out and makes it inert; the current value stays readable regardless. */
    val enabled: Boolean = true,
    val danger: Boolean = false,
    /** Trailing text; null means `ACTIVE` on the current value and nothing elsewhere. */
    val meta: String? = null,
)

/**
 * The option sheet behind every dropdown: a pinned header over a list of [options].
 *
 * Sized to its content: a list that fits shows every row with no scrolling, however tall the sheet
 * has to grow to hold it. Only a list taller than the safe drawing area scrolls, inside the sheet,
 * under a header that stays put -- and it opens with the current value in view, not at the top of
 * 24 hours.
 *
 * [onSelect] receives the index of a different, available option; the sheet has already asked to
 * close. Tapping the current value just closes, and an unavailable option does nothing (see
 * [OptionList.tap]).
 */
@Composable
public fun OptionSheet(
    title: String,
    options: List<SheetOption>,
    onSelect: (Int) -> Unit,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
) {
  val colors = Vitruvian
  val selectedIndex = options.indexOfFirst { it.selected }
  val listState =
      rememberLazyListState(
          initialFirstVisibleItemIndex =
              OptionList.firstVisibleIndex(selectedIndex = selectedIndex, count = options.size),
      )
  SheetFrame(onDismissRequest = onDismissRequest, modifier = modifier) {
    Row(
        modifier =
            Modifier.fillMaxWidth()
                .padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      // The title takes what it needs; the current value gets the rest and ellipsises in it.
      Label(text = title)
      // The current value stays named in the header once the list scrolls it away.
      val current = options.getOrNull(selectedIndex)
      if (current != null) {
        VText(
            text = current.label,
            modifier = Modifier.weight(1f),
            style = VitruvianType.listSub.copy(textAlign = TextAlign.End),
            color = colors.accentText,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
      }
    }
    // A hairline under the header only once rows have scrolled beneath it.
    // Read in the layer, not in composition, so scrolling does not recompose the sheet.
    MenuDivider(
        modifier =
            Modifier.padding(horizontal = Space.s4).graphicsLayer {
              alpha = if (listState.canScrollBackward) 1f else 0f
            },
    )
    LazyColumn(
        state = listState,
        // One choice among many, as TalkBack should announce it.
        modifier = Modifier.weight(1f, fill = false).fillMaxWidth().selectableGroup(),
        contentPadding =
            PaddingValues(start = Space.s4, end = Space.s4, top = Space.s1, bottom = Space.s5),
    ) {
      itemsIndexed(options) { index, option ->
        MenuItem(
            label = option.label,
            meta = option.meta ?: if (option.selected) "ACTIVE" else null,
            danger = option.danger,
            selected = option.selected,
            enabled = option.enabled || option.selected,
            onClick = {
              when (OptionList.tap(enabled = option.enabled, selected = option.selected)) {
                OptionList.Tap.Apply -> {
                  onDismissRequest()
                  onSelect(index)
                }
                OptionList.Tap.Dismiss -> onDismissRequest()
                OptionList.Tap.Ignore -> {}
              }
            },
        )
        // A rule under each row but the last, never over the first: a row scrolled up to the
        // header would otherwise draw a second hairline against the header's.
        if (index < options.lastIndex) MenuDivider()
      }
    }
  }
}

/**
 * The glass ground: a 66%-alpha surface where the platform supports glass, an opaque surface where
 * it does not.
 *
 * The blur that belongs with this is a blur of the scene BEHIND the surface, not of the surface
 * itself, so it cannot live in this modifier chain -- a dialog gets it from [blurBehindWindow] at
 * the window level. Blurring here would frost the dialog's own title and body text. See Glass.kt.
 */
@Composable
public fun Modifier.glassGround(): Modifier {
  val colors = Vitruvian
  return this.background(if (supportsGlass) colors.glass else colors.surface)
}

/** A floating menu: glass, 200 dp minimum, hairline-separated mono items. */
@Composable
public fun MenuSurface(
    modifier: Modifier = Modifier,
    minWidth: Dp = 200.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
  val colors = Vitruvian
  Column(
      modifier =
          modifier
              .widthIn(min = minWidth)
              .shadow(Shadow.md)
              .glassGround()
              .border(1.dp, colors.divider),
      content = content,
  )
}

/**
 * `.menu-item` - a clickable row inside a [MenuSurface], [BottomSheet] or [OptionSheet].
 *
 * At least [Hit.h1] tall, the touch floor every clickable in this language keeps. The label takes
 * the room [meta] leaves it and wraps to a second line before it ellipsises, so a long label never
 * pushes [meta] off the edge. [enabled] false dims the row and makes it inert.
 *
 * [selected] null is a plain menu command. Non-null makes the row one option of a single choice (a
 * radio button to TalkBack), and true marks it the current value with the 2 dp accent rule the
 * Hosts list uses.
 */
@Composable
public fun MenuItem(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    meta: String? = null,
    danger: Boolean = false,
    selected: Boolean? = null,
    enabled: Boolean = true,
) {
  val colors = Vitruvian
  val rule = colors.accent
  val current = selected == true
  Row(
      modifier =
          modifier
              .fillMaxWidth()
              .defaultMinSize(minHeight = Hit.h1)
              .alpha(if (enabled) 1f else DISABLED_ALPHA)
              .then(
                  if (selected == null) {
                    Modifier.clickable(enabled = enabled, onClick = onClick)
                  } else {
                    Modifier.selectable(
                        selected = selected,
                        enabled = enabled,
                        role = Role.RadioButton,
                        onClick = onClick,
                    )
                  },
              )
              .drawBehind {
                if (current) {
                  val width = 2.dp.toPx()
                  // On the leading edge, which is the right one in a right-to-left layout.
                  val x = if (layoutDirection == LayoutDirection.Ltr) 0f else size.width - width
                  drawRect(color = rule, topLeft = Offset(x, 0f), size = Size(width, size.height))
                }
              }
              .padding(horizontal = Space.s3, vertical = Space.s2),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    VText(
        text = label,
        modifier = Modifier.weight(1f),
        style = VitruvianType.log,
        color =
            when {
              danger -> colors.sanguineText
              current -> colors.accentText
              else -> colors.text
            },
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
    )
    if (meta != null) {
      VText(
          text = meta,
          style = VitruvianType.listSub,
          color = if (current) colors.accentText else colors.textDim,
          maxLines = 1,
      )
    }
  }
}

/** `.menu-divider` - a 1 dp hairline rule between menu groups. */
@Composable
public fun MenuDivider(modifier: Modifier = Modifier) {
  Box(modifier = modifier.fillMaxWidth().height(1.dp).background(Vitruvian.divider))
}

/** `.toast` - a transient status notification plate with a 2 dp leading status rule. */
@Composable
public fun Toast(
    title: String,
    modifier: Modifier = Modifier,
    tone: StatusTone = StatusTone.Ok,
    detail: String? = null,
    onDismiss: (() -> Unit)? = null,
) {
  val colors = Vitruvian
  val rule =
      when (tone) {
        StatusTone.Ok -> colors.ok
        StatusTone.Warn -> colors.warn
        StatusTone.Crit -> colors.sanguine
        StatusTone.Run -> colors.accent
        StatusTone.Neutral -> colors.divider
      }
  Row(
      modifier =
          modifier
              .fillMaxWidth()
              .shadow(Shadow.md)
              .glassGround()
              .drawBehind {
                drawRect(color = colors.divider, style = Stroke(width = 1.dp.toPx()))
                drawRect(color = rule, size = Size(2.dp.toPx(), size.height))
              }
              .padding(horizontal = Space.s4, vertical = Space.s3),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Status(tone = tone)
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      VText(text = title, style = VitruvianType.mono, color = colors.text)
      if (detail != null) {
        VText(text = detail, style = VitruvianType.listSub, color = colors.textDim)
      }
    }
    if (onDismiss != null) {
      VButton(
          label = "×",
          onClick = onDismiss,
          variant = ButtonVariant.Ghost,
      )
    }
  }
}
