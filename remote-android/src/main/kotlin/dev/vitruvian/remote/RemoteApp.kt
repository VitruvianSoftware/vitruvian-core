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

package dev.vitruvian.remote

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import dev.vitruvian.design.VitruvianTheme
import dev.vitruvian.remote.overlays.ConfirmDialog
import dev.vitruvian.remote.overlays.MacroEditor
import dev.vitruvian.remote.overlays.OfflineBanner
import dev.vitruvian.remote.overlays.UnpairedState
import dev.vitruvian.remote.screens.AppsScreen
import dev.vitruvian.remote.screens.ConsoleScreen
import dev.vitruvian.remote.screens.HomeScreen
import dev.vitruvian.remote.screens.HostsScreen
import dev.vitruvian.remote.screens.MacScreen
import dev.vitruvian.remote.screens.RemoteScreen
import dev.vitruvian.remote.shell.RemoteShell
import dev.vitruvian.remote.shell.rememberDeviceLayout
import dev.vitruvian.remote.state.RemoteState
import dev.vitruvian.remote.state.Screen

/**
 * The whole app.
 *
 * One theme, one shell, one state holder, and the screens as content inside it - the shell decides
 * posture and the screens do not know about it.
 */
@Composable
public fun RemoteApp(state: RemoteState) {
  LaunchedEffect(state) { state.runMetrics() }
  VitruvianTheme(dark = state.darkTheme) {
    val layout = rememberDeviceLayout()
    RemoteShell(state = state, layout = layout) { screen ->
      OfflineBanner(state)
      if (state.isUnpaired) {
        UnpairedState(state)
      }
      ScreenContent(state = state, screen = screen)
    }
    ConfirmDialog(state)
    MacroEditor(state)
  }
}

/**
 * The screen switch.
 *
 * Home is suppressed while unpaired because the empty state has already taken the pane; every other
 * screen still draws, since Hosts is where the user is being sent and the rest are simply
 * unreachable.
 */
@Composable
private fun ColumnScope.ScreenContent(state: RemoteState, screen: Screen) {
  when (screen) {
    Screen.Home -> if (!state.isUnpaired) HomeScreen(state)
    Screen.Remote -> RemoteScreen(state)
    Screen.Mac -> MacScreen(state)
    Screen.Apps -> AppsScreen(state)
    Screen.Console -> ConsoleScreen(state)
    Screen.Hosts -> HostsScreen(state)
  }
}
