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

package dev.vitruvian.wear.nexus

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.speech.RecognizerIntent
import android.view.HapticFeedbackConstants
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
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
import dev.vitruvian.wear.common.ApprovalDecision
import dev.vitruvian.wear.common.PendingApprovalItem
import dev.vitruvian.wear.common.SpecialistAgent
import dev.vitruvian.wear.common.VoiceAgentRouter

public class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent { VitruvianTheme { NexusWristScreen() } }
  }
}

@Composable
private fun NexusWristScreen() {
  val view = LocalView.current
  val focusRequester = remember { FocusRequester() }

  val approvalQueue = remember {
    listOf(
        PendingApprovalItem(
            id = "pr-3839",
            title = "PR #3839",
            subtitle = "Daytona Platinum 126506",
            agent = SpecialistAgent.SCOUT,
            prNumber = 3839,
        ),
        PendingApprovalItem(
            id = "k3s-audit",
            title = "Homelab Audit",
            subtitle = "3/3 nodes · 0 alerts",
            agent = SpecialistAgent.RIDGE,
            prNumber = null,
        ),
    )
  }

  var itemIndex by remember { mutableIntStateOf(0) }
  var dispatchStatus by remember { mutableStateOf("Tap Speak to dispatch agent") }

  val currentItem = approvalQueue[itemIndex % approvalQueue.size]

  val speechLauncher =
      rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result
        ->
        if (result.resultCode == Activity.RESULT_OK) {
          val matches = result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
          val spoken = matches?.firstOrNull().orEmpty()
          if (spoken.isNotBlank()) {
            val req = VoiceAgentRouter.route(spoken)
            req.toJsonPayload()
            dispatchStatus = "@${req.routedAgent.id}: $spoken"
            view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
          }
        }
      }

  LaunchedEffect(Unit) { focusRequester.requestFocus() }

  Box(
      modifier =
          Modifier.fillMaxSize()
              .background(Color(0xFF0A1217))
              .onRotaryScrollEvent { event ->
                if (kotlin.math.abs(event.verticalScrollPixels) > 12f) {
                  val step = if (event.verticalScrollPixels > 0f) 1 else -1
                  itemIndex = (itemIndex + step + approvalQueue.size) % approvalQueue.size
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
          text = "NEXUS · @${currentItem.agent.id}",
          tone = TagTone.Accent,
      )
      Spacer(modifier = Modifier.height(4.dp))

      Box(
          modifier =
              Modifier.clip(CircleShape)
                  .background(Color(0xFF2B4C62))
                  .clickable {
                    val intent =
                        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                          putExtra(
                              RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                              RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                          )
                          putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak to Vitruvian Agent")
                        }
                    runCatching { speechLauncher.launch(intent) }
                        .onFailure {
                          val fallback = VoiceAgentRouter.route("Check homelab k3s cluster health")
                          dispatchStatus = "Queued @${fallback.routedAgent.id} health check"
                        }
                    view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                  }
                  .padding(horizontal = 16.dp, vertical = 6.dp),
      ) {
        VText(text = "🎙 Speak to Agent")
      }

      Spacer(modifier = Modifier.height(6.dp))
      VText(text = "${currentItem.title} · ${currentItem.subtitle}")
      Spacer(modifier = Modifier.height(4.dp))

      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(
            modifier =
                Modifier.clip(RoundedCornerShape(12.dp))
                    .background(Color(0xFF1E3E2E))
                    .clickable {
                      VoiceAgentRouter.encodeApproval(
                          currentItem,
                          ApprovalDecision.APPROVE_AND_ENQUEUE,
                      )
                      dispatchStatus = "Approved ${currentItem.title}"
                      view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                    }
                    .padding(horizontal = 10.dp, vertical = 5.dp),
        ) {
          VText(text = "Approve")
        }

        Box(
            modifier =
                Modifier.clip(RoundedCornerShape(12.dp))
                    .background(Color(0xFF421C20))
                    .clickable {
                      VoiceAgentRouter.encodeApproval(currentItem, ApprovalDecision.HOLD_PR)
                      dispatchStatus = "Held ${currentItem.title}"
                      view.performHapticFeedback(HapticFeedbackConstants.REJECT)
                    }
                    .padding(horizontal = 10.dp, vertical = 5.dp),
        ) {
          VText(text = "Hold")
        }
      }

      Spacer(modifier = Modifier.height(6.dp))
      VText(text = dispatchStatus)
    }
  }
}
