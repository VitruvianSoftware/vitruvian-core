// Copyright (c) 2026 VitruvianSoftware

package dev.vitruvian.wand.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StrokeCoordinatorTest {

  @Test
  fun coalescesMovesWhileInFlightAndDispatchesOnCompletedWithRealElapsedDuration() {
    val coordinator =
        StrokeCoordinator(initialDurationMs = 40L, minDurationMs = 16L, maxDurationMs = 500L)

    // Start drag at t=1000ms
    val start = coordinator.onStrokeStart(x = 100f, y = 200f, nowMs = 1000L)
    assertEquals(
        StrokeSegment(
            fromX = 100f,
            fromY = 200f,
            toX = 100f,
            toY = 200f,
            durationMs = 40L,
            willContinue = true,
            isInitial = true,
        ),
        start,
    )
    assertTrue(coordinator.isInFlight)

    // Moves arriving at t=1015ms and t=1030ms while initial segment is in flight are coalesced
    assertNull(coordinator.onStrokeContinue(toX = 120f, toY = 210f, nowMs = 1015L))
    assertNull(coordinator.onStrokeContinue(toX = 150f, toY = 240f, nowMs = 1030L))

    // Initial segment completes at t=1045ms -> emits coalesced segment (100,200)->(150,240) with
    // duration 45ms
    val cont1 = coordinator.onCompleted(nowMs = 1045L)
    assertEquals(
        StrokeSegment(
            fromX = 100f,
            fromY = 200f,
            toX = 150f,
            toY = 240f,
            durationMs = 45L,
            willContinue = true,
            isInitial = false,
        ),
        cont1,
    )
    assertTrue(coordinator.isInFlight)

    // End requested at t=1070ms while cont1 is still in flight -> deferred until onCompleted
    assertNull(coordinator.onStrokeEnd(toX = 160f, toY = 250f, nowMs = 1070L))

    // cont1 completes at t=1090ms -> emits final segment (150,240)->(160,250) with
    // willContinue=false, duration=45ms
    val endSeg = coordinator.onCompleted(nowMs = 1090L)
    assertEquals(
        StrokeSegment(
            fromX = 150f,
            fromY = 240f,
            toX = 160f,
            toY = 250f,
            durationMs = 45L,
            willContinue = false,
            isInitial = false,
        ),
        endSeg,
    )
    assertFalse(coordinator.isActive)
    assertFalse(coordinator.isInFlight)
  }

  @Test
  fun onCancelledMarksDragLostAndDoesNotDispatchOnRelease() {
    val coordinator = StrokeCoordinator()

    coordinator.onStrokeStart(x = 300f, y = 400f, nowMs = 2000L)
    assertNull(coordinator.onStrokeContinue(toX = 320f, toY = 410f, nowMs = 2015L))

    // System cancels the in-flight gesture
    coordinator.onCancelled()
    assertTrue(coordinator.isDragLost)
    assertFalse(coordinator.isInFlight)

    // Subsequent moves are ignored
    assertNull(coordinator.onStrokeContinue(toX = 350f, toY = 430f, nowMs = 2030L))

    // Release must return null (NO tap or continuation stroke!) and clear dragLost
    assertNull(coordinator.onStrokeEnd(toX = 350f, toY = 430f, nowMs = 2050L))
    assertFalse(coordinator.isActive)
    assertFalse(coordinator.isDragLost)
  }

  @Test
  fun forceEndAtCursorTerminatesInFlightStrokeWithNonContinuingSegment() {
    val coordinator = StrokeCoordinator()

    coordinator.onStrokeStart(x = 500f, y = 600f, nowMs = 3000L)
    val forced = coordinator.forceEndAtCursor(cursorX = 525f, cursorY = 615f, nowMs = 3035L)
    assertNotNull(forced)
    assertEquals(
        StrokeSegment(
            fromX = 500f,
            fromY = 600f,
            toX = 525f,
            toY = 615f,
            durationMs = 35L,
            willContinue = false,
            isInitial = false,
        ),
        forced,
    )
    assertFalse(coordinator.isActive)
    assertFalse(coordinator.isInFlight)
  }
}
