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

import dev.vitruvian.design.TerminalLine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Walks derived Home, Mac, Remote, and Modules state for offline saved Macs against the actual
 * runtime fields on [MockHost], ensuring demo values never leak when a real Mac cannot answer.
 */
public class MockHostWalkTest {

  private class InMemoryKeyValueStore : KeyValueStore {
    private val data = linkedMapOf<String, Any?>()

    override fun contains(key: String): Boolean = data.containsKey(key)

    override fun getString(key: String, defValue: String?): String? =
        (data[key] as? String) ?: defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String, defValues: Set<String>?): Set<String>? =
        (data[key] as? Set<String>)?.toSet() ?: defValues

    override fun getInt(key: String, defValue: Int): Int = (data[key] as? Int) ?: defValue

    override fun getLong(key: String, defValue: Long): Long = (data[key] as? Long) ?: defValue

    override fun getBoolean(key: String, defValue: Boolean): Boolean =
        (data[key] as? Boolean) ?: defValue

    override fun edit(): KeyValueStore.Editor = InMemoryEditor()

    private inner class InMemoryEditor : KeyValueStore.Editor {
      private val pending = linkedMapOf<String, Any?>()
      private val removals = linkedSetOf<String>()

      override fun putString(key: String, value: String?): KeyValueStore.Editor = apply {
        if (value == null) removals.add(key) else pending[key] = value
      }

      override fun putStringSet(key: String, values: Set<String>?): KeyValueStore.Editor = apply {
        if (values == null) removals.add(key) else pending[key] = values.toSet()
      }

      override fun putInt(key: String, value: Int): KeyValueStore.Editor = apply {
        pending[key] = value
      }

      override fun putLong(key: String, value: Long): KeyValueStore.Editor = apply {
        pending[key] = value
      }

      override fun putBoolean(key: String, value: Boolean): KeyValueStore.Editor = apply {
        pending[key] = value
      }

      override fun remove(key: String): KeyValueStore.Editor = apply { removals.add(key) }

      override fun apply() {
        removals.forEach { data.remove(it) }
        pending.forEach { (k, v) -> data[k] = v }
      }
    }
  }

  private fun newSavedMacState(): RemoteState {
    val prefs = InMemoryKeyValueStore()
    val savedHost =
        AgentHostEntry(
            id = "host-studio-1",
            alias = "studio-mbp",
            url = "http://100.64.9.50:7411",
            token = "tok-real-1",
            mac = "10:20:30:40:50:60",
        )
    prefs
        .edit()
        .putString("hosts", HostCodec.encode(listOf(savedHost)))
        .putString("selectedHostId", savedHost.id)
        .apply()
    val persistence = Persistence(prefs)
    return RemoteState(
        persistence = persistence,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
    )
  }

  private data class DerivedScreenWalk(
      val screen: String,
      val values: Map<String, Any?>,
  )

  private fun deriveAllScreens(state: RemoteState): List<DerivedScreenWalk> {
    val home =
        DerivedScreenWalk(
            screen = "Home",
            values =
                linkedMapOf(
                    "hostShortName" to state.hostShortName,
                    "hostSubline" to state.hostSubline,
                    "hostChipText" to state.hostChipText,
                    "connectionWord" to state.connectionWord,
                    "metricsTagLabel" to state.metricsTagLabel,
                    "hostRows" to state.hostRows,
                    "widgets" to state.widgets,
                    "runningNow" to state.runningNow,
                    "runningNowEmpty" to state.runningNowEmpty,
                    "macros" to state.macros,
                    "logs" to state.logs.toList(),
                ),
        )
    val mac =
        DerivedScreenWalk(
            screen = "Mac",
            values =
                linkedMapOf(
                    "computeSubline" to state.computeSubline,
                    "cpuBreakdown" to state.cpuBreakdown,
                    "gpuPlate" to state.gpuPlate,
                    "anePlate" to state.anePlate,
                    "memoryPlate" to state.memoryPlate,
                    "memoryBreakdown" to state.memoryBreakdown,
                    "thermalPlate" to state.thermalPlate,
                    "batteryPlate" to state.batteryPlate,
                    "diskPlate" to state.diskPlate,
                    "networkSubline" to state.networkSubline,
                    "processes" to state.processes,
                    "processesNotice" to state.processesNotice,
                    "vms" to state.vms,
                    "vmsNotice" to state.vmsNotice,
                    "containers" to state.containers,
                    "containersNotice" to state.containersNotice,
                    "containersLabel" to state.containersLabel,
                    "nodes" to state.nodes,
                    "nodesNotice" to state.nodesNotice,
                    "promqlPanelRows" to state.promqlPanelRows,
                ),
        )
    val remote =
        DerivedScreenWalk(
            screen = "Remote",
            values =
                linkedMapOf(
                    "pointerLabel" to state.pointerLabel,
                    "mediaTitle" to state.mediaTitle,
                    "mediaSub" to state.mediaSub,
                    "volumeValue" to state.volumeValue,
                    "volumeFraction" to state.volumeFraction,
                    "brightnessValue" to state.brightnessValue,
                    "brightnessFraction" to state.brightnessFraction,
                    "macros" to state.macros,
                    "clipboard" to state.clipboard,
                    "terminal" to state.terminal.toList(),
                    "agentTranscript" to state.agentTranscript.toList(),
                    "recentCommands" to state.recentCommands,
                ),
        )
    val moduleMap = linkedMapOf<String, ModuleDashboard>()
    for (entry in MockHost.gallery) {
      state.openModule(entry.id)
      moduleMap[entry.id] = state.currentModule
    }
    val modules =
        DerivedScreenWalk(
            screen = "Modules",
            values =
                linkedMapOf(
                    "effectiveInstalled" to state.effectiveInstalled,
                    "moduleChipIds" to state.moduleChips.map { it.id }.toSet(),
                    "dashboards" to moduleMap,
                ),
        )
    return listOf(home, mac, remote, modules)
  }

  /**
   * Collects actual runtime [MockHost] objects, collections, and distinctive field values directly
   * from [MockHost]'s live fields for comparison against walked derived values.
   */
  private fun mockHostValues(): Map<Any, String> {
    val entries = linkedMapOf<Any, String>()
    fun record(label: String, value: Any?) {
      if (value == null) return
      if (value is Collection<*> && value.isEmpty()) return
      if (value is Map<*, *> && value.isEmpty()) return
      if (value is String && value.isBlank()) return
      entries.putIfAbsent(value, label)
    }

    record("MockHost.hosts", MockHost.hosts)
    MockHost.hosts.forEachIndexed { idx, h ->
      record("MockHost.hosts[$idx]", h)
      record("MockHost.hosts[$idx].id", h.id)
      record("MockHost.hosts[$idx].name", h.name)
      record("MockHost.hosts[$idx].subtitle", h.subtitle)
    }

    record("MockHost.builtInMacros", MockHost.builtInMacros)
    MockHost.builtInMacros.forEachIndexed { idx, m ->
      record("MockHost.builtInMacros[$idx]", m)
      record("MockHost.builtInMacros[$idx].id", m.id)
      record("MockHost.builtInMacros[$idx].label", m.label)
      record("MockHost.builtInMacros[$idx].command", m.command)
    }

    record("MockHost.runningNow", MockHost.runningNow)
    MockHost.runningNow.forEachIndexed { idx, r ->
      record("MockHost.runningNow[$idx]", r)
      record("MockHost.runningNow[$idx].subtitle", r.subtitle)
    }

    record("MockHost.demoInstalled", MockHost.demoInstalled)

    record("MockHost.processes", MockHost.processes)
    MockHost.processes.forEachIndexed { idx, p ->
      record("MockHost.processes[$idx]", p)
      record("MockHost.processes[$idx].memory", p.memory)
    }

    record("MockHost.vms", MockHost.vms)
    MockHost.vms.forEachIndexed { idx, vm ->
      record("MockHost.vms[$idx]", vm)
      record("MockHost.vms[$idx].name", vm.name)
      record("MockHost.vms[$idx].subtitle", vm.subtitle)
    }

    record("MockHost.containers", MockHost.containers)
    MockHost.containers.forEachIndexed { idx, c ->
      record("MockHost.containers[$idx]", c)
      record("MockHost.containers[$idx].subtitle", c.subtitle)
    }

    record("MockHost.initialTerminal", MockHost.initialTerminal)
    MockHost.initialTerminal.forEachIndexed { idx, line ->
      record("MockHost.initialTerminal[$idx]", line)
    }

    record("MockHost.initialAgentTranscript", MockHost.initialAgentTranscript)
    MockHost.initialAgentTranscript.forEachIndexed { idx, line ->
      record("MockHost.initialAgentTranscript[$idx]", line)
      record("MockHost.initialAgentTranscript[$idx].text", line.text)
    }

    record("MockHost.recentCommands", MockHost.recentCommands)

    val variants =
        listOf(
            "running" to MockHost.dashboards(MockHost.initialAgentTranscript, agentRunning = true),
            "idle" to MockHost.dashboards(emptyList(), agentRunning = false),
        )
    for ((variant, dashboards) in variants) {
      for ((id, dash) in dashboards) {
        val prefix = "MockHost.dashboards($variant)[$id]"
        record(prefix, dash)
        record("$prefix.meta", dash.meta)
        record("$prefix.metrics", dash.metrics)
        dash.metrics.forEachIndexed { idx, metric -> record("$prefix.metrics[$idx]", metric) }
        record("$prefix.lines", dash.lines)
        dash.lines.forEachIndexed { idx, line -> record("$prefix.lines[$idx]", line) }
        record("$prefix.rows", dash.rows)
        dash.rows.forEachIndexed { idx, row ->
          record("$prefix.rows[$idx]", row)
          record("$prefix.rows[$idx].title", row.title)
          record("$prefix.rows[$idx].subtitle", row.subtitle)
        }
      }
    }
    return entries
  }

  private fun walkAndFindMockMatch(
      walks: List<DerivedScreenWalk>,
      mockValues: Map<Any, String>,
  ): String? {
    fun visit(path: String, value: Any?): String? {
      if (value == null) return null
      if (value is Collection<*> && value.isEmpty()) return null
      if (value is Map<*, *> && value.isEmpty()) return null

      mockValues[value]?.let { matchedField ->
        return "$path matched $matchedField (value=$value)"
      }

      if (path.endsWith(".recentCommands") && value is Collection<*>) {
        for ((idx, item) in value.withIndex()) {
          if (item is String && item in MockHost.recentCommands) {
            return "$path[$idx] matched MockHost.recentCommands (value=$item)"
          }
        }
      }

      return when (value) {
        is DerivedScreenWalk -> visit("${value.screen}", value.values)
        is Map<*, *> -> {
          for ((k, v) in value) {
            visit("$path.$k", v)?.let {
              return it
            }
          }
          null
        }
        is Collection<*> -> {
          for ((idx, item) in value.withIndex()) {
            visit("$path[$idx]", item)?.let {
              return it
            }
          }
          null
        }
        is Host ->
            visit("$path.id", value.id)
                ?: visit("$path.name", value.name)
                ?: visit("$path.subtitle", value.subtitle)
                ?: visit("$path.tag", value.tag)
        is Macro ->
            visit("$path.id", value.id)
                ?: visit("$path.label", value.label)
                ?: visit("$path.command", value.command)
        is RunningItem ->
            visit("$path.moduleId", value.moduleId)
                ?: visit("$path.title", value.title)
                ?: visit("$path.subtitle", value.subtitle)
                ?: visit("$path.tag", value.tag)
        is Widget ->
            visit("$path.id", value.id)
                ?: visit("$path.label", value.label)
                ?: visit("$path.value", value.value)
                ?: visit("$path.sub", value.sub)
        is HonestMetric ->
            visit("$path.label", value.label)
                ?: visit("$path.value", value.value)
                ?: visit("$path.sub", value.sub)
        is Process -> visit("$path.name", value.name) ?: visit("$path.memory", value.memory)
        is Vm ->
            visit("$path.name", value.name)
                ?: visit("$path.subtitle", value.subtitle)
                ?: visit("$path.tag", value.tag)
        is Container ->
            visit("$path.name", value.name)
                ?: visit("$path.subtitle", value.subtitle)
                ?: visit("$path.trailing", value.trailing)
        is Notice -> visit("$path.title", value.title) ?: visit("$path.detail", value.detail)
        is PanelRow -> visit("$path.name", value.name) ?: visit("$path.value", value.value)
        is TerminalLine -> visit("$path.text", value.text)
        is ModuleMetric ->
            visit("$path.label", value.label)
                ?: visit("$path.value", value.value)
                ?: visit("$path.sub", value.sub)
        is ModuleRow ->
            visit("$path.title", value.title)
                ?: visit("$path.subtitle", value.subtitle)
                ?: visit("$path.trailing", value.trailing)
                ?: visit("$path.tag", value.tag)
        is ModuleList -> visit("$path.label", value.label) ?: visit("$path.rows", value.rows)
        is ModuleDashboard ->
            visit("$path.name", value.name)
                ?: visit("$path.meta", value.meta)
                ?: visit("$path.status", value.status)
                ?: visit("$path.metrics", value.metrics)
                ?: visit("$path.streamLabel", value.streamLabel)
                ?: visit("$path.lines", value.lines)
                ?: visit("$path.listLabel", value.listLabel)
                ?: visit("$path.rows", value.rows)
                ?: visit("$path.extraLists", value.extraLists)
        else -> null
      }
    }

    for (walk in walks) {
      visit(walk.screen, walk.values)?.let {
        return it
      }
    }
    return null
  }

  @Test
  public fun `offline saved Mac never answered leaks zero MockHost fields`() {
    val state = newSavedMacState()
    state.applyPollFailure("connect timed out")

    assertFalse(state.isDemoMode)
    assertFalse(state.hostResponded)
    assertTrue(state.isOffline)
    assertTrue(state.isStaleReading)
    assertEquals(Derive.HostPhase.Offline, state.hostPhase)
    assertNull(state.agentMetrics)
    assertNull(state.agentHost)
    assertTrue(state.widgets.isEmpty())

    val walks = deriveAllScreens(state)
    val match = walkAndFindMockMatch(walks, mockHostValues())
    assertNull("Unexpected MockHost value when saved Mac never answered: $match", match)
  }

  @Test
  public fun `offline saved Mac with old reading freezes reading and leaks zero MockHost fields`() {
    val state = newSavedMacState()
    val realHost =
        AgentHost(
            hostname = "studio-mbp.local",
            model = "MacBook Pro (14-inch, Nov 2023)",
            chip = "Apple M3 Pro",
            cores = 12,
            memoryBytes = 36_000_000_000L,
            osVersion = "15.4",
            agentVersion = "1.12.0",
            macAddress = "10:20:30:40:50:60",
            wakeOnLan = true,
        )
    val realMetrics =
        AgentMetrics(
            cpuReady = true,
            cpuBusyPercent = 19.4,
            load1 = 1.72,
            memoryUsedBytes = 14_500_000_000L,
            memoryTotalBytes = 36_000_000_000L,
            memoryFreePercent = 58,
            batteryPresent = true,
            batteryPercent = 91,
            onAc = true,
            charging = false,
            batteryTemperatureC = 32.5,
            drawWatts = 0.0,
            systemWatts = 14.2,
            diskUsedPercent = 47.0,
            diskUsedBytes = 470_000_000_000L,
            diskAvailableBytes = 530_000_000_000L,
            diskTotalBytes = 1_000_000_000_000L,
            rxBytesPerSec = 250_000.0,
            txBytesPerSec = 80_000.0,
            throttled = false,
            cpuSpeedLimitPercent = 100,
            uptimeSeconds = 432_000L,
            unavailable = emptySet(),
            sampledAt = "2026-11-15T00:00:00Z",
        )
    state.applyPollSuccess(realHost, realMetrics)
    state.applyEndpointReadings(
        processes = listOf(AgentProcess("swift-frontend", 11.2, 640_000_000L)),
        vms =
            AgentList(
                available = true,
                reason = "",
                items =
                    listOf(
                        AgentVm(
                            name = "dev-box",
                            status = "Running",
                            vmType = "vz",
                            cpus = 6,
                            memoryBytes = 12_000_000_000L,
                            diskBytes = 80_000_000_000L,
                            arch = "arm64",
                        )),
            ),
        containers =
            AgentList(
                available = true,
                reason = "",
                items = listOf(AgentContainer("pg-dev", "postgres:16", "Up 2 hours")),
                detail = "docker",
            ),
        k8s =
            AgentList(
                available = true,
                reason = "",
                items = listOf(AgentNode("lab-1", true, "v1.31.1", listOf("control-plane"))),
                detail = "studio-k3s",
            ),
        claudeSessions =
            listOf(
                AgentClaudeSession(
                    sessionId = "sess-real-1",
                    project = "payments-api",
                    cwd = "/Users/dev/payments-api",
                    path = "/Users/dev/.claude/projects/payments-api/sess-real-1.jsonl",
                    lastActive = "2026-11-15T00:00:00Z",
                    state = "waiting",
                    lastRole = "assistant",
                    lastText = "All payments unit tests pass",
                    lastTool = "",
                )),
        sessions = AgentSessions(sessions = emptyList(), runningProcesses = 1),
        prs =
            AgentList(
                available = true,
                reason = "",
                items =
                    listOf(
                        AgentPr(
                            repo = "acme/payments",
                            number = 42,
                            title = "Tighten webhook signature check",
                            url = "https://github.com/acme/payments/pull/42",
                            author = "dev",
                            isDraft = false,
                            headRef = "fix/webhook",
                            baseRef = "main",
                            mergeState = "CLEAN",
                            reviewDecision = "APPROVED",
                            checksSuccess = 4,
                            checksFailure = 0,
                            checksPending = 0,
                            checksSkipped = 0,
                            autoMerge = false,
                            updatedAt = "2026-11-15T00:00:00Z",
                        )),
            ),
        argo =
            AgentList(
                available = true,
                reason = "",
                items =
                    listOf(
                        AgentArgoApp(
                            name = "payments-api",
                            namespace = "payments",
                            project = "default",
                            sync = "Synced",
                            health = "Healthy",
                            revision = "abc1234",
                            lastSynced = "2026-11-15T00:00:00Z",
                            message = "",
                        )),
            ),
        ollama =
            AgentOllama(
                available = true,
                reason = "",
                models = listOf(AgentOllamaModel("qwen2.5-coder:7b", 4_700_000_000L, "today")),
                running = emptyList(),
            ),
        antigravity =
            AgentAntigravity(
                available = true,
                reason = "",
                version = "2.1.0",
                models = listOf("gemini-2.5-pro" to "Gemini 2.5 Pro"),
                agents = listOf("reviewer"),
            ),
        audio = AgentAudio(volumePercent = 45, muted = false),
        tools =
            AgentTools(
                mapOf(
                    "limactl" to AgentTool(true, "/opt/homebrew/bin/limactl"),
                    "gh" to AgentTool(true, "/opt/homebrew/bin/gh"),
                )),
        gpuPowerWatts = 4.2,
        anePowerWatts = 0.8,
    )

    state.applyPollFailure("connection reset by peer")

    assertFalse(state.isDemoMode)
    assertTrue(state.hostResponded)
    assertTrue(state.isOffline)
    assertTrue(state.isStaleReading)
    assertEquals(Derive.HostPhase.Offline, state.hostPhase)
    assertNotNull(state.agentMetrics)
    assertNotNull(state.agentHost)
    assertEquals("unreachable", state.metricsTagLabel)
    assertTrue(state.widgets.all { it.stale })

    val walks = deriveAllScreens(state)
    val match = walkAndFindMockMatch(walks, mockHostValues())
    assertNull(
        "Unexpected MockHost value when saved Mac is offline with an old reading: $match",
        match,
    )
  }

  @Test
  public fun `positive control detects MockHost values when demo mode is entered`() {
    val state =
        RemoteState(
            persistence = Persistence(InMemoryKeyValueStore()),
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    state.enterDemo()
    val match = walkAndFindMockMatch(deriveAllScreens(state), mockHostValues())
    if (match == null) {
      fail("Positive control failed: demo mode did not expose any MockHost value to walker")
    }
  }

  @Test
  public fun `about navigation works when unpaired and returns step by step to Settings`() {
    val state =
        RemoteState(
            persistence = Persistence(InMemoryKeyValueStore()),
            appVersion = "0.1.40",
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    assertTrue(state.isUnpaired)
    assertEquals(Screen.Hosts, state.effectiveScreen)

    state.openAbout()
    assertEquals(Screen.About, state.effectiveScreen)
    assertEquals(AboutPage.Main, state.aboutPage)

    state.openAboutPage(AboutPage.Privacy)
    assertEquals(Screen.About, state.effectiveScreen)
    assertEquals(AboutPage.Privacy, state.aboutPage)

    state.backFromAbout()
    assertEquals(Screen.About, state.effectiveScreen)
    assertEquals(AboutPage.Main, state.aboutPage)

    state.backFromAbout()
    assertEquals(Screen.Hosts, state.effectiveScreen)
    assertEquals(AboutPage.Main, state.aboutPage)
  }

  @Test
  public fun `send crash reports defaults true persists across restart and notifies callback`() {
    val store = InMemoryKeyValueStore()
    val events = mutableListOf<Boolean>()
    val first =
        RemoteState(
            persistence = Persistence(store),
            onCrashReportsChanged = { events.add(it) },
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    assertTrue(first.sendCrashReports)

    first.updateSendCrashReports(false)
    assertFalse(first.sendCrashReports)
    assertEquals(listOf(false), events)

    val restarted =
        RemoteState(
            persistence = Persistence(store),
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    assertFalse(restarted.sendCrashReports)

    restarted.updateSendCrashReports(true)
    assertTrue(restarted.sendCrashReports)
    assertTrue(Persistence(store).sendCrashReports)
  }

  @Test
  public fun `openExternalUrl populates fallback URL dialog when no browser handles intent`() {
    val written = mutableListOf<String>()
    val clipboard =
        object : PhoneClipboard {
          override fun read(): String = written.lastOrNull().orEmpty()

          override fun write(text: String) {
            written.add(text)
          }
        }
    val noBrowserState =
        RemoteState(
            persistence = Persistence(InMemoryKeyValueStore()),
            phoneClipboard = clipboard,
            openUrl = { false },
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    assertNull(noBrowserState.fallbackUrl)
    assertFalse(noBrowserState.openExternalUrl(AppInfo.donateURL))
    assertEquals(AppInfo.donateURL, noBrowserState.fallbackUrl)

    noBrowserState.copyFallbackUrl()
    assertEquals(listOf(AppInfo.donateURL), written)

    noBrowserState.dismissFallbackUrl()
    assertNull(noBrowserState.fallbackUrl)

    val withBrowserState =
        RemoteState(
            persistence = Persistence(InMemoryKeyValueStore()),
            openUrl = { true },
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    assertTrue(withBrowserState.openExternalUrl(AppInfo.donateURL))
    assertNull(withBrowserState.fallbackUrl)
  }

  @Test
  public fun `copyVersionInfo writes Android device summary to clipboard and sets confirmation`() {
    val written = mutableListOf<String>()
    val clipboard =
        object : PhoneClipboard {
          override fun read(): String = written.lastOrNull().orEmpty()

          override fun write(text: String) {
            written.add(text)
          }
        }
    val state =
        RemoteState(
            persistence = Persistence(InMemoryKeyValueStore()),
            phoneClipboard = clipboard,
            appVersion = "0.1.40",
            androidRelease = "15",
            deviceModel = "Pixel Fold",
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    assertFalse(state.versionCopied)
    state.copyVersionInfo()
    assertTrue(state.versionCopied)
    assertEquals(listOf("Vitruvian Remote 0.1.40 (Android 15, Pixel Fold)"), written)

    state.clearVersionCopied()
    assertFalse(state.versionCopied)
  }

  @Test
  public fun `requestForgetAgent opens non-typed danger confirmation and deletes host on confirm`() {
    val state =
        RemoteState(
            persistence = Persistence(InMemoryKeyValueStore()),
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    state.addHost("100.64.0.9")
    state.updateHostAliasDraft("atlas")
    state.saveHostAlias()
    assertEquals(1, state.hosts.size)

    state.requestForgetAgent()
    val kind = state.dialog as? DialogKind.ForgetHost
    assertNotNull(kind)
    val spec = state.dialogSpec!!
    assertEquals("Forget atlas?", spec.title)
    assertEquals("You'll need to pair again from the Mac.", spec.body)
    assertEquals("Forget", spec.action)
    assertTrue(spec.destructive)
    assertNull(spec.word)

    state.confirmDialog()
    assertTrue(state.hosts.isEmpty())
    assertNull(state.dialog)
  }

  @Test
  public fun `secondary navigation stack returns PhoneBridge, About sub-pages and Settings to Home`() {
    val state =
        RemoteState(
            persistence = Persistence(InMemoryKeyValueStore()),
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    state.enterDemo()
    assertEquals(Screen.Home, state.effectiveScreen)
    assertFalse(state.canGoBack)

    state.go(Screen.Hosts)
    assertEquals(Screen.Hosts, state.effectiveScreen)
    assertTrue(state.canGoBack)

    state.openPhoneBridge()
    assertEquals(Screen.PhoneBridge, state.effectiveScreen)
    assertTrue(state.navigateBack())
    assertEquals(Screen.Hosts, state.effectiveScreen)

    state.openAboutPage(AboutPage.Privacy)
    assertEquals(Screen.About, state.effectiveScreen)
    assertEquals(AboutPage.Privacy, state.aboutPage)

    assertTrue(state.navigateBack())
    assertEquals(Screen.About, state.effectiveScreen)
    assertEquals(AboutPage.Main, state.aboutPage)

    assertTrue(state.navigateBack())
    assertEquals(Screen.Hosts, state.effectiveScreen)

    assertTrue(state.navigateBack())
    assertEquals(Screen.Home, state.effectiveScreen)
    assertFalse(state.canGoBack)
    assertFalse(state.navigateBack())
  }

  @Test
  public fun `hideWidget populates hiddenWidgetOptions and showWidget restores one widget`() {
    val state =
        RemoteState(
            persistence = Persistence(InMemoryKeyValueStore()),
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    state.enterDemo()
    assertTrue(state.hiddenWidgetOptions.isEmpty())

    state.hideWidget("cpu")
    state.hideWidget("bat")
    assertEquals(listOf("cpu", "bat"), state.hiddenWidgetOptions.map { it.id })
    assertFalse(state.widgets.any { it.id == "cpu" })
    assertFalse(state.widgets.any { it.id == "bat" })

    state.showWidget("cpu")
    assertTrue(state.widgets.any { it.id == "cpu" })
    assertFalse(state.widgets.any { it.id == "bat" })
    assertEquals(listOf("bat"), state.hiddenWidgetOptions.map { it.id })
  }
}
