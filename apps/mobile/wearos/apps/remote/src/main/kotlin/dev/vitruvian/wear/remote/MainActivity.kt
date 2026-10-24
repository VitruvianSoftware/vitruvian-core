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

package dev.vitruvian.wear.remote

import android.os.Bundle
import android.view.HapticFeedbackConstants
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import dev.vitruvian.design.Tag
import dev.vitruvian.design.TagTone
import dev.vitruvian.design.VText
import dev.vitruvian.design.VitruvianTheme
import dev.vitruvian.wear.common.MediaTarget
import dev.vitruvian.wear.common.RemoteWireCodec
import dev.vitruvian.wear.common.RotaryVolumeAccumulator
import dev.vitruvian.wear.common.TvRemoteCommand

public class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent { VitruvianTheme { WristRemoteScreen() } }
  }
}

@Composable
private fun WristRemoteScreen() {
  val view = LocalView.current
  val focusRequester = remember { FocusRequester() }
  val accumulator = remember { RotaryVolumeAccumulator(pixelsPerStep = 18f) }
  val targets = MediaTarget.entries

  var targetIndex by remember { mutableIntStateOf(0) }
  var volume by remember { mutableIntStateOf(38) }
  var muted by remember { mutableStateOf(false) }
  var lastPayload by remember { mutableStateOf("Crown adjusts volume") }

  val target = targets[targetIndex]

  fun dispatch(cmd: TvRemoteCommand, vol: Int? = null) {
    lastPayload = "${cmd.label} -> ${target.title}"
    RemoteWireCodec.encodeCommand(target, cmd, vol)
    view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
  }

  LaunchedEffect(Unit) { focusRequester.requestFocus() }

  Box(
      modifier =
          Modifier.fillMaxSize()
              .background(Color(0xFF0A1217))
              .onRotaryScrollEvent { event ->
                val result = accumulator.onScroll(volume, muted, event.verticalScrollPixels)
                if (result.deltaSteps != 0) {
                  volume = result.newVolume
                  if (result.unmuted) muted = false
                  val cmd =
                      if (result.deltaSteps > 0) TvRemoteCommand.VOLUME_UP
                      else TvRemoteCommand.VOLUME_DOWN
                  dispatch(cmd, volume)
                }
                true
              }
              .focusRequester(focusRequester)
              .focusable()
              .padding(16.dp),
      contentAlignment = Alignment.Center,
  ) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
      Box(
          modifier =
              Modifier.clip(RoundedCornerShape(12.dp)).clickable {
                targetIndex = (targetIndex + 1) % targets.size
                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
              },
      ) {
        Tag(
            text = "${target.title} · ${if (muted) "MUTED" else "VOL $volume%"}",
            tone = if (muted) TagTone.Warn else TagTone.Accent,
        )
      }

      Spacer(modifier = Modifier.height(6.dp))

      // Top row: Power | Up | Input
      Row(
          horizontalArrangement = Arrangement.spacedBy(8.dp),
          verticalAlignment = Alignment.CenterVertically,
      ) {
        RemotePill("PWR", Color(0xFF421C20)) { dispatch(TvRemoteCommand.POWER) }
        RemotePill("▲", Color(0xFF1A2C38)) { dispatch(TvRemoteCommand.DPAD_UP) }
        RemotePill("INP", Color(0xFF1A2C38)) { dispatch(TvRemoteCommand.INPUT_CYCLE) }
      }

      Spacer(modifier = Modifier.height(6.dp))

      // Middle row: Left | OK | Right
      Row(
          horizontalArrangement = Arrangement.spacedBy(8.dp),
          verticalAlignment = Alignment.CenterVertically,
      ) {
        RemotePill("◀", Color(0xFF1A2C38)) { dispatch(TvRemoteCommand.DPAD_LEFT) }
        Box(
            modifier =
                Modifier.size(44.dp).clip(CircleShape).background(Color(0xFF2B4C62)).clickable {
                  dispatch(TvRemoteCommand.DPAD_CENTER)
                },
            contentAlignment = Alignment.Center,
        ) {
          VText(text = "OK")
        }
        RemotePill("▶", Color(0xFF1A2C38)) { dispatch(TvRemoteCommand.DPAD_RIGHT) }
      }

      Spacer(modifier = Modifier.height(6.dp))

      // Bottom row: Back | Down | Play/Pause
      Row(
          horizontalArrangement = Arrangement.spacedBy(8.dp),
          verticalAlignment = Alignment.CenterVertically,
      ) {
        RemotePill("BCK", Color(0xFF1A2C38)) { dispatch(TvRemoteCommand.BACK) }
        RemotePill("▼", Color(0xFF1A2C38)) { dispatch(TvRemoteCommand.DPAD_DOWN) }
        RemotePill("⏯", Color(0xFF1A2C38)) { dispatch(TvRemoteCommand.PLAY_PAUSE) }
      }

      Spacer(modifier = Modifier.height(6.dp))
      VText(text = lastPayload)
    }
  }
}

@Composable
private fun RemotePill(label: String, bg: Color, onClick: () -> Unit) {
  Box(
      modifier =
          Modifier.clip(RoundedCornerShape(14.dp))
              .background(bg)
              .clickable(onClick = onClick)
              .padding(horizontal = 10.dp, vertical = 6.dp),
      contentAlignment = Alignment.Center,
  ) {
    VText(text = label)
  }
}
