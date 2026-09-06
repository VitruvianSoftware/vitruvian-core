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

package dev.vitruvian.remote.state

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.toMutableStateList
import dev.vitruvian.design.LogEntry
import dev.vitruvian.design.SegState
import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.TagTone
import dev.vitruvian.design.TerminalLine
import dev.vitruvian.design.TerminalTone
import dev.vitruvian.remote.hid.HidAction
import dev.vitruvian.remote.hid.HidCodes
import dev.vitruvian.remote.hid.HidSender
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.random.Random
import kotlinx.coroutines.delay

/** How often the live metric series advances. */
private const val TICK_MS = 1500L

/** The window of samples the sparks show - 30 samples at 1.5 s is the "60 s" caption. */
public const val SERIES_LENGTH: Int = 30

private const val LOG_LIMIT = 40
private const val TERMINAL_LIMIT = 60

/** Fixed values the prototype states as constants rather than deriving. */
public const val MEMORY_PERCENT: Int = 41
public const val BATTERY_PERCENT: Int = 87
public const val DISK_PERCENT: Int = 60
public const val TRACK_PERCENT: Int = 66

/** Thermals above this read as warn, on both the widget and the Mac screen. */
public const val THERMAL_WARN_C: Int = 75

/**
 * Everything the app knows.
 *
 * A single observable holder rather than a per-screen ViewModel: the screens of this app are views
 * onto one host, and the dock shows two of them at once, so splitting the state would mean plumbing
 * most of it back together.
 */
