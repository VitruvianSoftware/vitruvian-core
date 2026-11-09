// Copyright (c) 2026 VitruvianSoftware

package dev.vitruvian.wand.service

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import dev.vitruvian.wand.MainActivity
import dev.vitruvian.wand.ble.BleConnectionState
import dev.vitruvian.wand.ble.DaydreamGatt
import dev.vitruvian.wand.ble.DiscoveredController
import dev.vitruvian.wand.core.BrightnessKind
import dev.vitruvian.wand.core.DPadDirection
import dev.vitruvian.wand.core.EngineScheduler
import dev.vitruvian.wand.core.GesturePlanner
import dev.vitruvian.wand.core.GlobalCommand
import dev.vitruvian.wand.core.MediaCommand
import dev.vitruvian.wand.core.NativeEngine
import dev.vitruvian.wand.core.PlannedCommand
import dev.vitruvian.wand.core.PlannerConfig
import dev.vitruvian.wand.core.StrokeCoordinator
import dev.vitruvian.wand.core.StrokeSegment
import dev.vitruvian.wand.core.SystemKind
import dev.vitruvian.wand.core.VolumeCommand
import dev.vitruvian.wand.core.WandAction
import dev.vitruvian.wand.core.WandConfig
import dev.vitruvian.wand.core.WandJson
import dev.vitruvian.wand.core.WandSample
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Snapshot of the live Wand runtime state observed by `MainActivity`. */
data class WandRuntimeSnapshot(
    val serviceRunning: Boolean = false,
    val connectionState: BleConnectionState = BleConnectionState.DISCONNECTED,
    val statusDetail: String? = null,
    val batteryPercent: Int? = null,
    val discoveredControllers: List<DiscoveredController> = emptyList(),
    val lastSample: WandSample? = null,
    val testMode: Boolean = false,
    val saveError: String? = null,
)

/**
 * Process-local state hub and config file store shared between `MainActivity` and
 * [WandAccessibilityService].
 */
object WandRuntimeHub {
  private const val TAG = "Wand"
  private const val CONFIG_FILE_NAME = "wand_config.json"

  private val mainHandler = Handler(Looper.getMainLooper())
  private val _state = MutableStateFlow(WandRuntimeSnapshot())
  val state: StateFlow<WandRuntimeSnapshot> = _state.asStateFlow()

  /**
   * Dedicated [NativeEngine] used when `MainActivity` loads or resets config while
   * [WandAccessibilityService] is not yet running, ensuring `nativeDefaultConfig` still runs
   * exclusively on a [NativeEngine] engine thread.
   */
  private val fallbackEngine: NativeEngine by lazy {
    val thread = HandlerThread("WandEngineHub").apply { start() }
    NativeEngine(
        scheduler = HandlerThreadEngineScheduler(thread),
        clockUs = { SystemClock.elapsedRealtimeNanos() / 1000L },
        onActions = {},
        onError = { message ->
          Log.w(TAG, "Hub NativeEngine error: $message")
          _state.update { it.copy(saveError = message) }
        },
    )
  }

  fun isTvMode(context: Context): Boolean {
    val uiModeManager = context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
    return uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
  }

  fun configFile(context: Context): File = File(context.filesDir, CONFIG_FILE_NAME)

  /**
   * Loads the persisted config or initializes the native default config on [NativeEngine]'s engine
   * thread.
   */
  fun loadConfig(context: Context, onLoaded: (WandConfig) -> Unit = {}) {
    val service = WandAccessibilityService.instance
    if (service != null) {
      service.reloadConfigFromDisk { loaded -> mainHandler.post { onLoaded(loaded) } }
    } else {
      fallbackEngine.loadConfig(
          configFile = configFile(context),
          isTv = isTvMode(context),
          initializeEngine = false,
      ) { loaded ->
        mainHandler.post { onLoaded(loaded) }
      }
    }
  }

  /**
   * Resets config to the native platform default on [NativeEngine]'s engine thread and persists it
   * to disk.
   */
  fun resetToDefaults(context: Context, onReset: (WandConfig) -> Unit = {}) {
    val service = WandAccessibilityService.instance
    if (service != null) {
      service.resetConfigToDefaults { defaults ->
        _state.update { it.copy(saveError = null) }
        mainHandler.post { onReset(defaults) }
      }
    } else {
      fallbackEngine.resetToDefaults(
          configFile = configFile(context),
          isTv = isTvMode(context),
      ) { defaults ->
        _state.update { it.copy(saveError = null) }
        mainHandler.post { onReset(defaults) }
      }
    }
  }

