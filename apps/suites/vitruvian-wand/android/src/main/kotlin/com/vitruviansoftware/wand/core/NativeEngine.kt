// Copyright (c) 2026 VitruvianSoftware

package com.vitruviansoftware.wand.core

import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Host-safe shim for `android.util.Log` so `:core` (`kt_jvm_library`) can log with `Log.w` /
 * `Log.e` and tag `"VitruvianWand"` both on Android devices and inside host JVM unit tests
 * (`kt_jvm_test`).
 */
internal object Log {
  fun w(tag: String, msg: String, tr: Throwable? = null): Int = invokeAndroidLog("w", tag, msg, tr)

  fun e(tag: String, msg: String, tr: Throwable? = null): Int = invokeAndroidLog("e", tag, msg, tr)

  private fun invokeAndroidLog(level: String, tag: String, msg: String, tr: Throwable?): Int {
    return try {
      val cls = Class.forName("android.util.Log")
      if (tr != null) {
        val m = cls.getMethod(level, String::class.java, String::class.java, Throwable::class.java)
        (m.invoke(null, tag, msg, tr) as? Int) ?: 0
      } else {
        val m = cls.getMethod(level, String::class.java, String::class.java)
        (m.invoke(null, tag, msg) as? Int) ?: 0
      }
    } catch (_: Throwable) {
      System.err.println("[$level/$tag] $msg${tr?.let { ": ${it.message}" } ?: ""}")
      0
    }
  }
}

/**
 * Abstraction over the single-threaded engine scheduler (`HandlerThread` on Android, or a
 * deterministic queue in host unit tests).
 */
interface EngineScheduler {
  fun post(task: Runnable)

  fun postDelayed(delayMs: Long, task: Runnable)

  fun removeCallbacks(task: Runnable)

  fun shutdown()
}

/**
 * Abstraction over [WandNative] JNI entrypoints so [NativeEngine] can be unit-tested on the host
 * without loading Android's `libvitruvian_wand_jni.so`.
 */
interface WandNativeBackend {
  val isAvailable: Boolean

  fun create(platform: Int, configJson: String): Long

  fun destroy(handle: Long)

  fun defaultConfig(platform: Int): String

  fun feed(handle: Long, packet: ByteArray, timestampUs: Long): String

  fun tick(handle: Long, timestampUs: Long): String

  fun releaseAll(handle: Long): String

  fun setConfig(handle: Long, configJson: String): String

  fun getConfig(handle: Long): String

  fun setTestMode(handle: Long, enabled: Boolean)

  fun recalibrate(handle: Long)

  fun lastSample(handle: Long): String

  fun batteryLow(level: Int): Boolean
}

/** Production [WandNativeBackend] delegating to [WandNative] JNI methods. */
object JniWandNativeBackend : WandNativeBackend {
  override val isAvailable: Boolean
    get() = WandNative.isLoaded

  override fun create(platform: Int, configJson: String): Long =
      if (isAvailable) WandNative.nativeCreate(platform, configJson) else 0L

  override fun destroy(handle: Long) {
    if (isAvailable && handle != 0L) WandNative.nativeDestroy(handle)
  }

  override fun defaultConfig(platform: Int): String =
      if (isAvailable) WandNative.nativeDefaultConfig(platform) else ""

  override fun feed(handle: Long, packet: ByteArray, timestampUs: Long): String =
      if (isAvailable && handle != 0L) WandNative.nativeFeed(handle, packet, timestampUs) else "[]"

  override fun tick(handle: Long, timestampUs: Long): String =
      if (isAvailable && handle != 0L) WandNative.nativeTick(handle, timestampUs) else "[]"

  override fun releaseAll(handle: Long): String =
      if (isAvailable && handle != 0L) WandNative.nativeReleaseAll(handle) else "[]"

  override fun setConfig(handle: Long, configJson: String): String =
      if (isAvailable && handle != 0L) WandNative.nativeSetConfig(handle, configJson)
      else """{"ok":true}"""

  override fun getConfig(handle: Long): String =
      if (isAvailable && handle != 0L) WandNative.nativeGetConfig(handle) else ""

  override fun setTestMode(handle: Long, enabled: Boolean) {
    if (isAvailable && handle != 0L) WandNative.nativeSetTestMode(handle, enabled)
  }

