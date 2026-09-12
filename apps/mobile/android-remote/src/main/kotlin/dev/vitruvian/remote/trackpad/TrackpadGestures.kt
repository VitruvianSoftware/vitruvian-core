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

package dev.vitruvian.remote.trackpad

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import kotlin.math.abs
import kotlin.math.hypot

/**
 * The trackpad gesture set.
 *
 * The interaction design is borrowed from gabrieldonadel/entangle (MIT), an open-source remote
 * mouse app, whose `apps/mobile/src/features/trackpad/gestures.ts` had already solved the problems
 * this surface hit: separating a tap from a pan, arming a drag without a button, and putting Spaces
 * and Mission Control on swipes instead of buttons. The thresholds below are theirs -- the drag
 * hold time is now a starting point rather than a fixed value, since it is the one a user can feel
 * is wrong. The implementation is not -- they use react-native-gesture-handler and this is Compose
 * -- so this is a port of the design, not the code.
 *
 * Written as ONE state machine rather than several Compose gesture detectors. Detectors compete for
 * the same pointers, and the multi-finger cases (two-finger scroll versus three-finger swipe versus
 * a tap) resolve unpredictably when stacked. entangle needs `Gesture.Race` for the same reason;
 * Compose has no equivalent, so the arbitration is explicit here.
 */

/** What the surface does; the caller decides what each one means. */
public interface TrackpadHandlers {
  public fun onMove(dx: Float, dy: Float)

  public fun onTap()

  public fun onRightClick()

  public fun onDragBegin()

  public fun onDragMove(dx: Float, dy: Float)

  public fun onDragEnd()

  /** Positive dy means the fingers moved down the pad. */
  public fun onScroll(dy: Float)

  public fun onSpaceSwipe(right: Boolean)

  public fun onMissionControl()
}

// Thresholds, all from entangle.

/**
 * Dead zone before a single finger starts moving the cursor.
 *
 * Android capacitive touch jitters on finger-down. Without this the pan starts instantly and eats
 * the tap, so every tap nudges the cursor first. A few pixels lets the tap win without the cursor
 * feeling sluggish.
 */
private const val PAN_MIN_DISTANCE = 4f

/** How far a finger may drift and still count as a tap rather than a short drag. */
private const val TAP_MAX_TRAVEL = 8f

/** Longer than this and it is a hold, not a tap. */
private const val TAP_MAX_MILLIS = 250L

/**
 * How still the finger must be during the hold to mean "drag".
 *
 * Without this check a slow swipe would arm a drag simply by lasting long enough, and the user
 * would find themselves selecting text when they meant to move the pointer.
 */
private const val DRAG_TRAVEL_TOLERANCE = 8f

/**
 * Two fingers must travel this far before scrolling starts, so a two-finger tap is not a scroll.
 */
private const val SCROLL_MIN_DISTANCE = 10f

private const val SWIPE_THRESHOLD_X = 50f
private const val SWIPE_THRESHOLD_Y = 60f

/** What the current gesture turned out to be. Undecided until the fingers commit. */
private enum class Mode {
  Undecided,
  Move,
  Drag,
  Scroll,
  Swipe,
}

/**
 * Recognises the trackpad gestures and reports them to [handlers].
 *
 * One gesture per `awaitEachGesture` pass: from first finger down to last finger up. The mode is
 * decided once and then held, so a gesture cannot turn into a different one halfway -- lifting one
 * of two fingers mid-scroll must not suddenly start moving the cursor.
 *
 * [dragHoldMillis] is how long a still finger rests before a drag arms - the one threshold here
 * that is user-tunable, because it is the one whose right value depends on the hand holding the
 * phone. Pointer and scroll speed are NOT applied here: those scale the deltas this reports, and
 * doing it downstream keeps a speed change from restarting the gesture loop.
 *
 * It is a `pointerInput` key rather than a plain read for a reason that is easy to miss: the
 * pointer loop below runs once and captures its inputs, so `pointerInput(Unit)` would keep using
 * whatever hold time was current when the surface first composed, and changing the setting would
 * silently do nothing. Restarting cancels any gesture in flight, which is harmless -- the setting
 * can only change while a finger is on a button somewhere else.
 *
 * [handlers] is deliberately NOT a key. It is an interface implementation, so a caller that
 * allocates it inline gets a new identity on every recomposition, and keying on it would tear down
 * and restart the pointer loop mid-stroke every time anything on the screen redrew. Callers should
 * `remember` it; the loop then holds one instance for its lifetime, which is correct as long as the
 * implementation forwards to stable state rather than closing over a snapshot value.
 */