  fun saveConfig(context: Context, config: WandConfig): Boolean {
    val json = WandJson.serializeConfig(config)
    return try {
      configFile(context).writeText(json)
      _state.update { it.copy(saveError = null) }
      WandAccessibilityService.instance?.reloadConfigFromDisk()
      true
    } catch (e: Exception) {
      Log.e(TAG, "Failed to write config file", e)
      _state.update { it.copy(saveError = e.message ?: "Could not write settings to disk.") }
      false
    }
  }

  fun clearSaveError() {
    _state.update { it.copy(saveError = null) }
  }

  fun isAccessibilityServiceEnabled(context: Context): Boolean {
    if (_state.value.serviceRunning) return true
    val enabledServices =
        try {
          Settings.Secure.getString(
              context.contentResolver,
              Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
          ) ?: ""
        } catch (e: Exception) {
          Log.w(TAG, "Failed to read ENABLED_ACCESSIBILITY_SERVICES", e)
          ""
        }
    val expectedFull = "${context.packageName}/${WandAccessibilityService::class.java.name}"
    val expectedShort = "${context.packageName}/.service.WandAccessibilityService"
    return enabledServices.split(':').any { entry ->
      entry.equals(expectedFull, ignoreCase = true) ||
          entry.equals(expectedShort, ignoreCase = true)
    }
  }

  internal fun update(transform: (WandRuntimeSnapshot) -> WandRuntimeSnapshot) {
    _state.update(transform)
  }
}

/** [EngineScheduler] implementation backed by a dedicated Android [HandlerThread]. */
private class HandlerThreadEngineScheduler(
    private val thread: HandlerThread,
    val handler: Handler = Handler(thread.looper),
) : EngineScheduler {
  override fun post(task: Runnable) {
    if (thread.isAlive) {
      handler.post(task)
    }
  }

  override fun postDelayed(delayMs: Long, task: Runnable) {
    if (thread.isAlive) {
      handler.postDelayed(task, delayMs)
    }
  }

  override fun removeCallbacks(task: Runnable) {
    handler.removeCallbacks(task)
  }

  override fun shutdown() {
    thread.quitSafely()
  }
}

/**
 * Accessibility service that owns the Daydream BLE connection, single-thread [NativeEngine],
 * `TYPE_ACCESSIBILITY_OVERLAY` pointer view, gesture dispatcher, and status notifications.
 *
 * Threading invariants:
 * - Every native call (`create`, `feed`, `tick`, `release_all`, `set_config`, `get_config`,
 *   `set_test_mode`, `recalibrate`, `last_sample`, `destroy`) runs exclusively on `engineThread`
 *   via [NativeEngine].
 * - [GesturePlanner], [StrokeCoordinator], `activeDragStroke`, and the cursor overlay view are
 *   confined exclusively to `mainHandler` (the main UI thread).
 */
class WandAccessibilityService : AccessibilityService() {

  private val mainHandler = Handler(Looper.getMainLooper())
  private var windowManager: WindowManager? = null
  private var audioManager: AudioManager? = null
  private var notificationManager: NotificationManager? = null

  private var cursorView: CursorOverlayView? = null
  private var cursorParams: WindowManager.LayoutParams? = null
  private var overlayAdded: Boolean = false

  private lateinit var engineScheduler: HandlerThreadEngineScheduler
  private lateinit var nativeEngine: NativeEngine
  private lateinit var planner: GesturePlanner
  private val strokeCoordinator = StrokeCoordinator()

  private var gattClient: DaydreamGatt? = null
  private var activeConfig: WandConfig = WandConfig()
  private var activeDragStroke: GestureDescription.StrokeDescription? = null

  private val lowBatteryNotifiedThisConnection = AtomicBoolean(false)
  private val cleanedUp = AtomicBoolean(false)

  @Volatile private var testModeActive: Boolean = false