  override fun recalibrate(handle: Long) {
    if (isAvailable && handle != 0L) WandNative.nativeRecalibrate(handle)
  }

  override fun lastSample(handle: Long): String =
      if (isAvailable && handle != 0L) WandNative.nativeLastSample(handle) else "null"

  override fun batteryLow(level: Int): Boolean =
      if (isAvailable) WandNative.nativeBatteryLow(level) else level < 15
}

/**
 * Confines EVERY native call (`create`, `feed`, `tick`, `set_config`, `get_config`,
 * `set_test_mode`, `recalibrate`, `release_all`, `last_sample`, `destroy`) to a single engine
 * thread ([scheduler]).
 * - Runs a 20 ms idle `tick` timer while connected whenever no packet has arrived within 20 ms.
 * - `destroy` is posted after BLE is stopped and is the final message executed on the engine
 *   thread; any calls made after `destroy` are no-ops.
 */
class NativeEngine(
    private val scheduler: EngineScheduler,
    private val backend: WandNativeBackend = JniWandNativeBackend,
    private val clockUs: () -> Long,
    private val onActions: (List<WandAction>) -> Unit,
    private val onSample: (WandSample) -> Unit = {},
    private val onError: (String) -> Unit = {},
) {
  private val destroyRequested = AtomicBoolean(false)

  @Volatile
  var isTestMode: Boolean = false
    private set

  // Accessed exclusively on the single engine thread:
  private var handle: Long = 0L
  private var destroyedOnThread: Boolean = false
  private var connectedOnThread: Boolean = false

  private val tickRunnable =
      object : Runnable {
        override fun run() {
          if (destroyedOnThread || destroyRequested.get() || !connectedOnThread || handle == 0L) {
            return
          }
          if (!isTestMode) {
            val json = backend.tick(handle, clockUs())
            dispatchParsedActions(json)
          }
          if (connectedOnThread && !destroyedOnThread && !destroyRequested.get()) {
            scheduler.postDelayed(TICK_INTERVAL_MS, this)
          }
        }
      }

  /** Creates the native engine instance on the engine thread. */
  fun create(platform: Int, configJson: String) {
    if (destroyRequested.get()) return
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get()) return@Runnable
          if (handle != 0L) {
            backend.destroy(handle)
            handle = 0L
          }
          handle = backend.create(platform, configJson)
        },
    )
  }

  /**
   * Updates connection state on the engine thread. When `connected` transitions to `true`, starts
   * the 20 ms idle tick loop; when `false`, stops the tick loop and calls `release_all`.
   */
  fun setConnected(connected: Boolean) {
    if (destroyRequested.get()) return
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get()) return@Runnable
          val wasConnected = connectedOnThread
          connectedOnThread = connected
          scheduler.removeCallbacks(tickRunnable)
          if (connected) {
            scheduler.postDelayed(TICK_INTERVAL_MS, tickRunnable)
          } else if (wasConnected && handle != 0L) {
            val releasedJson = backend.releaseAll(handle)
            dispatchParsedActions(releasedJson)
          }
        },
    )
  }

  /**
   * Feeds a 20-byte BLE notification packet on the engine thread and resets the 20 ms idle tick
   * timer so `nativeTick` only runs when no packet has arrived for 20 ms.
   */
  fun feed(packet: ByteArray, timestampUs: Long) {
    if (destroyRequested.get()) return
    val copy = packet.copyOf()
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get() || handle == 0L) return@Runnable
          // Reset the 20 ms tick timer since a packet just arrived.
          scheduler.removeCallbacks(tickRunnable)
          val actionsJson = backend.feed(handle, copy, timestampUs)
          if (isTestMode) {
            val sampleJson = backend.lastSample(handle)
            WandJson.parseSample(sampleJson)?.let(onSample)
          } else {
            dispatchParsedActions(actionsJson)
          }
          if (connectedOnThread && !destroyedOnThread && !destroyRequested.get()) {
            scheduler.postDelayed(TICK_INTERVAL_MS, tickRunnable)
          }
        },
    )
  }

  /** Explicitly advances engine timers at `timestampUs` on the engine thread. */
  fun tick(timestampUs: Long) {
    if (destroyRequested.get()) return
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get() || handle == 0L) return@Runnable
          if (!isTestMode) {
            val actionsJson = backend.tick(handle, timestampUs)
            dispatchParsedActions(actionsJson)
          }
        },
    )
  }

  /**
   * Releases all held/toggled buttons in the native engine and dispatches any resulting release
   * actions (such as `MouseUp`) before invoking [onComplete].
   */
  fun releaseAll(onComplete: (() -> Unit)? = null) {
    if (destroyRequested.get()) return
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get()) return@Runnable
          if (handle != 0L) {
            val releasedJson = backend.releaseAll(handle)
            dispatchParsedActions(releasedJson)
          }
          onComplete?.invoke()
        },
    )
  }

  /** Replaces the active engine configuration on the engine thread. */
  fun setConfig(configJson: String) {
    if (destroyRequested.get()) return
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get() || handle == 0L) return@Runnable
          backend.setConfig(handle, configJson)
        },
    )
  }

  /** Reads the active engine configuration on the engine thread. */
  fun getConfig(onResult: (WandJsonResult<WandConfig>) -> Unit) {
    if (destroyRequested.get()) return
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get() || handle == 0L) return@Runnable
          val json = backend.getConfig(handle)
          onResult(WandJson.parseConfig(json))
        },
    )
  }

  /**
   * Enables or disables test mode on the engine thread. When turning test mode ON, first calls
   * `release_all` and dispatches any release actions so held buttons/drags never get stuck.
   */
  fun setTestMode(enabled: Boolean) {
    if (destroyRequested.get()) return
    isTestMode = enabled
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get() || handle == 0L) return@Runnable
          if (enabled) {
            val releasedJson = backend.releaseAll(handle)
            dispatchParsedActions(releasedJson)
          }
          backend.setTestMode(handle, enabled)
        },
    )
  }

  /** Requests gyroscope recentering on the engine thread. */
  fun recalibrate() {
    if (destroyRequested.get()) return
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get() || handle == 0L) return@Runnable
          backend.recalibrate(handle)
        },
    )
  }

  /** Queries the most recently decoded sample on the engine thread. */
  fun lastSample(onResult: (WandSample?) -> Unit) {
    if (destroyRequested.get()) return
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get() || handle == 0L) return@Runnable
          val json = backend.lastSample(handle)
          onResult(WandJson.parseSample(json))
        },
    )
  }

  /**
   * Checks whether [level] (0–100) is below the low-battery threshold via `vitruvian_wand_core` on
   * the engine thread.
   */
  fun batteryLow(level: Int, onResult: (Boolean) -> Unit) {
    if (destroyRequested.get()) return
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get()) return@Runnable
          val isLow = backend.batteryLow(level)
          onResult(isLow)
        },
    )
  }

  /**
   * Loads the persisted [WandConfig] from [configFile] on the engine thread, or on first run /
   * corrupt file queries `vitruvian_wand_core` via [WandNativeBackend.defaultConfig] on the engine
   * thread, writes the default JSON to [configFile], initializes or updates the native engine, and
   * delivers the resulting [WandConfig] to [onResult].
   */
  fun loadConfig(
      configFile: File,
      isTv: Boolean,
      initializeEngine: Boolean = false,
      onResult: (WandConfig) -> Unit = {},
  ) {
    if (destroyRequested.get()) return
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get()) return@Runnable
          val config = readOrInitDefaultConfigOnThread(configFile, isTv)
          applyConfigOnThread(config, isTv, initializeEngine)
          onResult(config)
        },
    )
  }

  /**
   * Resets the configuration to the native platform default from `vitruvian_wand_core` on the
   * engine thread, writes it to [configFile], updates the native engine if created, and delivers
   * the resulting [WandConfig] to [onResult].
   */
  fun resetToDefaults(
      configFile: File,
      isTv: Boolean,
      onResult: (WandConfig) -> Unit = {},
  ) {
    if (destroyRequested.get()) return
    scheduler.post(
        Runnable {
          if (destroyedOnThread || destroyRequested.get()) return@Runnable
          val defaults = loadDefaultConfigOnThread(isTv)
          val json = WandJson.serializeConfig(defaults)
          try {
            configFile.parentFile?.mkdirs()
            configFile.writeText(json)
          } catch (e: Exception) {
            Log.e("VitruvianWand", "Failed to write reset config file ${configFile.path}", e)
            onError("Failed to save settings: ${e.message ?: "I/O error"}")
          }
          if (handle != 0L) {
            backend.setConfig(handle, json)
          }
          onResult(defaults)
        },
    )
  }

  /**
   * Posts the final destroy operation onto the engine thread and shuts down the scheduler. Any
   * subsequent calls on this [NativeEngine] instance are no-ops.
   */
  fun destroy() {
    if (!destroyRequested.compareAndSet(false, true)) return
    scheduler.removeCallbacks(tickRunnable)
    scheduler.post(
        Runnable {
          if (destroyedOnThread) return@Runnable
          destroyedOnThread = true
          connectedOnThread = false
          scheduler.removeCallbacks(tickRunnable)
          val h = handle
          handle = 0L
          if (h != 0L) {
            backend.destroy(h)
          }
          scheduler.shutdown()
        },
    )
  }

  private fun applyConfigOnThread(
      config: WandConfig,
      isTv: Boolean,
      initializeEngine: Boolean,
  ) {
    val json = WandJson.serializeConfig(config)
    if (initializeEngine) {
      val platformCode = if (isTv) WandNative.PLATFORM_ANDROID_TV else WandNative.PLATFORM_ANDROID
      if (handle != 0L) {
        backend.destroy(handle)
        handle = 0L
      }
      handle = backend.create(platformCode, json)
    } else if (handle != 0L) {
      backend.setConfig(handle, json)
    }
  }

  private fun readOrInitDefaultConfigOnThread(configFile: File, isTv: Boolean): WandConfig {
    if (configFile.exists()) {
      val raw =
          try {
            configFile.readText()
          } catch (e: Exception) {
            Log.w("VitruvianWand", "Failed to read config file ${configFile.path}", e)
            ""
          }
      if (raw.isNotBlank()) {
        when (val parsed = WandJson.parseConfig(raw)) {
          is WandJsonResult.Ok -> return parsed.value
          is WandJsonResult.Error -> {
            val err = IllegalArgumentException(parsed.message)
            Log.w(
                "VitruvianWand",
                "Invalid saved config in ${configFile.path}: ${parsed.message}",
                err)
          }
        }
      }
    }
    val defaults = loadDefaultConfigOnThread(isTv)
    try {
      configFile.parentFile?.mkdirs()
      configFile.writeText(WandJson.serializeConfig(defaults))
    } catch (e: Exception) {
      Log.e("VitruvianWand", "Failed to write default config file ${configFile.path}", e)
    }
    return defaults
  }

  /**
   * Queries the platform default [WandConfig] from `vitruvian_wand_core` via
   * [WandNativeBackend.defaultConfig] on the engine thread.
   */
  private fun loadDefaultConfigOnThread(isTv: Boolean): WandConfig {
    val platformCode = if (isTv) WandNative.PLATFORM_ANDROID_TV else WandNative.PLATFORM_ANDROID
    val defaultPlatformName = if (isTv) "android_tv" else "android"
    if (backend.isAvailable) {
      val json =
          try {
            backend.defaultConfig(platformCode)
          } catch (e: Exception) {
            Log.e("VitruvianWand", "Failed to fetch native default config", e)
            ""
          }
      if (json.isNotBlank()) {
        when (val parsed = WandJson.parseConfig(json)) {
          is WandJsonResult.Ok -> return parsed.value
          is WandJsonResult.Error -> {
            val err = IllegalArgumentException(parsed.message)
            Log.e("VitruvianWand", "Failed to parse native default config: ${parsed.message}", err)
            onError(parsed.message)
          }
        }
      }
    }
    return WandConfig(platform = defaultPlatformName)
  }

  private fun dispatchParsedActions(actionsJson: String) {
    when (val parsed = WandJson.parseActions(actionsJson)) {
      is WandJsonResult.Ok -> {
        if (parsed.value.isNotEmpty()) {
          onActions(parsed.value)
        }
      }
      is WandJsonResult.Error -> {
        onError(parsed.message)
      }
    }
  }

  companion object {
    const val TICK_INTERVAL_MS: Long = 20L
  }
}
