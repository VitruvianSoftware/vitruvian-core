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

package dev.vitruvian.wear.common

import kotlin.math.abs

/**
 * Pixel Watch 4 rotary crown accumulator and TV/media remote command protocol.
 *
 * Turning the physical crown emits fractional scroll deltas (`verticalScrollPixels`). An unbuffered
 * handler either fires on every sub-pixel jitter or drops slow turns; [RotaryVolumeAccumulator]
 * integrates scroll pixels against a configurable detent threshold (`pixelsPerStep`) and emits
 * clean integer volume deltas clamped to `0..100`.
 */
public enum class TvRemoteCommand(public val wireCode: String, public val label: String) {
  POWER("power", "Power"),
  VOLUME_UP("volume_up", "Vol +"),
  VOLUME_DOWN("volume_down", "Vol -"),
  MUTE("mute", "Mute"),
  DPAD_UP("dpad_up", "Up"),
  DPAD_DOWN("dpad_down", "Down"),
  DPAD_LEFT("dpad_left", "Left"),
  DPAD_RIGHT("dpad_right", "Right"),
  DPAD_CENTER("dpad_center", "OK"),
  BACK("back", "Back"),
  HOME("home", "Home"),
  PLAY_PAUSE("play_pause", "Play/Pause"),
  INPUT_CYCLE("input_cycle", "Input"),
}

public enum class MediaTarget(
    public val id: String,
    public val title: String,
    public val subtitle: String,
) {
  LIVING_ROOM_TV("living-room-bravia", "Living Room TV", "Sony Bravia XR"),
  LAKE_OFFICE_DISPLAY("lake-office-display", "Lake Office", "Smart Display & Studio"),
  MASTER_BEDROOM_TV("master-bedroom-tv", "Bedroom TV", "Google TV Streamer"),
  MAC_STUDIO_AUDIO("mac-studio-audio", "Mac Studio", "System Output"),
}

public data class VolumeStepResult(
    val previousVolume: Int,
    val newVolume: Int,
    val deltaSteps: Int,
    val unmuted: Boolean,
)

public class RotaryVolumeAccumulator(private val pixelsPerStep: Float = 18f) {
  private var residualPixels: Float = 0f

  init {
    require(pixelsPerStep > 0f) { "pixelsPerStep must be positive" }
  }

  /**
   * Integrates [scrollPixels] from the Pixel Watch 4 crown and returns the updated volume in
   * `0..100`. Turning the crown upward (positive delta) while muted automatically unmutes.
   */
  public fun onScroll(
      currentVolume: Int,
      muted: Boolean,
      scrollPixels: Float,
  ): VolumeStepResult {
    val clampedCurrent = currentVolume.coerceIn(0, 100)
    if (scrollPixels.isNaN() || scrollPixels.isInfinite() || abs(scrollPixels) < 0.01f) {
      return VolumeStepResult(clampedCurrent, clampedCurrent, 0, false)
    }
    // Reset residual if the user reverses crown direction mid-detent.
    if ((residualPixels > 0f && scrollPixels < 0f) || (residualPixels < 0f && scrollPixels > 0f)) {
      residualPixels = 0f
    }
    residualPixels += scrollPixels
    val steps = (residualPixels / pixelsPerStep).toInt()
    if (steps == 0) {
      return VolumeStepResult(clampedCurrent, clampedCurrent, 0, false)
    }
    residualPixels -= steps * pixelsPerStep
    val targetVolume = (clampedCurrent + steps).coerceIn(0, 100)
    val actualDelta = targetVolume - clampedCurrent
    val unmuted = muted && steps > 0
    return VolumeStepResult(
        previousVolume = clampedCurrent,
        newVolume = targetVolume,
        deltaSteps = actualDelta,
        unmuted = unmuted,
    )
  }

  public fun reset() {
    residualPixels = 0f
  }
}

public object RemoteWireCodec {
  public fun encodeCommand(
      target: MediaTarget,
      command: TvRemoteCommand,
      volumePercent: Int? = null,
  ): String = buildString {
    append("""{"target":"""")
    append(escapeJson(target.id))
    append("""","command":"""")
    append(escapeJson(command.wireCode))
    append('"')
    if (volumePercent != null) {
      append(""","volumePercent":""")
      append(volumePercent.coerceIn(0, 100))
    }
    append('}')
  }

  internal fun escapeJson(value: String): String =
      buildString(value.length) {
        for (ch in value) {
          when (ch) {
            '\\' -> append("\\\\")
            '"' -> append("\\\"")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> append(ch)
          }
        }
      }
}