  private val serviceReceiver =
      object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
          when (intent?.action) {
            ACTION_DISCONNECT -> disconnectController()
            ACTION_RECALIBRATE -> recalibrateController()
            ACTION_CONNECT -> connectController()
            Intent.ACTION_SCREEN_OFF -> {
              releaseAllAndEndStroke()
            }
          }
        }
      }

  override fun onCreate() {
    super.onCreate()
    instance = this
    windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
    audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
    ensureNotificationChannel()

    val isTv = WandRuntimeHub.isTvMode(this)
    val metrics = resources.displayMetrics
    planner =
        GesturePlanner(
            config =
                PlannerConfig(
                    screenWidth = metrics.widthPixels.coerceAtLeast(1),
                    screenHeight = metrics.heightPixels.coerceAtLeast(1),
                    density = metrics.density.coerceAtLeast(1f),
                    isTv = isTv,
                ),
        )

    val engineThread = HandlerThread("WandEngine").apply { start() }
    engineScheduler = HandlerThreadEngineScheduler(engineThread)
    nativeEngine =
        NativeEngine(
            scheduler = engineScheduler,
            clockUs = { SystemClock.elapsedRealtimeNanos() / 1000L },
            onActions = { actions -> mainHandler.post { handleActionsOnMainThread(actions) } },
            onSample = { sample -> WandRuntimeHub.update { it.copy(lastSample = sample) } },
            onError = { message -> Log.w(TAG, "NativeEngine error: $message") },
        )

    val filter =
        IntentFilter().apply {
          addAction(ACTION_DISCONNECT)
          addAction(ACTION_RECALIBRATE)
          addAction(ACTION_CONNECT)
          addAction(Intent.ACTION_SCREEN_OFF)
        }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      registerReceiver(serviceReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      registerReceiver(serviceReceiver, filter)
    }

    gattClient =
        DaydreamGatt(
            context = this,
            engineHandler = engineScheduler.handler,
            onStateChanged = { state, detail ->
              if (state == BleConnectionState.CONNECTED) {
                lowBatteryNotifiedThisConnection.set(false)
                nativeEngine.setConnected(true)
              } else if (state == BleConnectionState.DISCONNECTED) {
                nativeEngine.setConnected(false)
                mainHandler.post { forceEndInFlightStrokeOnMainThread() }
              }
              WandRuntimeHub.update {
                it.copy(
                    connectionState = state,
                    statusDetail = detail,
                    batteryPercent =
                        if (state == BleConnectionState.DISCONNECTED) null else it.batteryPercent,
                )
              }
              mainHandler.post {
                updateOverlayVisibility()
                postStatusNotification()
              }
            },
            onBatteryLevel = { level ->
              WandRuntimeHub.update { it.copy(batteryPercent = level) }
              nativeEngine.batteryLow(level) { isLow ->
                if (isLow && lowBatteryNotifiedThisConnection.compareAndSet(false, true)) {
                  mainHandler.post { postLowBatteryNotification(level) }
                }
                mainHandler.post { postStatusNotification() }
              }
            },
            onDiscoveredControllers = { list ->
              WandRuntimeHub.update { it.copy(discoveredControllers = list) }
            },
            onPacket = { packet, timestampUs -> nativeEngine.feed(packet, timestampUs) },
        )

    nativeEngine.loadConfig(
        configFile = WandRuntimeHub.configFile(this),
        isTv = isTv,
        initializeEngine = true,
    ) { loaded ->
      gattClient?.setAutoReconnect(loaded.settings.autoReconnect)
      mainHandler.post {
        activeConfig = loaded
        updateOverlaySizeAndVisibility()
      }
    }
  }

  override fun onServiceConnected() {
    super.onServiceConnected()
    instance = this
    WandRuntimeHub.update { it.copy(serviceRunning = true) }
    mainHandler.post {
      setupCursorOverlay()
      postStatusNotification()
    }
    if (activeConfig.settings.autoReconnect) {
      connectController()
    }
  }

  override fun onConfigurationChanged(newConfig: Configuration) {
    super.onConfigurationChanged(newConfig)
    mainHandler.post {
      val metrics = resources.displayMetrics
      planner.updateConfig(
          planner.config.copy(
              screenWidth = metrics.widthPixels.coerceAtLeast(1),
              screenHeight = metrics.heightPixels.coerceAtLeast(1),
              density = metrics.density.coerceAtLeast(1f),
          ),
      )
      updateOverlaySizeAndVisibility()
    }
  }

  override fun onAccessibilityEvent(event: AccessibilityEvent?) {
    // Window content is queried on demand for TV focus searches and Copy/Paste actions.
  }

  override fun onInterrupt() {
    releaseAllAndEndStroke()
  }

  override fun onUnbind(intent: Intent?): Boolean {
    releaseAllAndEndStroke()
    performServiceTeardown()
    return super.onUnbind(intent)
  }

  override fun onDestroy() {
    releaseAllAndEndStroke()
    performServiceTeardown()
    super.onDestroy()
  }

  private fun performServiceTeardown() {
    if (!cleanedUp.compareAndSet(false, true)) return
    instance = null
    WandRuntimeHub.update {
      it.copy(
          serviceRunning = false,
          connectionState = BleConnectionState.DISCONNECTED,
          batteryPercent = null,
      )
    }
    try {
      unregisterReceiver(serviceReceiver)
    } catch (e: Exception) {
      Log.w(TAG, "Failed to unregister serviceReceiver", e)
    }
    mainHandler.post {
      forceEndInFlightStrokeOnMainThread()
      removeCursorOverlay()
    }
    // Stop BLE first on the shared engine thread, then post NativeEngine.destroy as the final
    // message.
    gattClient?.stopBeforeDestroy()
    gattClient = null
    nativeEngine.destroy()
    notificationManager?.cancel(NOTIFICATION_ID_STATUS)
  }

  fun connectController() {
    gattClient?.connect()
  }

  fun connectToAddress(address: String) {
    gattClient?.connectToAddress(address)
  }

  fun disconnectController() {
    releaseAllAndEndStroke()
    gattClient?.disconnect()
  }

  fun startPairingScan() {
    gattClient?.startPairingScan()
  }

  fun pairAndConnect(address: String) {
    gattClient?.pairAndConnect(address)
  }

  fun recalibrateController() {
    nativeEngine.recalibrate()
    mainHandler.post {
      val metrics = resources.displayMetrics
      planner.setCursor(metrics.widthPixels / 2f, metrics.heightPixels / 2f)
      moveOverlayTo(planner.cursorX, planner.cursorY)
    }
  }

  fun setTestMode(enabled: Boolean) {
    testModeActive = enabled
    WandRuntimeHub.update { it.copy(testMode = enabled) }
    if (enabled) {
      releaseAllAndEndStroke()
    }
    nativeEngine.setTestMode(enabled)
  }

  fun reloadConfigFromDisk(onLoaded: ((WandConfig) -> Unit)? = null) {
    val isTv = WandRuntimeHub.isTvMode(this)
    nativeEngine.loadConfig(
        configFile = WandRuntimeHub.configFile(this),
        isTv = isTv,
        initializeEngine = false,
    ) { loaded ->
      gattClient?.setAutoReconnect(loaded.settings.autoReconnect)
      mainHandler.post {
        activeConfig = loaded
        val metrics = resources.displayMetrics
        planner.updateConfig(
            PlannerConfig(
                screenWidth = metrics.widthPixels.coerceAtLeast(1),
                screenHeight = metrics.heightPixels.coerceAtLeast(1),
                density = metrics.density.coerceAtLeast(1f),
                isTv = isTv,
            ),
        )
        updateOverlaySizeAndVisibility()
        onLoaded?.invoke(loaded)
      }
    }
  }

  fun resetConfigToDefaults(onReset: ((WandConfig) -> Unit)? = null) {
    val isTv = WandRuntimeHub.isTvMode(this)
    nativeEngine.resetToDefaults(
        configFile = WandRuntimeHub.configFile(this),
        isTv = isTv,
    ) { defaults ->
      gattClient?.setAutoReconnect(defaults.settings.autoReconnect)
      mainHandler.post {
        activeConfig = defaults
        updateOverlaySizeAndVisibility()
        onReset?.invoke(defaults)
      }
    }
  }

  /**
   * Calls `nativeReleaseAll` on the engine thread (which posts any emitted `MouseUp` actions to
   * `mainHandler`) and ensures any in-flight gesture stroke on the main thread is terminated with a
   * final non-continuing stroke at the cursor.
   */
  private fun releaseAllAndEndStroke() {
    if (::nativeEngine.isInitialized) {
      nativeEngine.releaseAll { mainHandler.post { forceEndInFlightStrokeOnMainThread() } }
    }
    mainHandler.post { forceEndInFlightStrokeOnMainThread() }
  }

  private fun forceEndInFlightStrokeOnMainThread() {
    if (!::planner.isInitialized) return
    planner.cancelDrag()
    val endSeg =
        strokeCoordinator.forceEndAtCursor(
            cursorX = planner.cursorX,
            cursorY = planner.cursorY,
            nowMs = SystemClock.uptimeMillis(),
        )
    if (endSeg != null) {
      dispatchStrokeSegment(endSeg)
    } else {
      activeDragStroke = null
    }
  }

  private fun handleActionsOnMainThread(actions: List<WandAction>) {
    if (testModeActive || actions.isEmpty()) return
    val commands = planner.planAll(actions)
    if (commands.isNotEmpty()) {
      executePlannedCommands(commands)
    }
  }

  private fun executePlannedCommands(commands: List<PlannedCommand>) {
    val nowMs = SystemClock.uptimeMillis()
    for (cmd in commands) {
      when (cmd) {
        is PlannedCommand.MoveCursor -> moveOverlayTo(cmd.x, cmd.y)
        is PlannedCommand.Tap -> dispatchTapGesture(cmd.x, cmd.y, durationMs = 45L)
        is PlannedCommand.SecondaryTap -> dispatchTapGesture(cmd.x, cmd.y, durationMs = 500L)
        is PlannedCommand.StrokeStart -> {
          val seg = strokeCoordinator.onStrokeStart(cmd.x, cmd.y, nowMs)
          dispatchStrokeSegment(seg)
        }
        is PlannedCommand.StrokeContinue -> {
          val seg = strokeCoordinator.onStrokeContinue(cmd.toX, cmd.toY, nowMs)
          if (seg != null) {
            dispatchStrokeSegment(seg)
          }
        }
        is PlannedCommand.StrokeEnd -> {
          val seg = strokeCoordinator.onStrokeEnd(cmd.toX, cmd.toY, nowMs)
          if (seg != null) {
            dispatchStrokeSegment(seg)
          }
        }
        is PlannedCommand.Swipe ->
            dispatchSwipeGesture(cmd.startX, cmd.startY, cmd.endX, cmd.endY, cmd.durationMs)
        is PlannedCommand.Global -> executeGlobalCommand(cmd.action)
        is PlannedCommand.Media -> executeMediaCommand(cmd.command)
        is PlannedCommand.Volume -> executeVolumeCommand(cmd.command)
        is PlannedCommand.FocusMove -> executeFocusMove(cmd.direction)
        is PlannedCommand.LaunchApp -> executeLaunchApp(cmd.packageName)
        PlannedCommand.ScreenOff -> {
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
          }
        }
        PlannedCommand.Assistant -> executeVoiceIntent(preferAssist = true)
        PlannedCommand.VoiceTyping -> executeVoiceIntent(preferAssist = false)
        is PlannedCommand.Brightness -> executeBrightnessCommand(cmd.kind)
        is PlannedCommand.System -> executeSystemCommand(cmd.kind)
        is PlannedCommand.Key,
        PlannedCommand.ToggleGyro,
        PlannedCommand.RadialMenu, -> Unit
      }
    }
  }

  private fun dispatchTapGesture(x: Float, y: Float, durationMs: Long) {
    val path = Path().apply { moveTo(x, y) }
    val stroke = GestureDescription.StrokeDescription(path, 0L, durationMs)
    val gesture = GestureDescription.Builder().addStroke(stroke).build()
    dispatchGesture(gesture, null, null)
  }

  private fun dispatchStrokeSegment(segment: StrokeSegment) {
    val path =
        Path().apply {
          moveTo(segment.fromX, segment.fromY)
          if (segment.toX != segment.fromX || segment.toY != segment.fromY) {
            lineTo(segment.toX, segment.toY)
          }
        }
    val stroke =
        try {
          if (segment.isInitial) {
            GestureDescription.StrokeDescription(
                path,
                0L,
                segment.durationMs,
                segment.willContinue,
            )
          } else {
            val current = activeDragStroke ?: return
            current.continueStroke(
                path,
                0L,
                segment.durationMs,
                segment.willContinue,
            )
          }
        } catch (e: Exception) {
          Log.w(TAG, "Stroke segment construction failed", e)
          activeDragStroke = null
          strokeCoordinator.onCancelled()
          planner.cancelDrag()
          return
        }

    activeDragStroke = if (segment.willContinue) stroke else null
    val gesture = GestureDescription.Builder().addStroke(stroke).build()
    val dispatched =
        dispatchGesture(
            gesture,
            object : GestureResultCallback() {
              override fun onCompleted(gestureDescription: GestureDescription?) {
                mainHandler.post {
                  val next = strokeCoordinator.onCompleted(SystemClock.uptimeMillis())
                  if (next != null) {
                    dispatchStrokeSegment(next)
                  }
                }
              }

              override fun onCancelled(gestureDescription: GestureDescription?) {
                mainHandler.post {
                  activeDragStroke = null
                  strokeCoordinator.onCancelled()
                  planner.cancelDrag()
                }
              }
            },
            mainHandler,
        )
    if (!dispatched) {
      activeDragStroke = null
      strokeCoordinator.onCancelled()
      planner.cancelDrag()
    }
  }

  private fun dispatchSwipeGesture(
      startX: Float,
      startY: Float,
      endX: Float,
      endY: Float,
      durationMs: Long,
  ) {
    val path =
        Path().apply {
          moveTo(startX, startY)
          lineTo(endX, endY)
        }
    val stroke = GestureDescription.StrokeDescription(path, 0L, durationMs.coerceAtLeast(50L))
    val gesture = GestureDescription.Builder().addStroke(stroke).build()
    dispatchGesture(gesture, null, null)
  }

  private fun executeGlobalCommand(action: GlobalCommand) {
    val globalId =
        when (action) {
          GlobalCommand.BACK -> GLOBAL_ACTION_BACK
          GlobalCommand.HOME -> GLOBAL_ACTION_HOME
          GlobalCommand.RECENTS -> GLOBAL_ACTION_RECENTS
          GlobalCommand.NOTIFICATIONS -> GLOBAL_ACTION_NOTIFICATIONS
          GlobalCommand.QUICK_SETTINGS -> GLOBAL_ACTION_QUICK_SETTINGS
        }
    performGlobalAction(globalId)
  }

  private fun executeMediaCommand(command: MediaCommand) {
    val keyCode =
        when (command) {
          MediaCommand.PLAY_PAUSE -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
          MediaCommand.NEXT -> KeyEvent.KEYCODE_MEDIA_NEXT
          MediaCommand.PREVIOUS -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
        }
    val now = SystemClock.uptimeMillis()
    val down = KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0)
    val up = KeyEvent(now, now, KeyEvent.ACTION_UP, keyCode, 0)
    audioManager?.dispatchMediaKeyEvent(down)
    audioManager?.dispatchMediaKeyEvent(up)
  }

  private fun executeVolumeCommand(command: VolumeCommand) {
    val adjust =
        when (command) {
          VolumeCommand.UP -> AudioManager.ADJUST_RAISE
          VolumeCommand.DOWN -> AudioManager.ADJUST_LOWER
          VolumeCommand.MUTE -> AudioManager.ADJUST_TOGGLE_MUTE
        }
    audioManager?.adjustStreamVolume(
        AudioManager.STREAM_MUSIC,
        adjust,
        AudioManager.FLAG_SHOW_UI,
    )
  }

  private fun executeBrightnessCommand(kind: BrightnessKind) {
    if (Settings.System.canWrite(this)) {
      try {
        val current =
            Settings.System.getInt(
                contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
                128,
            )
        val delta =
            when (kind) {
              BrightnessKind.UP -> BRIGHTNESS_STEP
              BrightnessKind.DOWN -> -BRIGHTNESS_STEP
            }
        val next = (current + delta).coerceIn(0, 255)
        Settings.System.putInt(
            contentResolver,
            Settings.System.SCREEN_BRIGHTNESS_MODE,
            Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL,
        )
        Settings.System.putInt(
            contentResolver,
            Settings.System.SCREEN_BRIGHTNESS,
            next,
        )
      } catch (e: Exception) {
        Log.w(TAG, "Failed to update screen brightness", e)
      }
    } else {
      postWriteSettingsNotificationAndToast()
    }
  }

  private fun executeSystemCommand(kind: SystemKind) {
    when (kind) {
      SystemKind.COPY -> {
        findFocusedInputNode()?.performAction(AccessibilityNodeInfo.ACTION_COPY)
      }
      SystemKind.PASTE -> {
        findFocusedInputNode()?.performAction(AccessibilityNodeInfo.ACTION_PASTE)
      }
      SystemKind.CUT -> {
        findFocusedInputNode()?.performAction(AccessibilityNodeInfo.ACTION_CUT)
      }
      SystemKind.APP_SWITCHER,
      SystemKind.MISSION_CONTROL, -> {
        performGlobalAction(GLOBAL_ACTION_RECENTS)
      }
      SystemKind.SHOW_DESKTOP -> {
        performGlobalAction(GLOBAL_ACTION_HOME)
      }
      SystemKind.UNDO -> Unit
    }
  }

  private fun findFocusedInputNode(): AccessibilityNodeInfo? {
    val root = rootInActiveWindow ?: return null
    return root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        ?: root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
  }

  private fun executeFocusMove(direction: DPadDirection) {
    val root = rootInActiveWindow ?: return
    val currentFocus =
        root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
            ?: root

    if (direction == DPadDirection.CENTER) {
      val clicked = currentFocus.performAction(AccessibilityNodeInfo.ACTION_CLICK)
      if (!clicked) {
        dispatchTapGesture(planner.cursorX, planner.cursorY, durationMs = 45L)
      }
      return
    }

    val searchDir =
        when (direction) {
          DPadDirection.UP -> View.FOCUS_UP
          DPadDirection.DOWN -> View.FOCUS_DOWN
          DPadDirection.LEFT -> View.FOCUS_LEFT
          DPadDirection.RIGHT -> View.FOCUS_RIGHT
          DPadDirection.CENTER -> View.FOCUS_FORWARD
        }
    val nextNode = currentFocus.focusSearch(searchDir)
    if (nextNode != null) {
      if (!nextNode.performAction(AccessibilityNodeInfo.ACTION_FOCUS)) {
        nextNode.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS)
      }
    }
  }

  private fun executeLaunchApp(packageName: String) {
    val pm = packageManager
    val intent =
        pm.getLeanbackLaunchIntentForPackage(packageName)
            ?: pm.getLaunchIntentForPackage(packageName)
            ?: return
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
      startActivity(intent)
    } catch (e: Exception) {
      Log.w(TAG, "Failed to launch $packageName", e)
    }
  }

  private fun executeVoiceIntent(preferAssist: Boolean) {
    val primaryAction = if (preferAssist) Intent.ACTION_ASSIST else Intent.ACTION_VOICE_COMMAND
    val fallbackAction = if (preferAssist) Intent.ACTION_VOICE_COMMAND else Intent.ACTION_ASSIST
    for (act in listOf(primaryAction, fallbackAction)) {
      try {
        val intent = Intent(act).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        startActivity(intent)
        return
      } catch (e: Exception) {
        Log.w(TAG, "Failed to start voice intent $act", e)
      }
    }
  }

  private fun setupCursorOverlay() {
    if (overlayAdded) return
    val wm = windowManager ?: return
    val sizePx = cursorSizePx()
    val view = CursorOverlayView(this)
    val params =
        WindowManager.LayoutParams(
                sizePx,
                sizePx,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT,
            )
            .apply {
              gravity = Gravity.TOP or Gravity.START
              x = (planner.cursorX - sizePx / 2f).toInt()
              y = (planner.cursorY - sizePx / 2f).toInt()
            }
    try {
      wm.addView(view, params)
      cursorView = view
      cursorParams = params
      overlayAdded = true
      updateOverlayVisibility()
    } catch (e: Exception) {
      Log.e(TAG, "Failed to add accessibility cursor overlay", e)
    }
  }

  private fun removeCursorOverlay() {
    val wm = windowManager
    val view = cursorView
    if (overlayAdded && wm != null && view != null) {
      try {
        wm.removeView(view)
      } catch (e: Exception) {
        Log.w(TAG, "Failed to remove accessibility cursor overlay", e)
      }
    }
    cursorView = null
    cursorParams = null
    overlayAdded = false
  }

  private fun cursorSizePx(): Int {
    val dp = activeConfig.settings.overlayCursorSize.coerceIn(12f, 64f)
    return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(16)
  }

  private fun updateOverlaySizeAndVisibility() {
    val wm = windowManager ?: return
    val view = cursorView ?: return
    val params = cursorParams ?: return
    val sizePx = cursorSizePx()
    params.width = sizePx
    params.height = sizePx
    params.x = (planner.cursorX - sizePx / 2f).toInt()
    params.y = (planner.cursorY - sizePx / 2f).toInt()
    updateOverlayVisibility()
    if (overlayAdded) {
      try {
        wm.updateViewLayout(view, params)
        view.invalidate()
      } catch (e: Exception) {
        Log.w(TAG, "Failed to update cursor overlay layout", e)
      }
    }
  }

  private fun updateOverlayVisibility() {
    val view = cursorView ?: return
    val connected = WandRuntimeHub.state.value.connectionState == BleConnectionState.CONNECTED
    val shouldShow = connected && activeConfig.settings.overlayCursor
    view.visibility = if (shouldShow) View.VISIBLE else View.GONE
  }

  private fun moveOverlayTo(x: Float, y: Float) {
    val wm = windowManager ?: return
    val view = cursorView ?: return
    val params = cursorParams ?: return
    if (view.visibility != View.VISIBLE) return
    val half = params.width / 2f
    params.x = (x - half).toInt()
    params.y = (y - half).toInt()
    try {
      wm.updateViewLayout(view, params)
    } catch (e: Exception) {
      Log.w(TAG, "Failed to move cursor overlay", e)
    }
  }

  private fun ensureNotificationChannel() {
    val nm = notificationManager ?: return
    val channel =
        NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Wand Controller",
                NotificationManager.IMPORTANCE_LOW,
            )
            .apply { description = "Daydream controller connection status and quick actions" }
    nm.createNotificationChannel(channel)
  }

  private fun postStatusNotification() {
    val nm = notificationManager ?: return
    val snapshot = WandRuntimeHub.state.value
    val statusText =
        when (snapshot.connectionState) {
          BleConnectionState.CONNECTED -> {
            val bat = snapshot.batteryPercent?.let { " · Battery $it%" } ?: ""
            "Connected to Daydream controller$bat"
          }
          BleConnectionState.SCANNING -> "Scanning for Daydream controller…"
          BleConnectionState.CONNECTING -> "Connecting to Daydream controller…"
          BleConnectionState.PAIRING -> "Pairing with Daydream controller…"
          BleConnectionState.DISCONNECTED -> "Disconnected"
        }

    val openIntent =
        PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
              flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    val disconnectPending =
        PendingIntent.getBroadcast(
            this,
            1,
            Intent(ACTION_DISCONNECT).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    val recalibratePending =
        PendingIntent.getBroadcast(
            this,
            2,
            Intent(ACTION_RECALIBRATE).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    val notification =
        Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle("Wand Air Mouse")
            .setContentText(statusText)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(
                        null,
                        "Disconnect",
                        disconnectPending,
                    )
                    .build(),
            )
            .addAction(
                Notification.Action.Builder(
                        null,
                        "Recalibrate",
                        recalibratePending,
                    )
                    .build(),
            )
            .build()

    try {
      nm.notify(NOTIFICATION_ID_STATUS, notification)
    } catch (e: SecurityException) {
      Log.w(TAG, "Missing permission to post status notification", e)
    }
  }

  private fun postLowBatteryNotification(level: Int) {
    val nm = notificationManager ?: return
    val notification =
        Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle("Daydream Controller Battery Low")
            .setContentText("Controller battery is at $level% (< 15%). Please recharge soon.")
            .setAutoCancel(true)
            .build()
    try {
      nm.notify(NOTIFICATION_ID_LOW_BATTERY, notification)
    } catch (e: SecurityException) {
      Log.w(TAG, "Missing permission to post low battery notification", e)
    }
  }

  private fun postWriteSettingsNotificationAndToast() {
    val manageIntent =
        Intent(
                Settings.ACTION_MANAGE_WRITE_SETTINGS,
                Uri.parse("package:$packageName"),
            )
            .apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
    Toast.makeText(
            this,
            "Grant Modify System Settings permission to adjust screen brightness.",
            Toast.LENGTH_LONG,
        )
        .show()

    val nm = notificationManager ?: return
    val pending =
        PendingIntent.getActivity(
            this,
            3,
            manageIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    val notification =
        Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Brightness Permission Required")
            .setContentText("Tap to grant Modify System Settings so Wand can adjust brightness.")
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
    try {
      nm.notify(NOTIFICATION_ID_WRITE_SETTINGS, notification)
    } catch (e: SecurityException) {
      Log.w(TAG, "Missing permission to post write-settings notification", e)
    }
  }

  /** Minimal accessibility cursor view rendered inside `TYPE_ACCESSIBILITY_OVERLAY`. */
  private class CursorOverlayView(context: Context) : View(context) {
    private val fillPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
          style = Paint.Style.FILL
          color = 0xCCD97706.toInt()
        }
    private val strokePaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
          style = Paint.Style.STROKE
          strokeWidth = 2.5f * resources.displayMetrics.density
          color = 0xFFF5F3EE.toInt()
        }
    private val shadowPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
          style = Paint.Style.STROKE
          strokeWidth = 4.0f * resources.displayMetrics.density
          color = 0x99181715.toInt()
        }

    override fun onDraw(canvas: Canvas) {
      super.onDraw(canvas)
      val cx = width / 2f
      val cy = height / 2f
      val radius =
          (width.coerceAtMost(height) / 2f - strokePaint.strokeWidth * 1.5f).coerceAtLeast(4f)
      canvas.drawCircle(cx, cy, radius, shadowPaint)
      canvas.drawCircle(cx, cy, radius, fillPaint)
      canvas.drawCircle(cx, cy, radius, strokePaint)
    }
  }

  companion object {
    private const val TAG = "Wand"
    private const val BRIGHTNESS_STEP = 25

    const val NOTIFICATION_CHANNEL_ID = "wand"
    const val NOTIFICATION_ID_STATUS = 1001
    const val NOTIFICATION_ID_LOW_BATTERY = 1002
    const val NOTIFICATION_ID_WRITE_SETTINGS = 1003

    const val ACTION_DISCONNECT = "dev.vitruvian.wand.action.DISCONNECT"
    const val ACTION_RECALIBRATE = "dev.vitruvian.wand.action.RECALIBRATE"
    const val ACTION_CONNECT = "dev.vitruvian.wand.action.CONNECT"

    @Volatile
    var instance: WandAccessibilityService? = null
      private set
  }
}