@Stable
public class RemoteState(
    private val persistence: Persistence,
    initialConnection: Connection = Connection.Connected,
    private val random: Random = Random.Default,
    /**
     * Sends real key presses to a Mac over Bluetooth HID.
     *
     * Null in previews and tests, and null on a device with no host connected -- every call site
     * below treats "not sent" as ordinary, because until the Mac agent exists the mock IS the
     * product for everything this cannot carry.
     */
    private val hid: HidSender? = null,
) {
  // --- navigation -------------------------------------------------------
  public var screen: Screen by mutableStateOf(Screen.Home)
    private set

  public var dockOpen: Boolean by mutableStateOf(persistence.dockOpen)
    private set

  // --- host -------------------------------------------------------------
  public var connection: Connection by mutableStateOf(initialConnection)
    private set

  public var selectedHost: Int by mutableStateOf(persistence.selectedHost)
    private set

  public var pairCode: String by mutableStateOf("482 917")
    private set

  public var pairTtl: String by mutableStateOf("4:52")
    private set

  public var wakeOnLan: Boolean by mutableStateOf(true)
    private set

  public var confirmDestructive: Boolean by mutableStateOf(true)
    private set

  public var tailscaleFirst: Boolean by mutableStateOf(true)
    private set

  public var refreshInterval: String by mutableStateOf("1 s")
    private set

  // --- appearance -------------------------------------------------------
  public var darkTheme: Boolean by mutableStateOf(persistence.darkTheme)
    private set

  // --- home -------------------------------------------------------------
  public var editMode: Boolean by mutableStateOf(false)
    private set

  public val hiddenWidgets: SnapshotStateList<String> =
      persistence.hiddenWidgets.toMutableStateList()

  // --- apps -------------------------------------------------------------
  public var module: String by mutableStateOf("claude")
    private set

  public var appsView: AppsView by mutableStateOf(AppsView.Dashboards)
    private set

  public val installed: SnapshotStateList<String> = persistence.installed.toMutableStateList()

  // --- macros -----------------------------------------------------------
  public val userMacros: SnapshotStateList<Macro> = persistence.userMacros.toMutableStateList()
  public var macroEditorOpen: Boolean by mutableStateOf(false)
    private set

  public var macroName: String by mutableStateOf("")
    private set

  public var macroCommand: String by mutableStateOf("")
    private set

  public var macroKind: MacroKind by mutableStateOf(MacroKind.Ssh)
    private set

  public var macroConfirm: Boolean by mutableStateOf(false)
    private set

  // --- media ------------------------------------------------------------
  public var playing: Boolean by mutableStateOf(true)
    private set

  public var volume: Int by mutableStateOf(62)
    private set

  public var brightness: Int by mutableStateOf(80)
    private set

  public var mirror: Boolean by mutableStateOf(false)
    private set

  // --- trackpad and keys ------------------------------------------------
  public var pointer: Pair<Float, Float>? by mutableStateOf(null)
    private set

  public var pointerLabel: String by mutableStateOf(POINTER_HINT)
    private set

  public var keyboardOpen: Boolean by mutableStateOf(false)
    private set

  public var typed: String by mutableStateOf("")
    private set

  // --- agent and console ------------------------------------------------
  public var prompt: String by mutableStateOf("")
    private set

  public var command: String by mutableStateOf("")
    private set

  public val terminal: SnapshotStateList<TerminalLine> =
      MockHost.initialTerminal.toMutableStateList()
  public val agentTranscript: SnapshotStateList<TerminalLine> =
      MockHost.initialAgentTranscript.toMutableStateList()
  public var agentPaused: Boolean by mutableStateOf(false)
    private set

  public val logs: SnapshotStateList<LogEntry> =
      mutableStateListOf(
          LogEntry("04:37:02", "ok", "homelab · 3/3 nodes ready, no drift"),
          LogEntry("04:36:51", "warn", "lima · k8s-node-3 stopped (manual)"),
          LogEntry("04:36:44", "info", "claude code · session 2 resumed"),
          LogEntry("04:35:10", "ok", "antigravity · build #412 green"),
          LogEntry("04:31:00", "info", "atlas · connected via tailscale (4 ms)"),
      )

  // --- clipboard and power ---------------------------------------------
  public var clipboard: String by
      mutableStateOf("https://github.com/VitruvianSoftware/vitruvian-core/pull/1551")
    private set

  public var dialog: DialogKind? by mutableStateOf(null)
    private set

  public var confirmText: String by mutableStateOf("")
    private set

  // --- PromQL panel -----------------------------------------------------
  public var promql: String by mutableStateOf("rate(node_cpu_seconds_total{mode!=\"idle\"}[5m])")
    private set

  public var promqlStatus: String by mutableStateOf("panel preview · run query")
    private set

  // --- live series ------------------------------------------------------
  public val cpu: SnapshotStateList<Int> =
      List(SERIES_LENGTH) { 18 + (12 * abs(sin(it / 3.0))).roundToInt() }.toMutableStateList()
  public val net: SnapshotStateList<Int> =
      List(SERIES_LENGTH) { 10 + (40 * abs(sin(it / 2.2))).roundToInt() }.toMutableStateList()
  public var gpu: Int by mutableStateOf(31)
    private set

  public var ane: Int by mutableStateOf(12)
    private set

  public var temperature: Int by mutableStateOf(48)
    private set

  public var fanRpm: Int by mutableStateOf(1200)
    private set

  public var powerDraw: Int by mutableStateOf(18)
    private set

  // --- derived ----------------------------------------------------------

  /** Navigation is locked to Hosts until a Mac is paired. */
  public val effectiveScreen: Screen
    get() = if (connection == Connection.Unpaired) Screen.Hosts else screen

  public val isOffline: Boolean
    get() = connection == Connection.Offline

  public val isUnpaired: Boolean
    get() = connection == Connection.Unpaired

  public val hosts: List<Host>
    get() =
        if (isUnpaired) {
          emptyList()
        } else {
          MockHost.hosts.mapIndexed { index, host ->
            if (index == 0 && isOffline) {
              host.copy(
                  subtitle = MockHost.OFFLINE_SUBTITLE,
                  tag = "unreachable",
                  tagTone = TagTone.Sanguine,
              )
            } else {
              host
            }
          }
        }

  /** The short name the top bar and rail show - `atlas`, not the full row title. */
  public val hostShortName: String
    get() =
        if (isUnpaired) {
          "no host"
        } else {
          hosts.getOrNull(selectedHost)?.name?.substringBefore(" · ") ?: "no host"
        }

  /** The chip's text: the short name, suffixed when unreachable. */
  public val hostChipText: String
    get() =
        when {
          isUnpaired -> "no host"
          isOffline -> "$hostShortName · offline"
          else -> hostShortName
        }

  public val hostTone: StatusTone
    get() =
        when (connection) {
          Connection.Connected -> StatusTone.Ok
          Connection.Offline -> StatusTone.Crit
          Connection.Unpaired -> StatusTone.Neutral
        }

  public val connectionWord: String
    get() =
        when (connection) {
          Connection.Connected -> "connected"
          Connection.Offline -> "unreachable"
          Connection.Unpaired -> "unpaired"
        }

  /** User macros come first, so a just-saved one is where the author left it. */
  public val macros: List<Macro>
    get() = userMacros + MockHost.builtInMacros

  public val widgets: List<Widget>
    get() =
        listOf(
                Widget("cpu", "CPU", "${cpu.last()}%", "M4 Max · 16 cores", cpu.last()),
                Widget(
                    "mem", "Memory pressure", "$MEMORY_PERCENT%", "26.4 / 64 GB", MEMORY_PERCENT),
                Widget(
                    id = "temp",
                    label = "Thermals",
                    value = "$temperature°",
                    sub = "fans $fanRpm rpm",
                    percent = temperature,
                    warn = temperature > THERMAL_WARN_C,
                ),
                Widget(
                    "bat", "Battery", "$BATTERY_PERCENT%", "$powerDraw W · on AC", BATTERY_PERCENT),
            )
            .filterNot { it.id in hiddenWidgets }

  public val runningNow: List<RunningItem>
    get() = MockHost.runningNow

  public val moduleDashboards: Map<String, ModuleDashboard>
    get() = MockHost.dashboards(agentTranscript.toList(), !agentPaused)

  /** Only installed modules that actually ship a dashboard get a chip. */
  public val moduleChips: List<GalleryEntry>
    get() = MockHost.gallery.filter { it.id in installed && it.id in moduleDashboards }

  public val currentModule: ModuleDashboard
    get() = moduleDashboards[module] ?: moduleDashboards.getValue("claude")

  public val memorySegments: List<SegState>
    get() =
        List(MEMORY_SEGMENTS) { index ->
          when {
            index < MEMORY_SEGMENTS_ON -> SegState.On
            index < MEMORY_SEGMENTS_ON + MEMORY_SEGMENTS_WARN -> SegState.Warn
            else -> SegState.Empty
          }
        }

  public val networkDown: String
    get() = "${(net.last() * DOWN_FACTOR).roundToInt()} Mb/s"

  public val networkUp: String
    get() = "${(net.last() * UP_FACTOR).roundToInt()} Mb/s"

  /** The dialog currently open, resolved to its copy. */
  public val dialogSpec: DialogSpec?
    get() = dialog?.let { DialogSpec.of(it, wakeOnLan, confirmDestructive) }

  /** A destructive dialog's action stays disabled until the word is typed exactly. */
  public val dialogBlocked: Boolean
    get() {
      val word = dialogSpec?.word ?: return false
      return confirmText.trim().lowercase(Locale.ROOT) != word
    }

  public val macroSaveBlocked: Boolean
    get() = macroName.isBlank() || macroCommand.isBlank()

  // --- the tick ---------------------------------------------------------

  /**
   * Advances the live series until cancelled.
   *
   * A random walk clamped to plausible bounds, matching the prototype's shape; the point of the
   * motion is that the dashboards read as live, not that the numbers mean anything yet.
   */
  public suspend fun runMetrics() {
    while (true) {
      delay(TICK_MS)
      advance()
    }
  }

  private fun advance() {
    cpu.removeAt(0)
    cpu.add((cpu.last() + walk(CPU_STEP)).coerceIn(CPU_MIN, CPU_MAX))
    net.removeAt(0)
    net.add((net.last() + walk(NET_STEP)).coerceIn(NET_MIN, NET_MAX))
    gpu = (gpu + walk(GPU_STEP)).coerceIn(GPU_MIN, GPU_MAX)
    ane = (ane + walk(ANE_STEP)).coerceIn(0, ANE_MAX)
    temperature = (temperature + walk(TEMP_STEP)).coerceIn(TEMP_MIN, TEMP_MAX)
    fanRpm = FAN_BASE + temperature * FAN_PER_DEGREE
    powerDraw = DRAW_BASE + cpu.last() / DRAW_DIVISOR
  }

  private fun walk(step: Int): Int = ((random.nextDouble() - 0.5) * step).roundToInt()

  // --- actions ----------------------------------------------------------

  public fun go(target: Screen) {
    screen = target
  }

  public fun openModule(id: String) {
    module = id
    appsView = AppsView.Dashboards
    screen = Screen.Apps
  }

  public fun selectModule(id: String) {
    module = id
  }

  public fun showAppsView(view: AppsView) {
    appsView = view
  }

  public fun toggleDock() {
    dockOpen = !dockOpen
    persistence.dockOpen = dockOpen
  }

  public fun toggleEditMode() {
    editMode = !editMode
  }

  public fun hideWidget(id: String) {
    if (id !in hiddenWidgets) {
      hiddenWidgets.add(id)
      persistence.hiddenWidgets = hiddenWidgets.toList()
    }
  }

  public fun restoreWidgets() {
    hiddenWidgets.clear()
    persistence.hiddenWidgets = emptyList()
  }

  public fun selectHost(id: Int) {
    selectedHost = id
    persistence.selectedHost = id
  }

  public fun toggleTheme() {
    darkTheme = !darkTheme
    persistence.darkTheme = darkTheme
  }

  public fun updateTailscaleFirst(value: Boolean) {
    tailscaleFirst = value
  }

  public fun updateWakeOnLan(value: Boolean) {
    wakeOnLan = value
  }

  public fun updateConfirmDestructive(value: Boolean) {
    confirmDestructive = value
  }

  public fun updateRefreshInterval(value: String) {
    refreshInterval = value
  }

  public fun regeneratePairCode() {
    pairCode = "${random.nextInt(100, 1000)} ${random.nextInt(100, 1000)}"
    pairTtl = "5:00"
  }

  public fun toggleModule(id: String) {
    val name = MockHost.gallery.first { it.id == id }.name
    if (id in installed) {
      installed.remove(id)
      log("info", "module · $name removed")
    } else {
      installed.add(id)
      log("ok", "module · $name installed")
    }
    persistence.installed = installed.toList()
  }

  public fun sideload(): Unit = log("info", "module · sideload dialog")

  public fun openInstallGuide(): Unit = log("info", "pairing · install guide opened")

  public fun runMacro(macro: Macro) {
    emit(
        TerminalLine("$", macro.command, TerminalTone.Text),
        TerminalLine(" ", "ok  ${macro.label.lowercase(Locale.ROOT)} — done", TerminalTone.Ok),
    )
    log("ok", "macro · ${macro.label}")
  }

  public fun openMacroEditor() {
    macroEditorOpen = true
  }

  public fun closeMacroEditor() {
    macroEditorOpen = false
  }

  public fun updateMacroName(value: String) {
    macroName = value
  }

  public fun updateMacroCommand(value: String) {
    macroCommand = value
  }

  public fun updateMacroKind(value: MacroKind) {
    macroKind = value
  }

  public fun updateMacroConfirm(value: Boolean) {
    macroConfirm = value
  }

  public fun saveMacro() {
    if (macroSaveBlocked) return
    val saved =
        Macro(
            id = "u${System.currentTimeMillis()}",
            label = macroName.trim(),
            command = macroCommand.trim(),
            kind = macroKind,
            confirm = macroConfirm,
        )
    userMacros.add(0, saved)
    persistence.userMacros = userMacros.toList()
    log("ok", "macro · \"${saved.label}\" saved")
    macroEditorOpen = false
    macroName = ""
    macroCommand = ""
    macroConfirm = false
  }

  // --- controls ---------------------------------------------------------
  //
  // Each of these drives the real Mac when a Bluetooth host is connected, and
  // falls back to the mock when it is not. The local state still moves either
  // way: a keyboard is write-only, so the Mac never tells us its real volume
  // and the slider is our best guess rather than a reading. Worth remembering
  // before anyone treats these numbers as telemetry.

  public fun togglePlay() {
    playing = !playing
    sendHid(HidAction.PlayPause)
  }

  public fun previousTrack() {
    log("info", "media · previous")
    sendHid(HidAction.PreviousTrack)
  }

  public fun nextTrack() {
    log("info", "media · next")
    sendHid(HidAction.NextTrack)
  }

  public fun nudgeVolume(delta: Int) {
    volume = (volume + delta).coerceIn(0, 100)
    sendHid(if (delta >= 0) HidAction.VolumeUp else HidAction.VolumeDown)
  }

  public fun nudgeBrightness(delta: Int) {
    brightness = (brightness + delta).coerceIn(0, 100)
    sendHid(if (delta >= 0) HidAction.BrightnessUp else HidAction.BrightnessDown)
  }

  /** Mission Control, Spaces and friends: the chords the esp32-s3 board already proves work. */
  public fun sendMacChord(action: HidAction) {
    sendHid(action)
    log("info", "desktop · ${desktopLabel(action)}")
  }

  /**
   * A readable name for the Console log.
   *
   * Matched on identity rather than switched on a label the UI passes in, so the log cannot drift
   * from what was actually sent.
   */
  private fun desktopLabel(action: HidAction): String =
      when (action) {
        HidAction.MissionControl -> "mission control"
        HidAction.AppExpose -> "app exposé"
        HidAction.ShowDesktop -> "show desktop"
        HidAction.Launchpad -> "launchpad"
        HidAction.SpaceLeft -> "space left"
        HidAction.SpaceRight -> "space right"
        HidAction.Spotlight -> "spotlight"
        HidAction.ScreenshotFull -> "screenshot"
        HidAction.ScreenshotRegion -> "screenshot · region"
        HidAction.ScreenshotUi -> "screenshot · capture ui"
        HidAction.CmdTab -> "switch app"
        HidAction.CycleWindows -> "cycle windows"
        HidAction.CloseWindow -> "close window"
        HidAction.MinimiseWindow -> "minimise"
        HidAction.HideApp -> "hide app"
        HidAction.Fullscreen -> "fullscreen"
        HidAction.ForceQuit -> "force quit"
        else -> "key"
      }

  private fun sendHid(action: HidAction) {
    val sender = hid ?: return
    if (!sender.send(action)) {
      // Not an error worth shouting about -- no host connected is the normal
      // state today. Logged so the Console screen shows why a press did
      // nothing, rather than leaving the user guessing.
      log("warn", "bluetooth · no host connected")
    }
  }

  public fun toggleMirror() {
    mirror = !mirror
    log("info", "display · mirror ${if (mirror) "on" else "off"}")
  }

  /**
   * Where the finger last was, so the next move can be sent as a DELTA.
   *
   * The trackpad reports absolute positions inside its own surface; a HID mouse speaks relative
   * movement and the Mac owns where its cursor actually is. Null between gestures so the first
   * touch of a new gesture does not send a jump from wherever the last one ended.
   */
  private var lastTouch: Pair<Float, Float>? = null

  public fun movePointer(x: Float, y: Float) {
    val previous = lastTouch
    pointer = x to y
    pointerLabel = "${x.roundToInt()} · ${y.roundToInt()}"
    lastTouch = x to y
    if (previous == null) return // first touch of a gesture: anchor only, no movement

    val dx = ((x - previous.first) * POINTER_GAIN).roundToInt()
    val dy = ((y - previous.second) * POINTER_GAIN).roundToInt()
    if (dx == 0 && dy == 0) return

    // One report carries -127..127 per axis. A fast flick exceeds that, and a
    // single clamped report would move a short way and drop the rest, so long
    // moves are split into several reports instead.
    var remainingX = dx
    var remainingY = dy
    while (remainingX != 0 || remainingY != 0) {
      val stepX = remainingX.coerceIn(-127, 127)
      val stepY = remainingY.coerceIn(-127, 127)
      hid?.sendPointer(stepX, stepY)
      remainingX -= stepX
      remainingY -= stepY
    }
  }

  public fun releasePointer() {
    pointer = null
    pointerLabel = POINTER_HINT
    lastTouch = null
  }

  public fun click() {
    pointerLabel = "click"
    tapButton(HidCodes.MOUSE_BUTTON_LEFT)
  }

  public fun rightClick() {
    pointerLabel = "right click"
    tapButton(HidCodes.MOUSE_BUTTON_RIGHT)
  }

  /** Scrolls the Mac. Positive scrolls up, matching the wheel axis. */
  public fun scroll(amount: Int) {
    hid?.sendPointer(dx = 0, dy = 0, wheel = amount)
  }

  /**
   * Press and release one mouse button in place.
   *
   * The release is mandatory: a button left down on the host makes the next pointer movement a
   * drag, and there is nothing in the UI that would ever lift it again.
   */
  private fun tapButton(button: Int) {
    val sender = hid ?: return
    if (!sender.sendPointer(dx = 0, dy = 0, buttons = button)) {
      log("warn", "bluetooth · no host connected")
      return
    }
    sender.sendPointer(dx = 0, dy = 0, buttons = HidCodes.MOUSE_BUTTON_NONE)
  }

  public fun toggleKeyboard() {
    keyboardOpen = !keyboardOpen
  }

  public fun updateTyped(value: String) {
    typed = value
  }

  public fun sendTyped() {
    if (typed.isNotEmpty()) log("info", "keys · \"$typed\" sent")
    typed = ""
  }

  public fun updatePrompt(value: String) {
    prompt = value
  }

  /** Relays the prompt to Claude Code and lands the user on that transcript. */
  public fun sendPrompt() {
    val text = prompt.trim()
    if (text.isEmpty()) return
    agentTranscript.add(TerminalLine("›", text, TerminalTone.Text))
    agentTranscript.add(TerminalLine(" ", "thinking…", TerminalTone.Dim))
    prompt = ""
    openModule("claude")
    log("info", "claude code · prompt relayed")
  }

  public fun updateCommand(value: String) {
    command = value
  }

  public fun runCommand() {
    val text = command.trim()
    if (text.isEmpty()) return
    emit(
        TerminalLine("$", text, TerminalTone.Text),
        TerminalLine(" ", MockHost.output(text), TerminalTone.Dim),
    )
    command = ""
  }

  public fun toggleAgentPaused() {
    agentPaused = !agentPaused
  }

  public fun pushClipboard(): Unit = log("ok", "clipboard · pushed to atlas")

  public fun pullClipboard() {
    clipboard = "bazel run //tools/gitops:sync -- staging"
    log("ok", "clipboard · pulled from atlas")
  }

  /** Ctrl+Cmd+Q. Distinct from Sleep: this demands a password on return, sleep does not. */
  public fun lock() {
    log("ok", "power · screen locked")
    sendHid(HidAction.LockScreen)
  }

  public fun openDialog(kind: DialogKind) {
    dialog = kind
    confirmText = ""
  }

  public fun updateConfirmText(value: String) {
    confirmText = value
  }

  public fun closeDialog() {
    dialog = null
  }

  public fun confirmDialog() {
    if (dialogBlocked) return
    when (dialog) {
      // The one power action a keyboard can actually perform. Restart and
      // Halt below stay mocked: HID cannot express them, and pretending
      // otherwise would be worse than an honest no-op.
      DialogKind.Sleep -> {
        log("info", "power · atlas sleeping")
        // Ctrl+Shift+Power on the KEYBOARD page. Consumer 0x30 -- what the
        // ESP32 sends over BLE -- is enumerated by macOS and then ignored over
        // Bluetooth Classic. Ctrl+Cmd+Q was the first workaround and does work,
        // but it LOCKS the Mac; this sleeps the display and leaves the session
        // alone, which is what was actually asked for.
        sendHid(HidAction.DisplaySleepChord)
      }
      DialogKind.Restart -> log("warn", "power · restart issued")
      DialogKind.Halt -> {
        agentPaused = true
        log("warn", "claude code · halted")
      }
      null -> Unit
    }
    dialog = null
  }

  public fun updatePromql(value: String) {
    promql = value
  }

  public fun runPromql() {
    promqlStatus = "12 series · 5m step · rendered"
    log("ok", "promql · query ran")
  }

  /** Sends the magic packet; the host answers after a beat. */
  public suspend fun wakeHost() {
    log("info", "power · magic packet sent to atlas")
    delay(WAKE_DELAY_MS)
    connection = Connection.Connected
    log("ok", "atlas · back online (tailscale · 5 ms)")
  }

  public fun retryHost(): Unit = log("warn", "atlas · still unreachable")

  // --- helpers ----------------------------------------------------------

  private fun emit(vararg lines: TerminalLine) {
    terminal.addAll(lines)
    while (terminal.size > TERMINAL_LIMIT) {
      terminal.removeAt(0)
    }
  }

  private fun log(level: String, message: String) {
    logs.add(0, LogEntry(Clock.now(), level, message))
    while (logs.size > LOG_LIMIT) {
      logs.removeAt(logs.lastIndex)
    }
  }

  private companion object {
    const val POINTER_HINT = "drag to move · tap to click"

    /**
     * Trackpad pixels to mouse units.
     *
     * Above 1.0 because the pad is a few hundred px wide and a Mac desktop is thousands: at 1:1 you
     * run out of trackpad long before the cursor crosses the screen. Deliberately a flat multiplier
     * rather than an acceleration curve -- macOS applies its own acceleration to incoming HID
     * deltas, and curving them here would compound with that and feel wrong at both ends.
     */
    const val POINTER_GAIN = 2.0f
    const val WAKE_DELAY_MS = 1800L
    const val MEMORY_SEGMENTS = 16
    const val MEMORY_SEGMENTS_ON = 7
    const val MEMORY_SEGMENTS_WARN = 2
    const val DOWN_FACTOR = 1.2
    const val UP_FACTOR = 0.3
    const val CPU_STEP = 16
    const val CPU_MIN = 6
    const val CPU_MAX = 96
    const val NET_STEP = 30
    const val NET_MIN = 4
    const val NET_MAX = 100
    const val GPU_STEP = 8
    const val GPU_MIN = 4
    const val GPU_MAX = 98
    const val ANE_STEP = 6
    const val ANE_MAX = 90
    const val TEMP_STEP = 2
    const val TEMP_MIN = 38
    const val TEMP_MAX = 92
    const val FAN_BASE = 900
    const val FAN_PER_DEGREE = 14
    const val DRAW_BASE = 12
    const val DRAW_DIVISOR = 3
  }
}

