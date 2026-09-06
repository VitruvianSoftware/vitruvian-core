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

package dev.vitruvian.remote.shell

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ExperimentalAnimationApi
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import dev.vitruvian.design.Duration
import dev.vitruvian.design.Easing
import dev.vitruvian.design.HostChip
import dev.vitruvian.design.NavItem
import dev.vitruvian.design.Rail
import dev.vitruvian.design.Space
import dev.vitruvian.design.TabBar
import dev.vitruvian.design.TopBar
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianIcons
import dev.vitruvian.design.motion
import dev.vitruvian.remote.state.Connection
import dev.vitruvian.remote.state.RemoteState
import dev.vitruvian.remote.state.Screen

/** The dock's width when it sits beside the content rather than under it. */
private val DOCK_WIDTH = 300.dp

/** The 5 dp the incoming screen slides, per the handoff's push spec. */
private val PUSH_SLIDE = 5.dp

/** The first five destinations are the tab bar; Hosts is rail- and chip-only. */
private val TAB_SCREENS =
    listOf(Screen.Home, Screen.Remote, Screen.Mac, Screen.Apps, Screen.Console)

private val ICONS =
    mapOf(
        Screen.Home to VitruvianIcons.HOME,
        Screen.Remote to VitruvianIcons.MOUSE_POINTER,
        Screen.Mac to VitruvianIcons.ACTIVITY,
        Screen.Apps to VitruvianIcons.GRID_2X2,
        Screen.Console to VitruvianIcons.TERMINAL,
        Screen.Hosts to VitruvianIcons.SETTINGS,
    )

/**
 * The adaptive shell.
 *
 * One composition for all three postures: the rail replaces the tab bar above compact width, and
 * the dock either flanks the content or - in tabletop - drops below the hinge.
 */
@Composable
public fun RemoteShell(
    state: RemoteState,
    layout: DeviceLayout,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.(Screen) -> Unit,
) {
  val colors = Vitruvian
  val screen = state.effectiveScreen
  val navItems = navItems(state)
  val showDock =
      layout.showRail &&
          state.dockOpen &&
          screen != Screen.Console &&
          state.connection != Connection.Unpaired

  Row(modifier = modifier.fillMaxSize().background(colors.bg)) {
    if (layout.showRail) {
      Rail(
          items = navItems,
          selectedKey = screen.name,
          dockOpen = state.dockOpen,
          onToggleDock = state::toggleDock,
          hostLabel = state.hostShortName,
          hostTone = state.hostTone,
      )
    }
    Column(modifier = Modifier.weight(1f).fillMaxHeight()) {
      TopBar(title = screen.title, showMark = !layout.showRail) {
        HostChip(
            text = state.hostChipText,
            tone = state.hostTone,
            onClick = { state.go(Screen.Hosts) },
        )
      }
      ShellBody(
          state = state,
          layout = layout,
          screen = screen,
          showDock = showDock,
          modifier = Modifier.weight(1f),
          content = content,
      )
      if (layout.showTabBar) {
        TabBar(
            items = navItems.filter { item -> TAB_SCREENS.any { it.name == item.key } },
            selectedKey = screen.name,
        )
      }
    }
  }
}

/**
 * Content beside or above the dock.
 *
 * In tabletop the split is the hinge itself: the dock takes the lower half and the divider between
 * them is the dashed rule the design calls for.
 */
@OptIn(ExperimentalAnimationApi::class)
@Composable
private fun ShellBody(
    state: RemoteState,
    layout: DeviceLayout,
    screen: Screen,
    showDock: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.(Screen) -> Unit,
) {
  val colors = Vitruvian
  val density = LocalDensity.current
  val slide = with(density) { PUSH_SLIDE.roundToPx() }
  val duration = motion(Duration.D3)

  val primary: @Composable (Modifier) -> Unit = { paneModifier ->
    AnimatedContent(
        targetState = screen,
        modifier = paneModifier,
        transitionSpec = {
          (fadeIn(tween(duration, easing = Easing.mech)) +
              slideInHorizontally(tween(duration, easing = Easing.mech)) { slide }) togetherWith
              (fadeOut(tween(duration, easing = Easing.mech)) +
                  slideOutHorizontally(tween(duration, easing = Easing.mech)) { -slide })
        },
        label = "screen",
    ) { target ->
      Column(
          modifier =
              Modifier.fillMaxSize()
                  .verticalScroll(rememberScrollState())
                  .padding(bottom = Space.s5),
      ) {
        content(target)
      }
    }
  }

  if (layout.isTabletop && showDock) {
    Column(modifier = modifier.fillMaxSize()) {
      primary(Modifier.weight(1f).fillMaxWidth())
      Box(
          modifier =
              Modifier.weight(1f).fillMaxWidth().drawBehind {
                drawLine(
                    color = colors.divider,
                    start = Offset(0f, 0f),
                    end = Offset(size.width, 0f),
                    strokeWidth = 1.dp.toPx(),
                    pathEffect =
                        PathEffect.dashPathEffect(
                            floatArrayOf(4.dp.toPx(), 4.dp.toPx()),
                        ),
                )
              },
      ) {
        Dock(state = state, showsTrackpad = screen == Screen.Remote)
      }
    }
  } else {
    Row(modifier = modifier.fillMaxSize()) {
      primary(Modifier.weight(1f).fillMaxHeight())
      if (showDock) {
        Box(
            modifier =
                Modifier.width(DOCK_WIDTH).fillMaxHeight().drawBehind {
                  drawRect(
                      color = colors.divider,
                      size = Size(1.dp.toPx(), size.height),
                  )
                },
        ) {
          Dock(state = state, showsTrackpad = false)
        }
      }
    }
  }
}

/** The six destinations, wired to navigation. */
@Composable
private fun navItems(state: RemoteState): List<NavItem> =
    Screen.entries.map { screen ->
      NavItem(
          key = screen.name,
          label = screen.title,
          iconPath = ICONS.getValue(screen),
          onSelect = { state.go(screen) },
      )
    }
