// Copyright (c) 2026 VitruvianSoftware

package com.vitruviansoftware.wand.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GesturePlannerTest {

  @Test
  fun plansCursorMovementScalingAndClamping() {
    // 1080px screen at density 2.7f -> pointerPixelScale = 1.35f.
    // Default sensitivity = 400 engine units per full swipe -> 2 swipes = 800 units * 1.35 =
    // 1080px.
    val config = PlannerConfig(screenWidth = 1080, screenHeight = 2400, density = 2.7f)
    val planner = GesturePlanner(config = config, initialX = 0f, initialY = 1200f)

    val swipe1 = planner.plan(WandAction.Move(dx = 400f, dy = 0f))
    assertEquals(listOf(PlannedCommand.MoveCursor(540f, 1200f)), swipe1)

    val swipe2 = planner.plan(WandAction.Move(dx = 400f, dy = 0f))
    assertEquals(listOf(PlannedCommand.MoveCursor(1080f, 1200f)), swipe2)

    // Clamping beyond right/bottom and left/top edges
    val clampHigh = planner.plan(WandAction.Move(dx = 500f, dy = 5000f))
    assertEquals(listOf(PlannedCommand.MoveCursor(1080f, 2400f)), clampHigh)

    val clampLow = planner.plan(WandAction.Move(dx = -5000f, dy = -5000f))
    assertEquals(listOf(PlannedCommand.MoveCursor(0f, 0f)), clampLow)
  }

  @Test
  fun plansDragSequenceMouseDownMoveMouseUp() {
    val config = PlannerConfig(screenWidth = 1000, screenHeight = 2000, density = 2.0f)
    val planner = GesturePlanner(config = config, initialX = 500f, initialY = 1000f)

    val commands =
        planner.planAll(
            listOf(
                WandAction.MouseDown,
                WandAction.Move(dx = 20f, dy = -10f),
                WandAction.Move(dx = 30f, dy = 15f),
                WandAction.MouseUp,
            ),
        )

    assertEquals(
        listOf(
            PlannedCommand.StrokeStart(500f, 1000f),
            PlannedCommand.MoveCursor(520f, 990f),
            PlannedCommand.StrokeContinue(fromX = 500f, fromY = 1000f, toX = 520f, toY = 990f),
            PlannedCommand.MoveCursor(550f, 1005f),
            PlannedCommand.StrokeContinue(fromX = 520f, fromY = 990f, toX = 550f, toY = 1005f),
            PlannedCommand.StrokeEnd(
                fromX = 550f,
                fromY = 1005f,
                toX = 550f,
                toY = 1005f,
                wasDrag = true,
            ),
        ),
        commands,
    )
    assertFalse(planner.isDragging)
  }

  @Test
  fun scrollWithReverseOnInSettingsProducesSameDirectionAsReverseOff() {
    val reverseOffConfig =
        PlannerConfig(
            screenWidth = 1080,
            screenHeight = 2400,
            density = 2.0f,
            scrollStrength = 1.0f,
            reverseScroll = false,
            horizontalScroll = true,
        )
    val reverseOnConfig =
        reverseOffConfig.copy(
            reverseScroll = true,
            scrollStrength = 3.0f,
        )
    val plannerOff = GesturePlanner(config = reverseOffConfig, initialX = 540f, initialY = 1200f)
    val plannerOn = GesturePlanner(config = reverseOnConfig, initialX = 540f, initialY = 1200f)

    val swipeOff =
        plannerOff.plan(WandAction.Scroll(dx = 0f, dy = 1f)).single() as PlannedCommand.Swipe
    val swipeOn =
        plannerOn.plan(WandAction.Scroll(dx = 0f, dy = 1f)).single() as PlannedCommand.Swipe

    assertEquals(
        "Planner must NOT re-apply reverseScroll (engine already owns it)",
        swipeOff.direction,
        swipeOn.direction,
    )
    assertEquals(
        "Planner must NOT re-apply scrollStrength (engine already scales dx/dy)",
        swipeOff.distancePx,
        swipeOn.distancePx,
        1e-2f,
    )
  }

  @Test
  fun plansScrollUnitsDirectlyFromEngineValues() {
    val config =
        PlannerConfig(
            screenWidth = 1080,
            screenHeight = 2400,
            density = 2.0f,
        )
    val planner = GesturePlanner(config = config, initialX = 540f, initialY = 1200f)

    val upSwipe = planner.plan(WandAction.Scroll(dx = 0f, dy = 1f)).single() as PlannedCommand.Swipe
    assertEquals(ScrollDirection.UP, upSwipe.direction)
    assertTrue("Swipe UP moves finger upward (endY < startY)", upSwipe.endY < upSwipe.startY)

    // Engine-scaled dy = 2.0 doubles swipe distance
    val strongSwipe =
        planner.plan(WandAction.Scroll(dx = 0f, dy = 2f)).single() as PlannedCommand.Swipe
    assertEquals(upSwipe.distancePx * 2f, strongSwipe.distancePx, 1e-2f)

    // Engine-reversed dy = -1.0 produces ScrollDirection.DOWN
    val downSwipe =
        planner.plan(WandAction.Scroll(dx = 0f, dy = -1f)).single() as PlannedCommand.Swipe
    assertEquals(ScrollDirection.DOWN, downSwipe.direction)
    assertTrue(
        "Swipe DOWN moves finger downward (endY > startY)", downSwipe.endY > downSwipe.startY)

    // Horizontal scroll right (dx = +1) and left (dx = -1)
    val rightSwipe =
        planner.plan(WandAction.Scroll(dx = 1f, dy = 0f)).single() as PlannedCommand.Swipe
    assertEquals(ScrollDirection.RIGHT, rightSwipe.direction)

    val leftSwipe =
        planner.plan(WandAction.Scroll(dx = -1f, dy = 0f)).single() as PlannedCommand.Swipe
    assertEquals(ScrollDirection.LEFT, leftSwipe.direction)
  }

  @Test
  fun plansTvFocusMovesAndAllSystemAndActionCommands() {
    val tvConfig =
        PlannerConfig(screenWidth = 1920, screenHeight = 1080, density = 2.0f, isTv = true)
    val planner = GesturePlanner(config = tvConfig, initialX = 960f, initialY = 540f)

    val focusCommands =
        planner.planAll(
            listOf(
                WandAction.DPad(DPadDirection.UP),
                WandAction.DPad(DPadDirection.DOWN),
                WandAction.DPad(DPadDirection.LEFT),
                WandAction.DPad(DPadDirection.RIGHT),
                WandAction.DPad(DPadDirection.CENTER),
            ),
        )
    assertEquals(
        listOf(
            PlannedCommand.FocusMove(DPadDirection.UP),
            PlannedCommand.FocusMove(DPadDirection.DOWN),
            PlannedCommand.FocusMove(DPadDirection.LEFT),
            PlannedCommand.FocusMove(DPadDirection.RIGHT),
            PlannedCommand.FocusMove(DPadDirection.CENTER),
        ),
        focusCommands,
    )

    val miscCommands =
        planner.planAll(
            listOf(
                WandAction.LeftClick,
                WandAction.RightClick,
                WandAction.Nav(NavKind.BACK),
                WandAction.Nav(NavKind.HOME),
                WandAction.Nav(NavKind.RECENTS),
                WandAction.Nav(NavKind.NOTIFICATIONS),
                WandAction.Nav(NavKind.QUICK_SETTINGS),
                WandAction.Media(MediaKind.PLAY_PAUSE),
                WandAction.Media(MediaKind.NEXT),
                WandAction.Media(MediaKind.PREVIOUS),
                WandAction.Volume(VolumeKind.UP),
                WandAction.Volume(VolumeKind.DOWN),
                WandAction.Volume(VolumeKind.MUTE),
                WandAction.LaunchApp("com.netflix.ninja"),
                WandAction.ScreenOff,
                WandAction.Assistant,
                WandAction.VoiceTyping,
                WandAction.Brightness(BrightnessKind.UP),
                WandAction.Brightness(BrightnessKind.DOWN),
                WandAction.Key(key = "Enter"),
                WandAction.System(SystemKind.COPY),
                WandAction.System(SystemKind.PASTE),
                WandAction.System(SystemKind.APP_SWITCHER),
                WandAction.System(SystemKind.SHOW_DESKTOP),
                WandAction.ToggleGyro,
                WandAction.RadialMenu,
            ),
        )

    assertEquals(
        listOf(
            PlannedCommand.Tap(960f, 540f),
            PlannedCommand.SecondaryTap(960f, 540f),
            PlannedCommand.Global(GlobalCommand.BACK),
            PlannedCommand.Global(GlobalCommand.HOME),
            PlannedCommand.Global(GlobalCommand.RECENTS),
            PlannedCommand.Global(GlobalCommand.NOTIFICATIONS),
            PlannedCommand.Global(GlobalCommand.QUICK_SETTINGS),
            PlannedCommand.Media(MediaCommand.PLAY_PAUSE),
            PlannedCommand.Media(MediaCommand.NEXT),
            PlannedCommand.Media(MediaCommand.PREVIOUS),
            PlannedCommand.Volume(VolumeCommand.UP),
            PlannedCommand.Volume(VolumeCommand.DOWN),
            PlannedCommand.Volume(VolumeCommand.MUTE),
            PlannedCommand.LaunchApp("com.netflix.ninja"),
            PlannedCommand.ScreenOff,
            PlannedCommand.Assistant,
            PlannedCommand.VoiceTyping,
            PlannedCommand.Brightness(BrightnessKind.UP),
            PlannedCommand.Brightness(BrightnessKind.DOWN),
            PlannedCommand.Key(key = "Enter"),
            PlannedCommand.System(SystemKind.COPY),
            PlannedCommand.System(SystemKind.PASTE),
            PlannedCommand.Global(GlobalCommand.RECENTS),
            PlannedCommand.Global(GlobalCommand.HOME),
            PlannedCommand.ToggleGyro,
            PlannedCommand.RadialMenu,
        ),
        miscCommands,
    )
  }

  @Test
  fun plansStationaryMouseDownUpAndIgnoresMouseUpWithoutActiveDrag() {
    val config = PlannerConfig(screenWidth = 1000, screenHeight = 2000, density = 2.0f)
    val planner = GesturePlanner(config = config, initialX = 400f, initialY = 800f)

    // MouseDown followed immediately by MouseUp without Move -> StrokeEnd(wasDrag = false)
    val clickHoldRelease =
        planner.planAll(
            listOf(
                WandAction.MouseDown,
                WandAction.MouseUp,
            ),
        )
    assertEquals(
        listOf(
            PlannedCommand.StrokeStart(400f, 800f),
            PlannedCommand.StrokeEnd(
                fromX = 400f,
                fromY = 800f,
                toX = 400f,
                toY = 800f,
                wasDrag = false,
            ),
        ),
        clickHoldRelease,
    )

    // MouseUp when not dragging (or after cancelDrag) must NOT emit a Tap
    val standaloneUp = planner.plan(WandAction.MouseUp)
    assertTrue(
        "MouseUp without an active drag must not emit a spurious Tap",
        standaloneUp.isEmpty(),
    )

    planner.plan(WandAction.MouseDown)
    assertTrue(planner.isDragging)
    planner.cancelDrag()
    assertFalse(planner.isDragging)
    assertTrue(planner.plan(WandAction.MouseUp).isEmpty())
  }

  @Test
  fun clampsScrollSwipesInsideScreenBounds() {
    val config =
        PlannerConfig(
            screenWidth = 1080,
            screenHeight = 2400,
            density = 3.0f,
        )
    val planner = GesturePlanner(config = config, initialX = 0f, initialY = 0f)

    // Vertical swipe UP from top edge clamps startX/startY to margin (24px) and endY to >= 0f
    val swipeNearTop =
        planner.plan(WandAction.Scroll(dx = 0f, dy = 2.0f)).single() as PlannedCommand.Swipe
    assertEquals(24f, swipeNearTop.startX, 1e-4f)
    assertEquals(24f, swipeNearTop.startY, 1e-4f)
    assertEquals(0f, swipeNearTop.endY, 1e-4f)

    // Bottom-right corner and swipe DOWN -> endY clamped to screenHeight (2400f)
    planner.setCursor(1080f, 2400f)
    val swipeNearBottom =
        planner.plan(WandAction.Scroll(dx = 0f, dy = -2.0f)).single() as PlannedCommand.Swipe
    assertEquals(1080f - 24f, swipeNearBottom.startX, 1e-4f)
    assertEquals(2400f - 24f, swipeNearBottom.startY, 1e-4f)
    assertEquals(2400f, swipeNearBottom.endY, 1e-4f)
  }
}
