// Copyright (c) 2026 VitruvianSoftware

package com.vitruviansoftware.wand.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActionsTest {

  @Test
  fun parsesAndSerializesEveryActionType() {
    val rawJson =
        """
            [
              {"type":"left_click"},
              {"type":"right_click"},
              {"type":"mouse_down"},
              {"type":"mouse_up"},
              {"type":"scroll","value":{"dx":0.5,"dy":-1.25}},
              {"type":"media","value":"play_pause"},
              {"type":"media","value":"next"},
              {"type":"media","value":"previous"},
              {"type":"volume","value":"up"},
              {"type":"volume","value":"down"},
              {"type":"volume","value":"mute"},
              {"type":"brightness","value":"up"},
              {"type":"brightness","value":"down"},
              {"type":"key","value":{"key":"Escape","ctrl":true,"alt":false,"shift":true,"meta":false}},
              {"type":"system","value":"copy"},
              {"type":"system","value":"paste"},
              {"type":"system","value":"app_switcher"},
              {"type":"toggle_gyro"},
              {"type":"launch_app","value":"com.google.android.youtube.tv"},
              {"type":"radial_menu"},
              {"type":"nav","value":"back"},
              {"type":"nav","value":"home"},
              {"type":"nav","value":"recents"},
              {"type":"nav","value":"notifications"},
              {"type":"nav","value":"quick_settings"},
              {"type":"d_pad","value":"up"},
              {"type":"d_pad","value":"down"},
              {"type":"d_pad","value":"left"},
              {"type":"d_pad","value":"right"},
              {"type":"d_pad","value":"center"},
              {"type":"screen_off"},
              {"type":"assistant"},
              {"type":"voice_typing"},
              {"type":"move","value":{"dx":14.0,"dy":-6.5}}
            ]
        """
            .trimIndent()

    val result = WandJson.parseActions(rawJson)
    assertTrue("Expected Ok result, got $result", result is WandJsonResult.Ok)
    val actions = (result as WandJsonResult.Ok).value
    assertEquals(34, actions.size)

    val expected =
        listOf(
            WandAction.LeftClick,
            WandAction.RightClick,
            WandAction.MouseDown,
            WandAction.MouseUp,
            WandAction.Scroll(0.5f, -1.25f),
            WandAction.Media(MediaKind.PLAY_PAUSE),
            WandAction.Media(MediaKind.NEXT),
            WandAction.Media(MediaKind.PREVIOUS),
            WandAction.Volume(VolumeKind.UP),
            WandAction.Volume(VolumeKind.DOWN),
            WandAction.Volume(VolumeKind.MUTE),
            WandAction.Brightness(BrightnessKind.UP),
            WandAction.Brightness(BrightnessKind.DOWN),
            WandAction.Key(key = "Escape", ctrl = true, alt = false, shift = true, meta = false),
            WandAction.System(SystemKind.COPY),
            WandAction.System(SystemKind.PASTE),
            WandAction.System(SystemKind.APP_SWITCHER),
            WandAction.ToggleGyro,
            WandAction.LaunchApp("com.google.android.youtube.tv"),
            WandAction.RadialMenu,
            WandAction.Nav(NavKind.BACK),
            WandAction.Nav(NavKind.HOME),
            WandAction.Nav(NavKind.RECENTS),
            WandAction.Nav(NavKind.NOTIFICATIONS),
            WandAction.Nav(NavKind.QUICK_SETTINGS),
            WandAction.DPad(DPadDirection.UP),
            WandAction.DPad(DPadDirection.DOWN),
            WandAction.DPad(DPadDirection.LEFT),
            WandAction.DPad(DPadDirection.RIGHT),
            WandAction.DPad(DPadDirection.CENTER),
            WandAction.ScreenOff,
            WandAction.Assistant,
            WandAction.VoiceTyping,
            WandAction.Move(14.0f, -6.5f),
        )
    assertEquals(expected, actions)

    for (action in expected) {
      val encoded = WandJson.serializeAction(action)
      val decoded = WandJson.parseAction(encoded)
      assertEquals(action, decoded)
    }
  }

  @Test
  fun kotlinDoesNotDefineConflictingDefaultBindings() {
    val emptyConfig = WandConfig()
    assertTrue(
        "Kotlin WandConfig must not hardcode default bindings (owned by vitruvian_wand_core)",
        emptyConfig.bindings.isEmpty(),
    )

    val parsedWithoutBindings = WandJson.parseConfig("""{"version":1,"platform":"android"}""")
    assertTrue(parsedWithoutBindings is WandJsonResult.Ok)
    assertTrue((parsedWithoutBindings as WandJsonResult.Ok).value.bindings.isEmpty())
  }

  @Test
  fun parsesErrorJsonAndConfigAndSample() {
    val errRes = WandJson.parseActions("""{"error":"invalid config JSON"}""")
    assertEquals(WandJsonResult.Error("invalid config JSON"), errRes)

    val initialConfig =
        WandConfig(
                version = 1,
                platform = "android",
                settings =
                    WandSettings(
                        touchSensitivity = 520f,
                        reverseScroll = true,
                        scrollStrength = 1.8f,
                        horizontalScroll = true,
                        overlayCursor = true,
                        overlayCursorSize = 32f,
                    ),
                bindings =
                    mapOf(
                        "home.short" to
                            WandBinding(WandAction.Nav(NavKind.BACK), WandTriggerMode.ONCE),
                        "home.long" to
                            WandBinding(WandAction.Nav(NavKind.HOME), WandTriggerMode.ONCE),
                        "app.short" to WandBinding(WandAction.ToggleGyro, WandTriggerMode.ONCE),
                    ),
            )
            .withBinding(
                WandButton.HOME,
                WandPress.DOUBLE,
                WandBinding(
                    WandAction.LaunchApp("com.vitruviansoftware.wand"), WandTriggerMode.ONCE),
            )

    val json = WandJson.serializeConfig(initialConfig)
    val parsed = WandJson.parseConfig(json)
    assertTrue(parsed is WandJsonResult.Ok)
    assertEquals(initialConfig, (parsed as WandJsonResult.Ok).value)

    assertNull(WandJson.parseSample("null"))
    val sample =
        WandJson.parseSample(
            """
            {
              "time": 120,
              "seq": 7,
              "orientation": {"x": 0.1, "y": -0.2, "z": 0.3},
              "accel": {"x": 0.0, "y": 9.8, "z": 0.1},
              "gyro": {"x": 1.5, "y": -0.5, "z": 0.0},
              "touch_x": 0.5,
              "touch_y": 0.75,
              "touching": true,
              "click": true,
              "home": false,
              "app": true,
              "vol_down": false,
              "vol_up": true
            }
            """
                .trimIndent(),
        )
    assertNotNull(sample)
    assertEquals(7, sample!!.seq)
    assertTrue(sample.touching)
    assertTrue(sample.click)
    assertTrue(sample.app)
    assertTrue(sample.volUp)
    assertFalse(sample.home)
    assertEquals(0.5f, sample.touchX, 1e-4f)
    assertEquals(0.75f, sample.touchY, 1e-4f)
  }

  @Test
  fun parsesAllSystemVariantsAndDisplayLabels() {
    for (kind in SystemKind.entries) {
      val action = WandAction.System(kind)
      val json = WandJson.serializeAction(action)
      assertEquals(action, WandJson.parseAction(json))
      assertTrue(action.displayLabel().contains(kind.label))
    }
    assertEquals("Scroll Left", WandAction.Scroll(dx = -1f, dy = 0f).displayLabel())
    assertEquals("Scroll Right", WandAction.Scroll(dx = 1f, dy = 0f).displayLabel())
    assertEquals("Scroll Up", WandAction.Scroll(dx = 0f, dy = 1f).displayLabel())
    assertEquals("Scroll Down", WandAction.Scroll(dx = 0f, dy = -1f).displayLabel())
    assertEquals(
        "Brightness: Brightness Up", WandAction.Brightness(BrightnessKind.UP).displayLabel())
    assertEquals(
        "Brightness: Brightness Down", WandAction.Brightness(BrightnessKind.DOWN).displayLabel())
  }
}
