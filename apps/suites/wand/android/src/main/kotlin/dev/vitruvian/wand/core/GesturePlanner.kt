// Copyright (c) 2026 VitruvianSoftware

package dev.vitruvian.wand.core

import kotlin.math.abs

/** Global accessibility actions executed via `AccessibilityService.performGlobalAction`. */
enum class GlobalCommand {
  BACK,
  HOME,
  RECENTS,
  NOTIFICATIONS,
  QUICK_SETTINGS,
}

/** Media key commands dispatched via `AudioManager.dispatchMediaKeyEvent`. */
enum class MediaCommand {
  PLAY_PAUSE,
  NEXT,
  PREVIOUS,
}

/** Volume adjustments dispatched via `AudioManager.adjustStreamVolume`. */
enum class VolumeCommand {
  UP,
  DOWN,
  MUTE,
}

/** Cardinal swipe direction for scroll gestures. */
enum class ScrollDirection {
  UP,
  DOWN,
  LEFT,
  RIGHT,
}

/** Concrete platform commands planned by [GesturePlanner] from [WandAction] events. */
sealed class PlannedCommand {
  data class MoveCursor(val x: Float, val y: Float) : PlannedCommand()

  data class Tap(val x: Float, val y: Float) : PlannedCommand()

  data class SecondaryTap(val x: Float, val y: Float) : PlannedCommand()

  data class StrokeStart(val x: Float, val y: Float) : PlannedCommand()

  data class StrokeContinue(
      val fromX: Float,
      val fromY: Float,
      val toX: Float,
      val toY: Float,
  ) : PlannedCommand()

  data class StrokeEnd(
      val fromX: Float,
      val fromY: Float,
      val toX: Float,
      val toY: Float,
      val wasDrag: Boolean,
  ) : PlannedCommand()

  data class Swipe(
      val startX: Float,
      val startY: Float,
      val endX: Float,
      val endY: Float,
      val direction: ScrollDirection,
      val distancePx: Float,
      val durationMs: Long = 180L,
  ) : PlannedCommand()

  data class Global(val action: GlobalCommand) : PlannedCommand()

  data class Media(val command: MediaCommand) : PlannedCommand()

  data class Volume(val command: VolumeCommand) : PlannedCommand()

  data class FocusMove(val direction: DPadDirection) : PlannedCommand()

  data class LaunchApp(val packageName: String) : PlannedCommand()

  data object ScreenOff : PlannedCommand()

  data object Assistant : PlannedCommand()

  data object VoiceTyping : PlannedCommand()

  data class Brightness(val kind: BrightnessKind) : PlannedCommand()

  data class Key(
      val key: String,
      val ctrl: Boolean = false,
      val alt: Boolean = false,
      val shift: Boolean = false,
      val meta: Boolean = false,
  ) : PlannedCommand()

  data class System(val kind: SystemKind) : PlannedCommand()

  data object ToggleGyro : PlannedCommand()

  data object RadialMenu : PlannedCommand()
}

/**
 * Runtime planner settings derived from screen geometry.
 *
 * Note: `reverseScroll` and `scrollStrength` are owned and applied by `wand_core::Engine` before
 * `Action::Scroll` is emitted. [GesturePlanner] only converts the engine's scroll units into a
 * swipe distance in pixels and never reads `reverseScroll` or `scrollStrength`.
 */
data class PlannerConfig(
    val screenWidth: Int = 1080,
    val screenHeight: Int = 2400,
    val density: Float = 2.75f,
    val scrollStrength: Float = 1.0f,
    val reverseScroll: Boolean = false,
    val horizontalScroll: Boolean = false,
    val isTv: Boolean = false,
) {
  /**
   * Density-based pointer pixel scale so default touch sensitivity (`400.0`, producing ~400 engine
   * units per full touchpad width) crosses a ~400dp screen width in ~2 swipes.
   */
  val pointerPixelScale: Float
    get() = (density * 0.5f).coerceAtLeast(0.5f)
}

/**
 * Pure Kotlin stateful planner that converts [WandAction] lists + cursor coordinates + screen
 * geometry into [PlannedCommand]s for `WandAccessibilityService`.
 */
