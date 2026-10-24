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

package dev.vitruvian.wear.home

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
import dev.vitruvian.wear.common.RoborockAction
import dev.vitruvian.wear.common.SpeakerRoom

public class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent { VitruvianTheme { HomeControlWatchScreen() } }
  }
}

@Composable
private fun HomeControlWatchScreen() {
  val view = LocalView.current
  val focusRequester = remember { FocusRequester() }
  val rooms = SpeakerRoom.entries

  var roomIndex by remember { mutableIntStateOf(0) }
  var statusLine by remember { mutableStateOf("Crown selects speaker room") }

  val activeRoom = rooms[roomIndex]

  fun selectRoom(room: SpeakerRoom) {
    room.toSpeakerBroadcastCliCommand()
    statusLine = "Speaker -> ${room.displayName}"
    view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
  }

  fun triggerRoborock(action: RoborockAction) {
    action.toJsonPayload()
    statusLine = "Roborock: ${action.label}"
    view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
  }

  LaunchedEffect(Unit) { focusRequester.requestFocus() }

  Box(
      modifier =
          Modifier.fillMaxSize()
              .background(Color(0xFF0A1217))
              .onRotaryScrollEvent { event ->
                if (kotlin.math.abs(event.verticalScrollPixels) > 12f) {
                  val step = if (event.verticalScrollPixels > 0f) 1 else -1
                  roomIndex = (roomIndex + step + rooms.size) % rooms.size
                  view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
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
      Tag(
          text = "SPEAKER · ${activeRoom.shortCode}",
          tone = if (activeRoom == SpeakerRoom.MUTE) TagTone.Warn else TagTone.Ok,
      )
      Spacer(modifier = Modifier.height(4.dp))

      Box(
          modifier =
              Modifier.clip(RoundedCornerShape(14.dp))
                  .background(Color(0xFF2B4C62))
                  .clickable { selectRoom(activeRoom) }
                  .padding(horizontal = 14.dp, vertical = 6.dp),
      ) {
        VText(text = "Set ${activeRoom.displayName}")
      }

      Spacer(modifier = Modifier.height(8.dp))
      VText(text = "ROBOROCK VACUUM")
      Spacer(modifier = Modifier.height(4.dp))

      Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        ActionChip("Office") { triggerRoborock(RoborockAction.CLEAN_OFFICE) }
        ActionChip("Kitchen") { triggerRoborock(RoborockAction.CLEAN_KITCHEN) }
      }
      Spacer(modifier = Modifier.height(4.dp))
      Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        ActionChip("Mop") { triggerRoborock(RoborockAction.WASH_MOP) }
        ActionChip("Dock") { triggerRoborock(RoborockAction.RETURN_TO_DOCK) }
      }

      Spacer(modifier = Modifier.height(6.dp))
      VText(text = statusLine)
    }
  }
}

@Composable
private fun ActionChip(label: String, onClick: () -> Unit) {
  Box(
      modifier =
          Modifier.clip(RoundedCornerShape(12.dp))
              .background(Color(0xFF1A2C38))
              .clickable(onClick = onClick)
              .padding(horizontal = 10.dp, vertical = 5.dp),
      contentAlignment = Alignment.Center,
  ) {
    VText(text = label)
  }
}
