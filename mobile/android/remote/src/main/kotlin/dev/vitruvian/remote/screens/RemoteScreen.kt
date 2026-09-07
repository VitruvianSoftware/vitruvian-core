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

import android.graphics.BitmapFactory
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalView
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
import dev.vitruvian.remote.hid.HidAction
import dev.vitruvian.remote.overlays.DictateButton
import dev.vitruvian.remote.state.DialogKind
import dev.vitruvian.remote.state.RemoteState
import dev.vitruvian.remote.state.TRACK_PERCENT
import dev.vitruvian.remote.trackpad.TrackpadHandlers
import dev.vitruvian.remote.trackpad.TrackpadTuning
import dev.vitruvian.remote.trackpad.trackpadGestures

/** `minmax(300dp, 1fr)` - the two-up boards. */
internal val TWO_UP_MIN = 300.dp

private val TRACKPAD_HEIGHT = 230.dp

/** The peek plate's ceiling: a still taller than this pushes the trackpad off the screen. */
private val PEEK_MAX_HEIGHT = 260.dp

// The width asked of `/v1/screen`, in pixels. The contract accepts 200-1600
// and defaults to 800; the floor here is higher than the contract's because a
// 200 px still of a 6K display is not a picture of anything.
private const val PEEK_DEFAULT_WIDTH = 800
private const val PEEK_MIN_WIDTH = 400
private const val PEEK_MAX_WIDTH = 1600

/** Width of the square nudge buttons: `Hit.h1`, so they are as tall as they are wide. */
private val NUDGE_SIZE = 44.dp

/**
 * Content padding for a nudge button.
 *
 * VButton defaults to `Space.s5` (21 dp) EACH SIDE, which at 44 dp wide leaves 2 dp for the label
 * -- so the glyph was ellipsised away and both buttons rendered as a single "…" dot. They looked
 * like disabled placeholders, and volume and brightness had shipped that way. A one-character label
 * needs the padding out of its way, not a wider button.
 */
private val NUDGE_PADDING = PaddingValues(horizontal = Space.s2)

private val METER_HEIGHT = 8.dp
private const val VOLUME_STEP = 6
private const val BRIGHTNESS_STEP = 10

/**
 * The on-screen key palette.
 *
 * Bare keys and one chord, NOT bare modifiers. A lone ⌘ is meaningless over HID: a modifier only
 * exists as part of a report that also carries a key, and there is nowhere to "hold" it between two
 * taps. The old palette showed ⌘ ⌥ ⌃ ⇧ as if they were buttons and none of them did anything.
 */
