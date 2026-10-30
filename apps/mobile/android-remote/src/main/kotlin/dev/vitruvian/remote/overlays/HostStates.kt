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
import dev.vitruvian.remote.state.Derive
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
      label = "${state.hostShortName} unreachable",
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

/**
 * The screens with controls on them, plus Hosts where the fix lives. Remote, Mac and Console have
 * their own per-control "pair" wording; a banner on each would be a fourth way to say it.
 */
private val PAIRING_BANNER_SCREENS = setOf(Screen.Home, Screen.Apps, Screen.Hosts)

/**
 * Connected but not paired: the Mac answers every read, and refuses every change.
 *
 * Not dismissible. It goes away when the condition does -- a token arriving -- because the incident
 * it exists for was exactly this state with nothing on screen to explain it: switches that did
 * nothing, a Mac saying "paired, not connected" and a phone saying "connected".
 */
@Composable
public fun ColumnScope.PairingBanner(state: RemoteState) {
  val (label, body) = state.pairingBanner ?: return
  if (state.effectiveScreen !in PAIRING_BANNER_SCREENS) return
  // The bridge fails for the same reason; one banner says both, rather than two stacked.
  val bridge =
      if (state.bridgeProblem == Derive.BridgeProblem.NotPaired) {
        " Phone Bridge cannot link either."
      } else {
        ""
      }
  Banner(
      tone = BannerTone.Warn,
      label = label,
      body = body + bridge,
      modifier = Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s4),
  ) {
    VButton(label = "Pair now", onClick = state::openPairing, variant = ButtonVariant.Primary)
  }
}

/**
 * Phone Bridge switched on but not linked, for a reason other than pairing (the pairing banner
 * already says that one). Transient "connecting…" stays on the plate; this is for the states that
 * do not fix themselves.
 */
@Composable
public fun ColumnScope.BridgeBanner(state: RemoteState) {
  if (state.needsPairing) return
  if (state.effectiveScreen !in PAIRING_BANNER_SCREENS) return
  val problem = state.bridgeProblem
  if (!Derive.bridgeProblemIsBannerWorthy(problem)) return
  val text = state.bridgeProblemText ?: return
  Banner(
      tone = BannerTone.Warn,
      label = "Phone Bridge not linked",
      body = text,
      modifier = Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s4),
  ) {
    VButton(
        label = if (problem == Derive.BridgeProblem.Stopped) "Start" else "Reconnect",
        onClick = state::reconnectBridge,
    )
  }
}