/** The copy and behaviour of one confirmation dialog. */
public data class DialogSpec(
    val kicker: String,
    val destructive: Boolean,
    val title: String,
    val body: String,
    val action: String,
    val word: String?,
) {
  public companion object {
    /**
     * Builds the dialog's copy.
     *
     * The typed confirmation is skipped entirely when the Hosts switch is off, which is why
     * [confirmDestructive] reaches in here rather than being checked at the call site.
     */
    public fun of(kind: DialogKind, wakeOnLan: Boolean, confirmDestructive: Boolean): DialogSpec =
        when (kind) {
          DialogKind.Sleep ->
              DialogSpec(
                  kicker = "Power",
                  destructive = false,
                  title = "Sleep atlas?",
                  body =
                      "Displays off, SSH session kept alive by Tailscale. " +
                          "Wake on LAN is ${if (wakeOnLan) "on" else "off"}.",
                  action = "Sleep",
                  word = null,
              )
          DialogKind.Restart ->
              DialogSpec(
                  kicker = "Destructive · power",
                  destructive = true,
                  title = "Restart atlas?",
                  body =
                      "2 Claude Code sessions and 2 Lima VMs will be interrupted. " +
                          "Homelab control plane loses one node until reboot completes.",
                  action = "Restart",
                  word = "restart".takeIf { confirmDestructive },
              )
          DialogKind.Halt ->
              DialogSpec(
                  kicker = "Destructive · agent",
                  destructive = true,
                  title = "Halt Claude Code?",
                  body =
                      "Kills the running CLI process. Uncommitted edits in " +
                          "worktree/auth stay on disk.",
                  action = "Halt",
                  word = "halt".takeIf { confirmDestructive },
              )
        }
  }
}