class GesturePlanner(
    config: PlannerConfig = PlannerConfig(),
    initialX: Float = config.screenWidth / 2f,
    initialY: Float = config.screenHeight / 2f,
) {
  var config: PlannerConfig = config
    private set

  var cursorX: Float = clampX(initialX, config.screenWidth)
    private set

  var cursorY: Float = clampY(initialY, config.screenHeight)
    private set

  var isDragging: Boolean = false
    private set

  private var dragMoved: Boolean = false
  private var strokeLastX: Float = cursorX
  private var strokeLastY: Float = cursorY

  fun updateConfig(newConfig: PlannerConfig) {
    config = newConfig
    cursorX = clampX(cursorX, newConfig.screenWidth)
    cursorY = clampY(cursorY, newConfig.screenHeight)
  }

  fun setCursor(x: Float, y: Float) {
    cursorX = clampX(x, config.screenWidth)
    cursorY = clampY(y, config.screenHeight)
  }

  fun cancelDrag() {
    isDragging = false
    dragMoved = false
  }

  fun planAll(actions: List<WandAction>): List<PlannedCommand> {
    if (actions.isEmpty()) return emptyList()
    val out = ArrayList<PlannedCommand>(actions.size * 2)
    for (action in actions) {
      planInto(action, out)
    }
    return out
  }

  fun plan(action: WandAction): List<PlannedCommand> {
    val out = ArrayList<PlannedCommand>(2)
    planInto(action, out)
    return out
  }

  private fun planInto(action: WandAction, out: MutableList<PlannedCommand>) {
    when (action) {
      is WandAction.Move -> {
        val scale = config.pointerPixelScale
        val nextX = clampX(cursorX + action.dx * scale, config.screenWidth)
        val nextY = clampY(cursorY + action.dy * scale, config.screenHeight)
        cursorX = nextX
        cursorY = nextY
        out.add(PlannedCommand.MoveCursor(cursorX, cursorY))
        if (isDragging) {
          dragMoved = true
          out.add(
              PlannedCommand.StrokeContinue(
                  fromX = strokeLastX,
                  fromY = strokeLastY,
                  toX = cursorX,
                  toY = cursorY,
              ),
          )
          strokeLastX = cursorX
          strokeLastY = cursorY
        }
      }
      WandAction.LeftClick -> {
        out.add(PlannedCommand.Tap(cursorX, cursorY))
      }
      WandAction.RightClick -> {
        out.add(PlannedCommand.SecondaryTap(cursorX, cursorY))
      }
      WandAction.MouseDown -> {
        isDragging = true
        dragMoved = false
        strokeLastX = cursorX
        strokeLastY = cursorY
        out.add(PlannedCommand.StrokeStart(cursorX, cursorY))
      }
      WandAction.MouseUp -> {
        if (isDragging) {
          isDragging = false
          out.add(
              PlannedCommand.StrokeEnd(
                  fromX = strokeLastX,
                  fromY = strokeLastY,
                  toX = cursorX,
                  toY = cursorY,
                  wasDrag = dragMoved,
              ),
          )
          dragMoved = false
        }
      }
      is WandAction.Scroll -> {
        planScroll(action.dx, action.dy)?.let { out.add(it) }
      }
      is WandAction.Nav -> {
        val global =
            when (action.kind) {
              NavKind.BACK -> GlobalCommand.BACK
              NavKind.HOME -> GlobalCommand.HOME
              NavKind.RECENTS -> GlobalCommand.RECENTS
              NavKind.NOTIFICATIONS -> GlobalCommand.NOTIFICATIONS
              NavKind.QUICK_SETTINGS -> GlobalCommand.QUICK_SETTINGS
            }
        out.add(PlannedCommand.Global(global))
      }
      is WandAction.Media -> {
        val media =
            when (action.kind) {
              MediaKind.PLAY_PAUSE -> MediaCommand.PLAY_PAUSE
              MediaKind.NEXT -> MediaCommand.NEXT
              MediaKind.PREVIOUS -> MediaCommand.PREVIOUS
            }
        out.add(PlannedCommand.Media(media))
      }
      is WandAction.Volume -> {
        val vol =
            when (action.kind) {
              VolumeKind.UP -> VolumeCommand.UP
              VolumeKind.DOWN -> VolumeCommand.DOWN
              VolumeKind.MUTE -> VolumeCommand.MUTE
            }
        out.add(PlannedCommand.Volume(vol))
      }
      is WandAction.DPad -> {
        out.add(PlannedCommand.FocusMove(action.direction))
      }
      is WandAction.LaunchApp -> {
        if (action.packageName.isNotBlank()) {
          out.add(PlannedCommand.LaunchApp(action.packageName))
        }
      }
      WandAction.ScreenOff -> {
        out.add(PlannedCommand.ScreenOff)
      }
      WandAction.Assistant -> {
        out.add(PlannedCommand.Assistant)
      }
      WandAction.VoiceTyping -> {
        out.add(PlannedCommand.VoiceTyping)
      }
      is WandAction.Brightness -> {
        out.add(PlannedCommand.Brightness(action.kind))
      }
      is WandAction.Key -> {
        out.add(
            PlannedCommand.Key(
                key = action.key,
                ctrl = action.ctrl,
                alt = action.alt,
                shift = action.shift,
                meta = action.meta,
            ),
        )
      }
      is WandAction.System -> {
        when (action.kind) {
          SystemKind.APP_SWITCHER,
          SystemKind.MISSION_CONTROL -> out.add(PlannedCommand.Global(GlobalCommand.RECENTS))
          SystemKind.SHOW_DESKTOP -> out.add(PlannedCommand.Global(GlobalCommand.HOME))
          else -> out.add(PlannedCommand.System(action.kind))
        }
      }
      WandAction.ToggleGyro -> {
        out.add(PlannedCommand.ToggleGyro)
      }
      WandAction.RadialMenu -> {
        out.add(PlannedCommand.RadialMenu)
      }
    }
  }

  /**
   * Converts engine scroll units `(dx, dy)` into a swipe distance in pixels.
   *
   * `wand_core::Engine` already applies `reverse_scroll` and `scroll_strength`, so this method
   * never reads those settings.
   */
  private fun planScroll(dx: Float, dy: Float): PlannedCommand.Swipe? {
    if (abs(dx) < 1e-4f && abs(dy) < 1e-4f) return null

    val baseDistance = 120f * config.density.coerceAtLeast(1f)
    val margin = 24f

    val startX = cursorX.coerceIn(margin, (config.screenWidth - margin).coerceAtLeast(margin))
    val startY = cursorY.coerceIn(margin, (config.screenHeight - margin).coerceAtLeast(margin))

    return if (abs(dy) >= abs(dx)) {
      val dist = baseDistance * abs(dy).coerceIn(0.1f, 5.0f)
      val direction = if (dy > 0f) ScrollDirection.UP else ScrollDirection.DOWN
      val deltaY = if (dy > 0f) -dist else dist
      val endY = clampY(startY + deltaY, config.screenHeight)
      PlannedCommand.Swipe(
          startX = startX,
          startY = startY,
          endX = startX,
          endY = endY,
          direction = direction,
          distancePx = dist,
      )
    } else {
      val dist = baseDistance * abs(dx).coerceIn(0.1f, 5.0f)
      val direction = if (dx > 0f) ScrollDirection.RIGHT else ScrollDirection.LEFT
      val deltaX = if (dx > 0f) -dist else dist
      val endX = clampX(startX + deltaX, config.screenWidth)
      PlannedCommand.Swipe(
          startX = startX,
          startY = startY,
          endX = endX,
          endY = startY,
          direction = direction,
          distancePx = dist,
      )
    }
  }

  companion object {
    fun clampX(x: Float, width: Int): Float = x.coerceIn(0f, width.coerceAtLeast(1).toFloat())

    fun clampY(y: Float, height: Int): Float = y.coerceIn(0f, height.coerceAtLeast(1).toFloat())
  }
}
