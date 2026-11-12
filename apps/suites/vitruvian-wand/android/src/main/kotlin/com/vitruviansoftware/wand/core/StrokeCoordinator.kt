// Copyright (c) 2026 VitruvianSoftware

package com.vitruviansoftware.wand.core

/** Single gesture stroke segment to be dispatched by `WandAccessibilityService`. */
data class StrokeSegment(
    val fromX: Float,
    val fromY: Float,
    val toX: Float,
    val toY: Float,
    val durationMs: Long,
    val willContinue: Boolean,
    val isInitial: Boolean,
)

/**
 * Pure Kotlin state machine that sequences `GestureDescription.StrokeDescription.continueStroke`
 * segments so that:
 * - The next `continueStroke` is dispatched ONLY after the previous
 *   `GestureResultCallback.onCompleted`.
 * - Pointer moves that arrive while a segment is in flight are coalesced into the next segment.
 * - Each segment gets a duration covering the real elapsed time (`[minDurationMs, maxDurationMs]`).
 * - On `onCancelled`, the drag is marked lost (`dragLost = true`), subsequent moves are ignored,
 *   and releasing (`onStrokeEnd`) does NOT dispatch a tap or stroke.
 * - On forced release (`forceEndAtCursor` for BLE disconnect, user Disconnect, `onInterrupt`,
 *   `ACTION_SCREEN_OFF`, `onUnbind`/`onDestroy`, or test mode), an in-flight stroke is terminated
 *   with a final non-continuing stroke (`willContinue = false`) at the cursor.
 */
class StrokeCoordinator(
    private val initialDurationMs: Long = 40L,
    private val minDurationMs: Long = 16L,
    private val maxDurationMs: Long = 500L,
) {
  var isActive: Boolean = false
    private set

  var isInFlight: Boolean = false
    private set

  var isDragLost: Boolean = false
    private set

  private var lastX: Float = 0f
  private var lastY: Float = 0f
  private var pendingX: Float = 0f
  private var pendingY: Float = 0f
  private var hasPendingMove: Boolean = false
  private var endRequested: Boolean = false
  private var lastSegmentTimeMs: Long = 0L
  private var latestEventTimeMs: Long = 0L

  /** Starts a new drag stroke at `(x, y)` at timestamp `nowMs`. */
  fun onStrokeStart(x: Float, y: Float, nowMs: Long): StrokeSegment {
    isActive = true
    isInFlight = true
    isDragLost = false
    hasPendingMove = false
    endRequested = false
    lastX = x
    lastY = y
    pendingX = x
    pendingY = y
    lastSegmentTimeMs = nowMs
    latestEventTimeMs = nowMs
    return StrokeSegment(
        fromX = x,
        fromY = y,
        toX = x,
        toY = y,
        durationMs = initialDurationMs,
        willContinue = true,
        isInitial = true,
    )
  }

  /**
   * Records a drag move to `(toX, toY)` at timestamp `nowMs`.
   *
   * When a segment is currently in flight (`isInFlight == true`), the move is coalesced into
   * `(pendingX, pendingY)` and `null` is returned until [onCompleted] fires.
   */
  fun onStrokeContinue(toX: Float, toY: Float, nowMs: Long): StrokeSegment? {
    if (!isActive || isDragLost || endRequested) return null
    pendingX = toX
    pendingY = toY
    latestEventTimeMs = maxOf(latestEventTimeMs, nowMs)
    if (isInFlight) {
      hasPendingMove = true
      return null
    }
    val duration = computeDuration(nowMs)
    lastSegmentTimeMs = maxOf(nowMs, lastSegmentTimeMs)
    val seg =
        StrokeSegment(
            fromX = lastX,
            fromY = lastY,
            toX = toX,
            toY = toY,
            durationMs = duration,
            willContinue = true,
            isInitial = false,
        )
    lastX = toX
    lastY = toY
    hasPendingMove = false
    isInFlight = true
    return seg
  }

  /**
   * Requests completion of the current drag stroke at `(toX, toY)` at timestamp `nowMs`.
   * - If the drag was cancelled (`isDragLost == true`), resets state and returns `null` (never
   *   dispatches a tap).
   * - If a segment is currently in flight, marks `endRequested = true` and returns `null` so the
   *   final `willContinue = false` segment is dispatched from [onCompleted].
   */
  fun onStrokeEnd(toX: Float, toY: Float, nowMs: Long): StrokeSegment? {
    if (isDragLost) {
      reset()
      return null
    }
    if (!isActive) {
      return null
    }
    pendingX = toX
    pendingY = toY
    latestEventTimeMs = maxOf(latestEventTimeMs, nowMs)
    if (isInFlight) {
      endRequested = true
      return null
    }
    val duration = computeDuration(nowMs)
    val seg =
        StrokeSegment(
            fromX = lastX,
            fromY = lastY,
            toX = toX,
            toY = toY,
            durationMs = duration,
            willContinue = false,
            isInitial = false,
        )
    reset()
    return seg
  }

  /**
   * Called from `GestureResultCallback.onCompleted` when the currently executing stroke segment
   * finishes. Dispatches any coalesced continuation or pending end segment with a duration covering
   * the real elapsed time.
   */
  fun onCompleted(nowMs: Long): StrokeSegment? {
    if (!isActive || isDragLost) {
      isInFlight = false
      return null
    }
    val effectiveNow = maxOf(nowMs, latestEventTimeMs)
    val duration = computeDuration(effectiveNow)
    lastSegmentTimeMs = effectiveNow

    if (endRequested) {
      val seg =
          StrokeSegment(
              fromX = lastX,
              fromY = lastY,
              toX = pendingX,
              toY = pendingY,
              durationMs = duration,
              willContinue = false,
              isInitial = false,
          )
      reset()
      return seg
    }

    if (hasPendingMove) {
      val seg =
          StrokeSegment(
              fromX = lastX,
              fromY = lastY,
              toX = pendingX,
              toY = pendingY,
              durationMs = duration,
              willContinue = true,
              isInitial = false,
          )
      lastX = pendingX
      lastY = pendingY
      hasPendingMove = false
      isInFlight = true
      return seg
    }

    isInFlight = false
    return null
  }

  /**
   * Called from `GestureResultCallback.onCancelled`. Marks the drag lost so subsequent moves and
   * the eventual release become no-ops (no tap on release).
   */
  fun onCancelled() {
    if (isActive) {
      isDragLost = true
    }
    isInFlight = false
    hasPendingMove = false
    endRequested = false
  }

  /**
   * Forces an immediate non-continuing end stroke at `(cursorX, cursorY)` if a drag is currently
   * active (used on disconnect, interrupt, screen-off, unbind/destroy, and test mode).
   */
  fun forceEndAtCursor(cursorX: Float, cursorY: Float, nowMs: Long): StrokeSegment? {
    if (!isActive || isDragLost) {
      reset()
      return null
    }
    val duration = computeDuration(nowMs)
    val seg =
        StrokeSegment(
            fromX = lastX,
            fromY = lastY,
            toX = cursorX,
            toY = cursorY,
            durationMs = duration,
            willContinue = false,
            isInitial = false,
        )
    reset()
    return seg
  }

  fun reset() {
    isActive = false
    isInFlight = false
    isDragLost = false
    hasPendingMove = false
    endRequested = false
  }

  private fun computeDuration(nowMs: Long): Long {
    val elapsed = (nowMs - lastSegmentTimeMs).coerceAtLeast(minDurationMs)
    return elapsed.coerceAtMost(maxDurationMs)
  }
}