private val PALETTE_KEYS: List<Pair<String, HidAction>> =
    listOf(
        "esc" to HidAction.Escape,
        "tab" to HidAction.Tab,
        "↩" to HidAction.Return,
        "⌫" to HidAction.Backspace,
        "↑" to HidAction.ArrowUp,
        "↓" to HidAction.ArrowDown,
        "←" to HidAction.ArrowLeft,
        "→" to HidAction.ArrowRight,
        "⌘ space" to HidAction.Spotlight,
    )

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
  val view = LocalView.current
  // Same light tick the trackpad uses, so an explicit Click button and a tap on
  // the pad feel identical -- they do the same thing.
  fun tick() = view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)

  // How wide a capture to ask the Mac for: the plate's own width in pixels, so
  // a foldable's open panel gets a sharper still than a phone does and neither
  // pays for pixels it will not draw. Until the plate has measured itself
  // there is nothing to go on but the contract's default.
  var peekWidth by remember { mutableIntStateOf(PEEK_DEFAULT_WIDTH) }

  Box(modifier = Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s5)) {
    AutoGrid(minItemWidth = TWO_UP_MIN, gap = Space.s4) {
      item {
        Column(verticalArrangement = Arrangement.spacedBy(Space.s3)) {
          Label("Trackpad")
          // Above the pad, because it is what you are pointing AT: a still of
          // the Mac over the surface that moves its cursor.
          if (state.peekOpen) {
            PeekPlate(state = state, onMeasured = { peekWidth = it })
          }
          Trackpad(state = state, modifier = Modifier.height(TRACKPAD_HEIGHT))
          // Two rows, not one: five buttons across the folded width leave
          // "Click" and "Right" no room and they ellipsise to "Cli…".
          Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
            VButton("Click", { if (state.click()) tick() }, modifier = Modifier.weight(1f))
            VButton("Right", { if (state.rightClick()) tick() }, modifier = Modifier.weight(1f))
          }
          Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
            VButton(
                label = "Keys",
                onClick = state::toggleKeyboard,
                modifier = Modifier.weight(1f),
                contentColor = if (state.keyboardOpen) colors.accentText else null,
            )
            VButton(
                label = "Feel",
                onClick = state::toggleTuning,
                modifier = Modifier.weight(1f),
                contentColor = if (state.tuningOpen) colors.accentText else null,
            )
            VButton(
                label = "Peek",
                // The width is decided when the plate has measured itself;
                // before it has, the contract's own default is the honest
                // guess.
                onClick = { state.togglePeek(peekWidth) },
                modifier = Modifier.weight(1f),
                contentColor = if (state.peekOpen) colors.accentText else null,
            )
          }
          if (state.tuningOpen) {
            TuningPlate(state)
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
              PALETTE_KEYS.forEach { (glyph, action) ->
                Kbd(text = glyph, onClick = { state.sendMacChord(action) })
              }
            }
          }
        }
      }
      item {
        Column(verticalArrangement = Arrangement.spacedBy(Space.s4)) {
          MediaPlate(state)
          DesktopPlate(state)
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
    DictateButton(state) { spoken ->
      state.updatePrompt(
          listOf(state.prompt.trim(), spoken).filter { it.isNotBlank() }.joinToString(" "))
    }
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
 * A still of the Mac's screen, on demand.
 *
 * Never on a timer. Every picture here is one tap and one `screencapture` on the Mac, which is the
 * difference between a remote that can look and one that is watching.
 *
 * The reason path is the one most people will meet first: without Screen Recording granted to the
 * agent binary macOS refuses, and the agent's 503 carries the exact route through System Settings.
 * That sentence is printed verbatim -- paraphrasing it would cost the only actionable thing in it.
 */
@Composable
private fun PeekPlate(state: RemoteState, onMeasured: (Int) -> Unit) {
  val colors = Vitruvian
  val bytes = state.peekImage
  val bitmap =
      remember(bytes) {
        bytes?.let { runCatching { BitmapFactory.decodeByteArray(it, 0, it.size) }.getOrNull() }
      }
  // Kept here as well as reported upward: Refresh needs the width this plate
  // actually is, and the Peek button above needs it before the plate exists.
  var width by remember { mutableIntStateOf(PEEK_DEFAULT_WIDTH) }
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier =
            Modifier.padding(Space.s4).fillMaxWidth().onSizeChanged { size ->
              if (size.width > 0) {
                width = size.width.coerceIn(PEEK_MIN_WIDTH, PEEK_MAX_WIDTH)
                onMeasured(width)
              }
            },
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Label("Screen · ${state.hostShortName.ifBlank { "the Mac" }}")
      when {
        bitmap != null ->
            Image(
                bitmap = bitmap.asImageBitmap(),
                // The Mac's screen, not a decoration. Its own words would be
                // an invention; what it is is all this can honestly say.
                contentDescription = "A still of the Mac's screen",
                modifier = Modifier.fillMaxWidth().heightIn(max = PEEK_MAX_HEIGHT),
                contentScale = ContentScale.Fit,
            )
        state.peekReason.isNotBlank() ->
            VText(
                text = state.peekReason,
                style = VitruvianType.listSub,
                color = colors.warn,
            )
        // Neither a picture nor a reason yet: the capture is in flight.
        else ->
            VText(
                text = if (state.peekLoading) "capturing…" else "no capture yet",
                style = VitruvianType.listSub,
                color = colors.textDim,
            )
      }
      // Said while a picture is on screen too: without it a second tap on
      // Refresh looks like it did nothing at all.
      if (state.peekLoading && bitmap != null) {
        VText(text = "capturing…", style = VitruvianType.listSub, color = colors.textDim)
      }
      Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
        VButton(
            label = "Refresh",
            onClick = { state.capturePeek(width) },
            modifier = Modifier.weight(1f),
            enabled = !state.peekLoading,
        )
        VButton("Close", state::closePeek, modifier = Modifier.weight(1f))
      }
    }
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
  val view = LocalView.current
  // Glass has no travel, so vibration is the only thing that can confirm a
  // press without looking down -- and looking down is the thing this surface
  // should never ask you to do. KEYBOARD_TAP is the light tick, not the heavy
  // long-press thud. Same idea as the esp32-s3's haptic_click().
  fun tick() = view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
  // Remembered, NOT allocated inline: `trackpadGestures` cannot key its pointer
  // loop on this object (see its docs), and a fresh instance every recomposition
  // would be a new identity for anything that later did. One instance for the
  // life of the surface, forwarding to the same state, is what the gesture loop
  // expects.
  val handlers =
      remember(state, view) {
        object : TrackpadHandlers {
          override fun onMove(dx: Float, dy: Float) = state.movePointerBy(dx, dy)

          override fun onTap() {
            if (state.click()) tick()
          }

          override fun onRightClick() {
            if (state.rightClick()) tick()
          }

          override fun onDragBegin() {
            // Heavier than a tap: arming a drag is a mode change and
            // should feel different from a click.
            if (state.beginDrag()) {
              view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            }
          }

          override fun onDragMove(dx: Float, dy: Float) = state.dragBy(dx, dy)

          override fun onDragEnd(): Unit = state.endDrag()

          // No haptic. entangle does not buzz on scroll and they are
          // right: a tick per notch during a long scroll is constant
          // vibration, not feedback.
          override fun onScroll(dy: Float) {
            state.scrollByDelta(dy)
          }

          override fun onSpaceSwipe(right: Boolean) {
            tick()
            state.sendMacChord(if (right) HidAction.SpaceRight else HidAction.SpaceLeft)
          }

          override fun onMissionControl() {
            tick()
            state.sendMacChord(HidAction.MissionControl)
          }
        }
      }

  Plate(
      modifier =
          modifier
              .fillMaxWidth()
              .heightIn(min = TRACKPAD_HEIGHT)
              .clipToBounds()
              .trackpadGestures(handlers, dragHoldMillis = state.tuning.dragHoldMillis),
      marks = true,
      gridField = true,
  ) {
    Label(
        text = captionPrefix + state.pointerLabel,
        modifier =
            Modifier.align(Alignment.BottomStart).padding(start = Space.s4, bottom = Space.s3),
        style = VitruvianType.tabLabel,
    )
  }
}