public fun Modifier.trackpadGestures(
    handlers: TrackpadHandlers,
    dragHoldMillis: Int,
): Modifier =
    pointerInput(dragHoldMillis) {
      awaitEachGesture {
        val first = awaitFirstDown(requireUnconsumed = false)
        val startedAt = first.uptimeMillis
        var mode = Mode.Undecided
        var maxPointers = 1
        var travel = 0f
        var swipeFired = false
        var last: Offset = first.position
        var lastScroll: Offset = first.position
        // The timestamp of the most recent event, so the tap check below measures
        // the WHOLE gesture. Reading first.uptimeMillis there would always give
        // zero and make every gesture brief enough to be a tap.
        var lastEventAt = startedAt

        while (true) {
          val event = awaitPointerEvent()
          val pressed = event.changes.filter { it.pressed }
          if (pressed.isEmpty()) break

          maxPointers = maxOf(maxPointers, pressed.size)
          val centroid = pressed.centroid()
          lastEventAt = event.changes.first().uptimeMillis
          val elapsed = lastEventAt - startedAt
          travel =
              maxOf(travel, hypot(centroid.x - first.position.x, centroid.y - first.position.y))

          when (mode) {
            Mode.Undecided -> {
              mode =
                  when {
                    // Three fingers are always a swipe, however far they have
                    // moved: deciding later would let a slow three-finger start
                    // be mistaken for a scroll.
                    pressed.size >= 3 -> Mode.Swipe
                    pressed.size == 2 && travel > SCROLL_MIN_DISTANCE -> Mode.Scroll
                    // A hold that stayed still arms a drag. Checked before the
                    // pan threshold so a deliberate hold is not stolen by a few
                    // pixels of jitter.
                    pressed.size == 1 &&
                        elapsed >= dragHoldMillis &&
                        travel <= DRAG_TRAVEL_TOLERANCE -> {
                      handlers.onDragBegin()
                      Mode.Drag
                    }
                    pressed.size == 1 && travel > PAN_MIN_DISTANCE -> Mode.Move
                    else -> Mode.Undecided
                  }
              // Re-anchor on commit so the movement that decided the mode is not
              // also replayed as cursor motion.
              if (mode != Mode.Undecided) {
                last = centroid
                lastScroll = centroid
              }
            }
            Mode.Move -> {
              handlers.onMove(centroid.x - last.x, centroid.y - last.y)
              last = centroid
            }
            Mode.Drag -> {
              handlers.onDragMove(centroid.x - last.x, centroid.y - last.y)
              last = centroid
            }
            Mode.Scroll -> {
              handlers.onScroll(centroid.y - lastScroll.y)
              lastScroll = centroid
            }
            Mode.Swipe -> {
              if (!swipeFired) {
                val dx = centroid.x - first.position.x
                val dy = centroid.y - first.position.y
                if (abs(dx) > SWIPE_THRESHOLD_X && abs(dx) > abs(dy)) {
                  // macOS convention: fingers sliding left advance to the next
                  // space on the right, so the desktops follow the fingers.
                  handlers.onSpaceSwipe(right = dx < 0)
                  swipeFired = true
                } else if (dy < -SWIPE_THRESHOLD_Y && abs(dy) > abs(dx)) {
                  handlers.onMissionControl()
                  swipeFired = true
                }
              }
            }
          }
          // Consume so a parent scroll container cannot steal the gesture
          // halfway through and leave a drag button stuck down.
          pressed.forEach { it.consume() }
        }

        when {
          mode == Mode.Drag -> handlers.onDragEnd()
          // A tap is what is left: never committed to a mode, brief, and barely
          // moved. Finger count decides which button, matching a real trackpad
          // where extra fingers mean secondary click.
          mode == Mode.Undecided &&
              (lastEventAt - startedAt) <= TAP_MAX_MILLIS &&
              travel <= TAP_MAX_TRAVEL ->
              if (maxPointers >= 2) handlers.onRightClick() else handlers.onTap()
          else -> Unit
        }
      }
    }

private fun List<PointerInputChange>.centroid(): Offset {
  var x = 0f
  var y = 0f
  forEach {
    x += it.position.x
    y += it.position.y
  }
  return Offset(x / size, y / size)
}
