// Copyright (c) 2026 VitruvianSoftware

package dev.vitruvian.wand.core

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeEngineTest {

  private class FakeScheduler : EngineScheduler {
    val queue = ArrayDeque<Runnable>()
    val delayed = LinkedHashMap<Runnable, Long>()
    var isShutdown = false

    override fun post(task: Runnable) {
      if (!isShutdown) {
        queue.addLast(task)
      }
    }

    override fun postDelayed(delayMs: Long, task: Runnable) {
      if (!isShutdown) {
        delayed[task] = delayMs
      }
    }

    override fun removeCallbacks(task: Runnable) {
      queue.remove(task)
      delayed.remove(task)
    }

    override fun shutdown() {
      isShutdown = true
      delayed.clear()
    }

    fun drainQueue() {
      while (queue.isNotEmpty()) {
        val next = queue.removeFirst()
        next.run()
      }
    }

    fun triggerDelayed() {
      val tasks = delayed.keys.toList()
      delayed.clear()
      for (t in tasks) {
        t.run()
      }
    }
  }

  private class FakeBackend : WandNativeBackend {
    override val isAvailable: Boolean = true
    val calls = mutableListOf<String>()
    var nextFeedJson: String = """[{"type":"move","value":{"dx":5.0,"dy":-2.0}}]"""
    var nextTickJson: String = """[{"type":"nav","value":"home"}]"""
    var nextReleaseJson: String = """[{"type":"mouse_up"}]"""

    override fun create(platform: Int, configJson: String): Long {
      calls.add("create($platform)")
      return 42L
    }

    override fun destroy(handle: Long) {
      calls.add("destroy($handle)")
    }

    override fun defaultConfig(platform: Int): String {
      calls.add("defaultConfig($platform)")
      val platformName = if (platform == WandNative.PLATFORM_ANDROID_TV) "android_tv" else "android"
      return """
                {
                  "version": 1,
                  "platform": "$platformName",
                  "settings": {"touch_sensitivity": 612.5},
                  "bindings": {
                    "home.short": {"action": {"type": "nav", "value": "back"}, "trigger": "once"},
                    "home.long": {"action": {"type": "nav", "value": "home"}, "trigger": "once"}
                  }
                }
            """
          .trimIndent()
    }

    override fun feed(handle: Long, packet: ByteArray, timestampUs: Long): String {
      calls.add("feed($handle,$timestampUs)")
      return nextFeedJson
    }

    override fun tick(handle: Long, timestampUs: Long): String {
      calls.add("tick($handle,$timestampUs)")
      return nextTickJson
    }

    override fun releaseAll(handle: Long): String {
      calls.add("releaseAll($handle)")
      return nextReleaseJson
    }

    override fun setConfig(handle: Long, configJson: String): String {
      calls.add("setConfig($handle)")
      return """{"ok":true}"""
    }

    override fun getConfig(handle: Long): String {
      calls.add("getConfig($handle)")
      return defaultConfig(WandNative.PLATFORM_ANDROID)
    }

    override fun setTestMode(handle: Long, enabled: Boolean) {
      calls.add("setTestMode($handle,$enabled)")
    }

    override fun recalibrate(handle: Long) {
      calls.add("recalibrate($handle)")
    }

    override fun lastSample(handle: Long): String {
      calls.add("lastSample($handle)")
      return """{"time":1,"seq":2,"touch_x":0.5,"touch_y":0.5,"touching":true}"""
    }

    override fun batteryLow(level: Int): Boolean {
      calls.add("batteryLow($level)")
      return level < 15
    }
  }

  @Test
  fun usesNativeDefaultConfigOnFirstRunAndOnResetInsteadOfKotlinFallback() {
    val scheduler = FakeScheduler()
    val backend = FakeBackend()
    val tempDir = Files.createTempDirectory("wand_native_engine_test").toFile()
    val configFile = File(tempDir, "wand_config.json")
    assertFalse(configFile.exists())

    val engine =
        NativeEngine(
            scheduler = scheduler,
            backend = backend,
            clockUs = { 10_000L },
            onActions = {},
        )

    // 1. First run: configFile does not exist yet.
    var firstRunConfig: WandConfig? = null
    engine.loadConfig(
        configFile = configFile,
        isTv = false,
        initializeEngine = true,
    ) { loaded ->
      firstRunConfig = loaded
    }
    // Confined to engine thread: nothing runs until scheduler drains.
    assertTrue(backend.calls.isEmpty())

    scheduler.drainQueue()
    val initial = firstRunConfig
    assertNotNull("Expected first-run config to be delivered", initial)
    assertEquals(listOf("defaultConfig(1)", "create(1)"), backend.calls)
    // Must match the fake native layer's default JSON, NOT the Kotlin fallback (400.0f / empty
    // bindings).
    assertEquals(612.5f, initial!!.settings.touchSensitivity, 1e-4f)
    assertEquals(
        WandBinding(WandAction.Nav(NavKind.BACK), WandTriggerMode.ONCE),
        initial.bindingFor(WandButton.HOME, WandPress.SHORT),
    )
    assertEquals(
        WandBinding(WandAction.Nav(NavKind.HOME), WandTriggerMode.ONCE),
        initial.bindingFor(WandButton.HOME, WandPress.LONG),
    )
    assertTrue(configFile.exists())
    val persistedFirstRun = (WandJson.parseConfig(configFile.readText()) as WandJsonResult.Ok).value
    assertEquals(612.5f, persistedFirstRun.settings.touchSensitivity, 1e-4f)
    assertEquals(2, persistedFirstRun.bindings.size)

    // 2. Overwrite configFile with custom settings and empty bindings, then Reset.
    val customized =
        WandConfig(
            platform = "android",
            settings = WandSettings(touchSensitivity = 250.0f),
            bindings = emptyMap(),
        )
    configFile.writeText(WandJson.serializeConfig(customized))
    backend.calls.clear()

    var resetConfig: WandConfig? = null
    engine.resetToDefaults(configFile = configFile, isTv = false) { defaults ->
      resetConfig = defaults
    }
    assertTrue(backend.calls.isEmpty())

    scheduler.drainQueue()
    val afterReset = resetConfig
    assertNotNull("Expected reset config to be delivered", afterReset)
    assertEquals(listOf("defaultConfig(1)", "setConfig(42)"), backend.calls)
    assertEquals(612.5f, afterReset!!.settings.touchSensitivity, 1e-4f)
    assertEquals(
        WandBinding(WandAction.Nav(NavKind.BACK), WandTriggerMode.ONCE),
        afterReset.bindingFor(WandButton.HOME, WandPress.SHORT),
    )
    assertEquals(
        WandBinding(WandAction.Nav(NavKind.HOME), WandTriggerMode.ONCE),
        afterReset.bindingFor(WandButton.HOME, WandPress.LONG),
    )
    val persistedAfterReset =
        (WandJson.parseConfig(configFile.readText()) as WandJsonResult.Ok).value
    assertEquals(612.5f, persistedAfterReset.settings.touchSensitivity, 1e-4f)
    assertEquals(2, persistedAfterReset.bindings.size)

    // 3. Verify batteryLow also runs exclusively on the engine thread.
    backend.calls.clear()
    var batteryLowResult: Boolean? = null
    engine.batteryLow(12) { isLow -> batteryLowResult = isLow }
    assertTrue(backend.calls.isEmpty())
    scheduler.drainQueue()
    assertEquals(listOf("batteryLow(12)"), backend.calls)
    assertEquals(true, batteryLowResult)

    configFile.delete()
    tempDir.delete()
  }

  @Test
  fun confinesAllCallsToEngineThreadAndIgnoresCallsAfterDestroy() {
    val scheduler = FakeScheduler()
    val backend = FakeBackend()
    val receivedActions = mutableListOf<WandAction>()
    var nowUs = 100_000L

    val engine =
        NativeEngine(
            scheduler = scheduler,
            backend = backend,
            clockUs = { nowUs },
            onActions = { receivedActions.addAll(it) },
        )

    engine.create(WandNative.PLATFORM_ANDROID, "")
    engine.setConnected(true)
    engine.feed(ByteArray(20), 100_000L)
    // Before draining scheduler queue, no native calls have run yet (confined to scheduler)
    assertTrue(backend.calls.isEmpty())

    scheduler.drainQueue()
    assertEquals(listOf("create(1)", "feed(42,100000)"), backend.calls)
    assertEquals(listOf(WandAction.Move(5.0f, -2.0f)), receivedActions)

    // 20ms idle tick is scheduled while connected and no packet arrives
    assertEquals(1, scheduler.delayed.size)
    assertEquals(20L, scheduler.delayed.values.single())
    nowUs = 120_000L
    scheduler.triggerDelayed()
    assertTrue(backend.calls.contains("tick(42,120000)"))
    assertTrue(receivedActions.contains(WandAction.Nav(NavKind.HOME)))

    // Disconnect calls releaseAll on engine thread and stops 20ms tick timer
    engine.setConnected(false)
    scheduler.drainQueue()
    assertTrue(backend.calls.contains("releaseAll(42)"))
    assertTrue(receivedActions.contains(WandAction.MouseUp))
    assertTrue(scheduler.delayed.isEmpty())

    // Destroy is posted last; calls after destroy are no-ops
    engine.destroy()
    engine.feed(ByteArray(20), 200_000L)
    engine.recalibrate()
    engine.releaseAll()
    scheduler.drainQueue()

    assertEquals("destroy(42)", backend.calls.last())
    assertTrue(scheduler.isShutdown)
  }

  @Test
  fun turningTestModeOnCallsReleaseAllBeforeEnteringTestMode() {
    val scheduler = FakeScheduler()
    val backend = FakeBackend()
    val receivedActions = mutableListOf<WandAction>()
    val receivedSamples = mutableListOf<WandSample>()

    val engine =
        NativeEngine(
            scheduler = scheduler,
            backend = backend,
            clockUs = { 50_000L },
            onActions = { receivedActions.addAll(it) },
            onSample = { receivedSamples.add(it) },
        )

    engine.create(WandNative.PLATFORM_ANDROID, "")
    engine.setTestMode(true)
    engine.feed(ByteArray(20), 60_000L)
    scheduler.drainQueue()

    assertEquals(
        listOf(
            "create(1)",
            "releaseAll(42)",
            "setTestMode(42,true)",
            "feed(42,60000)",
            "lastSample(42)"),
        backend.calls,
    )
    assertEquals(listOf(WandAction.MouseUp), receivedActions)
    assertEquals(1, receivedSamples.size)
    assertFalse(receivedSamples.single().click)
    assertTrue(receivedSamples.single().touching)
  }
}