/**
 * Trackpad feel.
 *
 * Lives directly under the pad, not on a settings screen, because it is tuned by feel: you change a
 * number, put your thumb back on the pad, and decide. Anything that made you navigate away and back
 * would not get used, which is how these values stayed guesses for as long as they did.
 *
 * Shows the raw milliseconds for the hold and percentages for the speeds. Percent because "a bit
 * faster than before" is the actual question; milliseconds because a hold time is a duration you
 * can count, and rendering it as a percentage would hide the only number that means anything.
 */
@Composable
private fun TuningPlate(state: RemoteState) {
  val tuning = state.tuning
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s4),
    ) {
      TuneRow(
          label = "Pointer speed",
          value = "${tuning.pointerPercent}%",
          fraction = percentFraction(tuning.pointerPercent),
          onDown = { state.nudgePointerSpeed(-1) },
          onUp = { state.nudgePointerSpeed(1) },
      )
      TuneRow(
          label = "Scroll speed",
          value = "${tuning.scrollPercent}%",
          fraction = percentFraction(tuning.scrollPercent),
          onDown = { state.nudgeScrollSpeed(-1) },
          onUp = { state.nudgeScrollSpeed(1) },
      )
      TuneRow(
          label = "Hold to drag",
          value = "${tuning.dragHoldMillis} ms",
          fraction = holdFraction(tuning.dragHoldMillis),
          onDown = { state.nudgeDragHold(-1) },
          onUp = { state.nudgeDragHold(1) },
      )
      VButton("Reset to defaults", state::resetTuning, modifier = Modifier.fillMaxWidth())
    }
  }
}

/** Position within the settable range, NOT the value itself - 100% is not 100% of the bar. */
private fun percentFraction(percent: Int): Float =
    (percent - TrackpadTuning.MIN_PERCENT).toFloat() /
        (TrackpadTuning.MAX_PERCENT - TrackpadTuning.MIN_PERCENT)

private fun holdFraction(millis: Int): Float =
    (millis - TrackpadTuning.MIN_DRAG_HOLD_MILLIS).toFloat() /
        (TrackpadTuning.MAX_DRAG_HOLD_MILLIS - TrackpadTuning.MIN_DRAG_HOLD_MILLIS)

/**
 * One tunable, as label, value, bar and a pair of nudges.
 *
 * Same shape as [NudgeRow] but takes a formatted value and an explicit bar fraction: volume and
 * brightness are percentages that ARE their own fraction, and these are not - a 400% pointer would
 * otherwise overflow the meter.
 */
@Composable
private fun TuneRow(
    label: String,
    value: String,
    fraction: Float,
    onDown: () -> Unit,
    onUp: () -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(Space.s3)) {
    Row(modifier = Modifier.fillMaxWidth()) {
      Label(text = label, modifier = Modifier.weight(1f))
      VText(text = value, style = VitruvianType.listSub, color = Vitruvian.textDim)
    }
    Row(
        horizontalArrangement = Arrangement.spacedBy(Space.s3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
      VButton(
          "−",
          onDown,
          modifier = Modifier.width(NUDGE_SIZE),
          contentPadding = NUDGE_PADDING,
      )
      Meter(fraction = fraction, modifier = Modifier.weight(1f), height = METER_HEIGHT)
      VButton(
          "+",
          onUp,
          modifier = Modifier.width(NUDGE_SIZE),
          contentPadding = NUDGE_PADDING,
      )
    }
  }
}

