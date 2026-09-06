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

package dev.vitruvian.remote.overlays

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import dev.vitruvian.design.Banner
import dev.vitruvian.design.BannerTone
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.EmptyState
import dev.vitruvian.design.Space
import dev.vitruvian.design.VButton
import dev.vitruvian.remote.state.RemoteState
import dev.vitruvian.remote.state.Screen
import kotlinx.coroutines.launch

/**
 * The unreachable-host banner.
 *
 * Wake on LAN actually does something here: it sends the packet, and on the host answering the
 * banner clears itself and the event stream gains a line saying so.
 */
@Composable
public fun ColumnScope.OfflineBanner(state: RemoteState) {
  if (!state.isOffline) return
  val scope = rememberCoroutineScope()
  Banner(
      tone = BannerTone.Warn,
      label = "atlas unreachable",
      body =
          "Last seen 4 m ago via Tailscale. Controls are disabled; " +
              "dashboards show the last sample.",
      modifier = Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s4),
  ) {
    VButton("Wake on LAN", { scope.launch { state.wakeHost() } })
    VButton("Retry", state::retryHost)
  }
}

/**
 * The unpaired empty state.
 *
 * Navigation is locked to Hosts while this shows, so both buttons lead somewhere that can actually
 * resolve it.
 */
@Composable
public fun ColumnScope.UnpairedState(state: RemoteState) {
  if (!state.isUnpaired) return
  Box(modifier = Modifier.fillMaxWidth().padding(horizontal = Space.s4, vertical = Space.s6)) {
    EmptyState(
        label = "No Mac paired",
        title = "This remote has nothing to point at yet.",
        body =
            "Install the agent on your Mac, then enter the pairing code shown here. " +
                "Dashboards and modules appear once the first host connects.",
    ) {
      VButton(
          label = "Pair a Mac",
          onClick = { state.go(Screen.Hosts) },
          variant = ButtonVariant.Primary,
      )
      VButton("Install guide", state::openInstallGuide)
    }
  }
}
