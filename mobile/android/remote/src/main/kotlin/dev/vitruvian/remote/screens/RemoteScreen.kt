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

package dev.vitruvian.remote.screens

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.vitruvian.design.AutoGrid
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.Kbd
import dev.vitruvian.design.Label
import dev.vitruvian.design.ListItem
import dev.vitruvian.design.Meter
import dev.vitruvian.design.Plate
import dev.vitruvian.design.Space
import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.Terminal
import dev.vitruvian.design.TerminalLine
import dev.vitruvian.design.TerminalTone
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VInput
import dev.vitruvian.design.VSwitch
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.state.DialogKind
import dev.vitruvian.remote.state.RemoteState
import dev.vitruvian.remote.state.TRACK_PERCENT

/** `minmax(300dp, 1fr)` - the two-up boards. */
internal val TWO_UP_MIN = 300.dp

private val TRACKPAD_HEIGHT = 230.dp
private val CROSSHAIR_ARM = 9.dp
private const val VOLUME_STEP = 6
private const val BRIGHTNESS_STEP = 10

private val MODIFIER_KEYS = listOf("⌘", "⌥", "⌃", "⇧", "esc", "tab", "↩", "⌘ space")

/**
 * Remote: the controls.
 *
 * Trackpad and keys, media, volume and brightness, an agent prompt, the macros, the clipboard, and
 * power - in that order, because that is roughly how often each is reached for.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
public fun ColumnScope.RemoteScreen(state: RemoteState) {
  val colors = Vitruvian

  Box(modifier = Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s5)) {
    AutoGrid(minItemWidth = TWO_UP_MIN, gap = Space.s4) {
      item {
        Column(verticalArrangement = Arrangement.spacedBy(Space.s3)) {
          Label("Trackpad")
          Trackpad(state = state, modifier = Modifier.height(TRACKPAD_HEIGHT))
          Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
            VButton("Click", state::click, modifier = Modifier.weight(1f))
            VButton("Right", state::rightClick, modifier = Modifier.weight(1f))
            VButton(
                label = "Keys",
                onClick = state::toggleKeyboard,
                modifier = Modifier.weight(1f),
                contentColor = if (state.keyboardOpen) colors.accentText else null,
            )
          }
          if (state.keyboardOpen) {
            Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
              VInput(
                  value = state.typed,
                  onValueChange = state::updateTyped,
                  modifier = Modifier.weight(1f),
                  placeholder = "Type on atlas…",
              )
              VButton("Send", state::sendTyped, variant = ButtonVariant.Primary)
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(Space.s2),
                verticalArrangement = Arrangement.spacedBy(Space.s2),
            ) {
              MODIFIER_KEYS.forEach { key -> Kbd(text = key) }
            }
          }
        }
      }
      item {
        Column(verticalArrangement = Arrangement.spacedBy(Space.s4)) {
          MediaPlate(state)
          OutputPlate(state)
        }
      }
    }
  }

  Label(text = "Agent", modifier = Modifier.sectionPadding())
  Row(
      modifier = Modifier.padding(horizontal = Space.s4),
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    VInput(
        value = state.prompt,
        onValueChange = state::updatePrompt,
        modifier = Modifier.weight(1f),
        placeholder = "Ask Claude Code on atlas…",
    )
    VButton("Send", state::sendPrompt, variant = ButtonVariant.Primary)
  }

  Label(text = "Macros · scripts", modifier = Modifier.sectionPadding())
  state.macros.forEach { macro ->
    ListItem(
        title = macro.label,
        subtitle = macro.command,
        status = StatusTone.Ok,
    ) {
      VButton("Run", { state.runMacro(macro) })
    }
  }

  Label(text = "Clipboard", modifier = Modifier.sectionPadding())
  Row(
      modifier = Modifier.padding(horizontal = Space.s4),
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
      verticalAlignment = Alignment.CenterVertically,
  ) {
    Terminal(
        lines = listOf(TerminalLine(" ", state.clipboard, TerminalTone.Dim)),
        modifier = Modifier.weight(1f),
        fontSize = 12.sp,
    )
    VButton("Push", state::pushClipboard)
    VButton("Pull", state::pullClipboard)
  }

  Label(text = "Power", modifier = Modifier.sectionPadding())
  Row(
      modifier = Modifier.padding(horizontal = Space.s4),
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    VButton("Lock", state::lock, modifier = Modifier.weight(1f))
    VButton("Sleep", { state.openDialog(DialogKind.Sleep) }, modifier = Modifier.weight(1f))
    VButton(
        label = "Restart",
        onClick = { state.openDialog(DialogKind.Restart) },
        modifier = Modifier.weight(1f),
        variant = ButtonVariant.Danger,
    )
  }
}

/**
 * The trackpad surface.
 *
 * Shared with the tabletop dock, which is why the caption prefix is a parameter: in the dock the
 * same field is labelled `Trackpad · …` because it has no section header above it.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
public fun Trackpad(
    state: RemoteState,
    modifier: Modifier = Modifier,
    captionPrefix: String = "",
) {
  val colors = Vitruvian
  val pointer = state.pointer
  Plate(
      modifier =
          modifier
              .fillMaxWidth()
              .heightIn(min = TRACKPAD_HEIGHT)
              .clipToBounds()
              .pointerInput(Unit) {
                awaitPointerEventScope {
                  while (true) {
                    val event = awaitPointerEvent()
                    val position = event.changes.firstOrNull()?.position
                    when (event.type) {
                      PointerEventType.Move,
                      PointerEventType.Press, -> position?.let { state.movePointer(it.x, it.y) }
                      PointerEventType.Release,
                      PointerEventType.Exit, -> state.releasePointer()
                      else -> Unit
                    }
                  }
                }
              }
              .pointerInput(Unit) { detectTapGestures(onTap = { state.click() }) },
      marks = true,
      gridField = true,
  ) {
    if (pointer != null) {
      Box(
          modifier =
              Modifier.fillMaxWidth().height(TRACKPAD_HEIGHT).drawBehind {
                val arm = CROSSHAIR_ARM.toPx()
                val hairline = 1.dp.toPx()
                drawRect(
                    color = colors.accentText,
                    topLeft = Offset(pointer.first - arm, pointer.second),
                    size = Size(arm * 2 + hairline, hairline),
                )
                drawRect(
                    color = colors.accentText,
                    topLeft = Offset(pointer.first, pointer.second - arm),
                    size = Size(hairline, arm * 2 + hairline),
                )
              },
      )
    }
    Label(
        text = captionPrefix + state.pointerLabel,
        modifier =
            Modifier.align(Alignment.BottomStart).padding(start = Space.s4, bottom = Space.s3),
        style = VitruvianType.tabLabel,
    )
  }
}

@Composable
private fun MediaPlate(state: RemoteState) {
  val colors = Vitruvian
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Label("Media · Music")
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(Space.s3),
          verticalAlignment = Alignment.Bottom,
      ) {
        VText(
            text = if (state.playing) "Ambient Works 85–92" else "Paused",
            modifier = Modifier.weight(1f),
            style = VitruvianType.barTitle,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        VText(
            text = "2:41 / 4:03",
            style = VitruvianType.listSub,
            color = colors.textDim,
        )
      }
      Meter(fraction = TRACK_PERCENT / 100f)
      Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
        VButton("⏮", state::previousTrack, modifier = Modifier.weight(1f))
        VButton(
            label = if (state.playing) "Pause" else "Play",
            onClick = state::togglePlay,
            modifier = Modifier.weight(1f),
            variant = ButtonVariant.Primary,
        )
        VButton("⏭", state::nextTrack, modifier = Modifier.weight(1f))
      }
    }
  }
}

/** Volume, brightness and the display mirror - the "output" plate. */
@Composable
private fun OutputPlate(state: RemoteState) {
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s4),
    ) {
      NudgeRow(
          label = "Volume",
          percent = state.volume,
          onDown = { state.nudgeVolume(-VOLUME_STEP) },
          onUp = { state.nudgeVolume(VOLUME_STEP) },
      )
      NudgeRow(
          label = "Brightness",
          percent = state.brightness,
          onDown = { state.nudgeBrightness(-BRIGHTNESS_STEP) },
          onUp = { state.nudgeBrightness(BRIGHTNESS_STEP) },
      )
      VSwitch(
          checked = state.mirror,
          onCheckedChange = { state.toggleMirror() },
          label = "Mirror to Studio Display",
      )
    }
  }
}

@Composable
private fun NudgeRow(
    label: String,
    percent: Int,
    onDown: () -> Unit,
    onUp: () -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(Space.s3)) {
    Row(modifier = Modifier.fillMaxWidth()) {
      Label(text = label, modifier = Modifier.weight(1f))
      VText(
          text = "$percent%",
          style = VitruvianType.listSub,
          color = Vitruvian.textDim,
      )
    }
    Row(
        horizontalArrangement = Arrangement.spacedBy(Space.s3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
      VButton("−", onDown, modifier = Modifier.width(44.dp))
      Meter(fraction = percent / 100f, modifier = Modifier.weight(1f), height = 8.dp)
      VButton("+", onUp, modifier = Modifier.width(44.dp))
    }
  }
}

/** `.m-section` padding, for the labels that head a full-bleed section. */
internal fun Modifier.sectionPadding(): Modifier =
    padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3)