/**
 * Desktop, Spaces and window control.
 *
 * Everything here is a documented macOS keyboard shortcut sent over HID, so it works with no
 * software on the Mac. Force Quit deliberately routes through the confirm dialog rather than firing
 * on a single tap.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DesktopPlate(state: RemoteState) {
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Label("Desktop · Spaces")
      Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
        VButton(
            "Space ←",
            { state.sendMacChord(HidAction.SpaceLeft) },
            modifier = Modifier.weight(1f),
        )
        VButton(
            "Space →",
            { state.sendMacChord(HidAction.SpaceRight) },
            modifier = Modifier.weight(1f),
        )
      }
      FlowRow(
          horizontalArrangement = Arrangement.spacedBy(Space.s2),
          verticalArrangement = Arrangement.spacedBy(Space.s2),
      ) {
        DESKTOP_ACTIONS.forEach { (label, action) ->
          VButton(label, { state.sendMacChord(action) })
        }
      }
      Label("Window")
      FlowRow(
          horizontalArrangement = Arrangement.spacedBy(Space.s2),
          verticalArrangement = Arrangement.spacedBy(Space.s2),
      ) {
        WINDOW_ACTIONS.forEach { (label, action) -> VButton(label, { state.sendMacChord(action) }) }
      }
    }
  }
}

private val DESKTOP_ACTIONS: List<Pair<String, HidAction>> =
    listOf(
        "Mission Control" to HidAction.MissionControl,
        "App Exposé" to HidAction.AppExpose,
        "Show Desktop" to HidAction.ShowDesktop,
        "Launchpad" to HidAction.Launchpad,
        "Screenshot" to HidAction.ScreenshotFull,
        "Capture…" to HidAction.ScreenshotUi,
    )

private val WINDOW_ACTIONS: List<Pair<String, HidAction>> =
    listOf(
        "Switch App" to HidAction.CmdTab,
        "Cycle" to HidAction.CycleWindows,
        "Fullscreen" to HidAction.Fullscreen,
        "Minimise" to HidAction.MinimiseWindow,
        "Hide" to HidAction.HideApp,
        "Close" to HidAction.CloseWindow,
    )

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
            text = state.mediaTitle,
            modifier = Modifier.weight(1f),
            style = VitruvianType.barTitle,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        VText(
            text = state.mediaSub,
            style = VitruvianType.listSub,
            color = colors.textDim,
        )
      }
      // No scrubber when nothing knows the position. The transport buttons
      // below are HID and work regardless of what is playing.
      if (!state.isLive) {
        Meter(fraction = TRACK_PERCENT / 100f)
      }
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
          value = state.volumeValue,
          fraction = state.volumeFraction,
          onDown = { state.nudgeVolume(-VOLUME_STEP) },
          onUp = { state.nudgeVolume(VOLUME_STEP) },
      )
      NudgeRow(
          label = "Brightness",
          value = state.brightnessValue,
          fraction = state.brightnessFraction,
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

/**
 * A pair of nudge keys with a bar the caller may not be able to fill.
 *
 * [fraction] is nullable because the two rows that use this are asymmetric: the Mac reports its
 * volume, and nothing reports its brightness. The keys work either way -- they are HID -- but a bar
 * drawn from a local guess drifts away from the machine on every press made at the Mac itself, and
 * looks exactly as authoritative as one that does not.
 */
@Composable
private fun NudgeRow(
    label: String,
    value: String,
    fraction: Float?,
    onDown: () -> Unit,
    onUp: () -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(Space.s3)) {
    Row(modifier = Modifier.fillMaxWidth()) {
      Label(text = label, modifier = Modifier.weight(1f))
      VText(text = value, style = VitruvianType.listSub, color = Vitruvian.textDim)
    }
    Row(
        horizontalArrangement = Arrangement.spacedBy(Space.s3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
      VButton(
          "−",
          onDown,
          modifier = Modifier.width(NUDGE_SIZE),
          contentPadding = NUDGE_PADDING,
      )
      if (fraction == null) {
        VText(
            text = "no reading · keys still work",
            modifier = Modifier.weight(1f),
            style = VitruvianType.label,
            color = Vitruvian.textDim,
        )
      } else {
        Meter(fraction = fraction, modifier = Modifier.weight(1f), height = METER_HEIGHT)
      }
      VButton(
          "+",
          onUp,
          modifier = Modifier.width(NUDGE_SIZE),
          contentPadding = NUDGE_PADDING,
      )
    }
  }
}

/** `.m-section` padding, for the labels that head a full-bleed section. */
internal fun Modifier.sectionPadding(): Modifier =
    padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3)
