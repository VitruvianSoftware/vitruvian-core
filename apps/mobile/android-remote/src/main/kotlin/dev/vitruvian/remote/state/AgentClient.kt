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

import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.Instant
import java.time.OffsetDateTime
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * One reading from the Mac agent's `GET /v1/metrics`.
 *
 * Mirrors the agent's JSON, including its honesty markers: [cpuReady] is false for the first few
 * seconds while `top` samples, and [unavailable] names every figure the agent cannot read without
 * root. A dashboard that ignores either will show a zero as if it were a measurement.
 */
public data class AgentMetrics(
    val cpuReady: Boolean,
    val cpuBusyPercent: Double,
    val load1: Double,
    val memoryUsedBytes: Long,
    val memoryTotalBytes: Long,
    val memoryFreePercent: Int,
    val batteryPresent: Boolean,
    val batteryPercent: Int,
    val onAc: Boolean,
    val charging: Boolean,
    /**
     * The battery's own sensor, in Celsius. Null when macOS does not report one (API v1.5.1): the
     * agent used to send 0 for that, and the phone printed it as "battery 0°".
     */
    val batteryTemperatureC: Double?,
    /** The battery's own discharge. 0 on AC by definition, so never the headline there. */
    val drawWatts: Double,
    /** The whole Mac's draw from the adapter (v1.5.1). Null when macOS does not say. */
    val systemWatts: Double?,
    val diskUsedPercent: Double,
    val diskUsedBytes: Long,
    val diskAvailableBytes: Long,
    /** The data volume's size. 0 from an agent older than v1.5.1, which did not send it. */
    val diskTotalBytes: Long,
    val rxBytesPerSec: Double,
    val txBytesPerSec: Double,
    val throttled: Boolean,
    val cpuSpeedLimitPercent: Int,
    val uptimeSeconds: Long,
    val unavailable: Set<String>,
)

/** `GET /v1/host`: the slow-changing identity of the machine. */
public data class AgentHost(
    val hostname: String,
    val model: String,
    val chip: String,
    val cores: Int,
    val memoryBytes: Long,
    val osVersion: String,
    val agentVersion: String,
    /** en0's, so the phone can aim a Wake-on-LAN packet at a machine that is asleep. */
    val macAddress: String,
    /** `pmset womp`: whether the Mac would actually answer that packet. */
    val wakeOnLan: Boolean,
)

/** One row of `GET /v1/processes` - the top 8 by CPU. */
public data class AgentProcess(val name: String, val cpuPercent: Double, val memoryBytes: Long)

/**
 * A list the agent may not have been able to produce.
 *
 * The contract's rule carried into the type system: `available:false` arrives with a [reason], and
 * the phone must show that reason IN PLACE OF the list. An empty list rendered as an empty list
 * reads as "nothing running", which is a different claim entirely.
 */
public data class AgentList<T>(
    val available: Boolean,
    val reason: String,
    val items: List<T>,
    /** The extra word the endpoint carries: the container runtime, the kube context. */
    val detail: String = "",
)

/** One `limactl list` instance. */
/** `GET /v1/ollama`: installed models and the ones loaded right now. */
public data class AgentOllama(
    val available: Boolean,
    val reason: String,
    val models: List<AgentOllamaModel>,
    val running: List<AgentOllamaLoaded>,
)

public data class AgentOllamaModel(val name: String, val sizeBytes: Long, val modified: String)

public data class AgentOllamaLoaded(
    val name: String,
    val sizeBytes: Long,
    val processor: String,
    val context: Int,
    val until: String,
)

public data class AgentVm(
    val name: String,
    val status: String,
    val vmType: String,
    val cpus: Int,
    val memoryBytes: Long,
    val diskBytes: Long,
    val arch: String,
)

/** One `docker ps` / `podman ps` container. */
public data class AgentContainer(val name: String, val image: String, val status: String)

/** One `kubectl get nodes` node. */
public data class AgentNode(
    val name: String,
    val ready: Boolean,
    val version: String,
    val roles: List<String>,
)

/** `GET /v1/audio` - the one output figure the Mac will actually tell us. */
public data class AgentAudio(val volumePercent: Int, val muted: Boolean)

/** One Claude Code session, as the agent infers it from `~/.claude/projects`. */
public data class AgentSession(val project: String, val lastActive: String, val path: String)

/** `GET /v1/sessions` - the sessions, plus the count of live `claude` processes. */
public data class AgentSessions(val sessions: List<AgentSession>, val runningProcesses: Int)

/**
 * `GET /v1/promql`, flattened.
 *
 * Deliberately not the whole Prometheus document: the panel shows what kind of result came back,
 * how many series it has and the first value, and there is nothing on this screen that could render
 * more. [available] false carries the agent's own reason, normally "not configured".
 */
public data class AgentPromql(
    val available: Boolean,
    val reason: String,
    val resultType: String,
    val seriesCount: Int,
    val firstValue: Double?,
    /** Every series in an instant-vector reply: its labels and newest value. */
    val series: List<AgentSeries> = emptyList(),
)

public data class AgentSeries(val labels: Map<String, String>, val value: Double?)

/** `GET /v1/tools`: which programs the Mac has. */
public data class AgentTools(val tools: Map<String, AgentTool>)

public data class AgentTool(val available: Boolean, val path: String)

/** `GET /v1/antigravity`. */
public data class AgentAntigravity(
    val available: Boolean,
    val reason: String,
    val version: String,
    val models: List<Pair<String, String>>,
    val agents: List<String>,
)

/** `POST /v1/exec`. A non-zero [exitCode] is an ordinary 200, not an error. */
public data class AgentExec(
    val exitCode: Int,
    val stdout: String,
    val stderr: String,
    val durationMs: Int,
    val truncated: Boolean,
)

/** What `POST /v1/exec` should run it as - the contract's four `kind` values. */
public enum class ExecKind(public val wire: String) {
  Shell("shell"),
  AppleScript("applescript"),
  Shortcut("shortcut"),
  Claude("claude"),
}

/**
 * 401 or 403 from an act endpoint: this phone is not paired, or its token is wrong.
 *
 * Its own type because it is the one failure with a remedy the user can act on. Every other network
 * error means "the Mac is not answering"; this one means "pair, and it will".
 */
public class AgentAuthException(message: String) : RuntimeException(message)

/**
 * 503 from an endpoint the Mac itself cannot serve, with the Mac's own reason.
 *
 * `/v1/screen` without Screen Recording is the case that motivated it: the agent is healthy, the
 * phone is paired, and the answer is still no. The remedy is a macOS privacy setting, and the only
 * way the user can learn that is for [reason] to reach the screen verbatim.
 */
public class AgentUnavailableException(public val reason: String) : RuntimeException(reason)

/**
 * 404 from an endpoint.
 *
 * Its own type because two different answers share the code and both matter: an agent older than
 * the endpoint (the feature is not there, so hide it and say "update the agent"), and an id the
 * agent no longer holds (a Claude prompt already answered on the Mac, or expired). Either is a fact
 * about the Mac, not a network failure, and an `IllegalStateException` could not be told apart from
 * one.
 */
public class AgentNotFoundException(message: String) : RuntimeException(message)

/**
 * Any other non-200, with the agent's own `error` text kept apart in [detail].
 *
 * An `IllegalStateException` as before, so nothing that caught one changes; the difference is that
 * a caller who needs the Mac's words verbatim -- the Claude hook toggle, whose 500 says what is
 * wrong with `settings.json` -- no longer has to peel "agent: " off the message.
 */
public class AgentRequestException(
    public val status: Int,
    public val detail: String,
    message: String
) : IllegalStateException(message)

// --- v1.2 ---------------------------------------------------------------

/** One streamed line: which pipe it came from, and the text. */
public data class ExecLine(val stream: String, val text: String)

/** How a streamed exec ended. Lines were delivered as they arrived, so none are repeated here. */
public data class ExecResult(
    val exitCode: Int,
    val durationMs: Int,
    /** True when the phone hung up: the agent killed the process, and there is no exit code. */
    val cancelled: Boolean = false,
)

/**
 * The phone's end of a streaming exec, held so it can be hung up.
 *
 * Cancellation IS closing the connection -- the agent kills the process group when the client
 * disconnects -- so Stop has to reach the socket from the main thread while an IO thread is blocked
 * reading it. `disconnect()` is the one call that unblocks that read.
 */
public class ExecStreamHandle {
  @Volatile private var connection: HttpURLConnection? = null

  @Volatile
  public var cancelled: Boolean = false
    private set

  internal fun attach(conn: HttpURLConnection) {
    connection = conn
    // Stop pressed between the request being built and the socket opening:
    // without this the command would run to completion unattended.
    if (cancelled) runCatching { conn.disconnect() }
  }

  /** Hangs up. Safe from any thread, and safe to call twice. */
  public fun cancel() {
    cancelled = true
    runCatching { connection?.disconnect() }
  }
}

/** One Claude Code session as `/v1/claude/sessions` infers it. [state] is the agent's heuristic. */
public data class AgentClaudeSession(
    val sessionId: String,
    val project: String,
    val cwd: String,
    val path: String,
    val lastActive: String,
    val state: String,
    val lastRole: String,
    val lastText: String,
    val lastTool: String,
)

/**
 * One Claude Code permission prompt held by the agent for the phone to answer (API v1.6).
 *
 * [expiresAtMs] is the agent's `expires_at` read as epoch milliseconds, or 0 when it could not be
 * parsed; the countdown then says "expired" rather than inventing a deadline. It is compared with
 * the PHONE's clock: both ends keep network time over the tailnet, and a second of skew moves a
 * two-minute countdown by one tick, which is not worth a round trip to measure.
 */
public data class PendingPermission(
    val id: String,
    val sessionId: String,
    val project: String,
    val cwd: String,
    val tool: String,
    val summary: String,
    val detail: String,
    val createdAt: String,
    val expiresAt: String,
    val expiresAtMs: Long,
)

/**
 * `GET /v1/claude/permissions`: whether the phone-approval hook is installed in Claude Code on the
 * Mac, how long the agent holds a prompt, and the prompts waiting now.
 */
public data class AgentClaudePermissions(
    val enabled: Boolean,
    val waitSeconds: Int,
    val pending: List<PendingPermission>,
)

/** `POST /v1/claude/permissions/enabled`: the hook's state after the change, and the file. */
public data class AgentClaudeHook(val enabled: Boolean, val settingsPath: String)

/** One Antigravity conversation from `/v1/antigravity/sessions` (API v1.7), newest first. */
public data class AgentAntigravitySession(
    val id: String,
    val title: String,
    val preview: String,
    /** The basename of the conversation's first workspace. */
    val project: String,
    val steps: Int,
    val updatedAt: String,
    /** `working`, `idle` or `killed` -- the agent's reading. */
    val state: String,
)

/** `GET /v1/antigravity/sessions`: [available] false carries the agent's reason. */
public data class AgentAntigravitySessions(
    val available: Boolean,
    val reason: String,
    val sessions: List<AgentAntigravitySession>,
)

/** One open pull request from `/v1/prs`, with its check counts already summed by the agent. */
public data class AgentPr(
    val repo: String,
    val number: Int,
    val title: String,
    val url: String,
    val author: String,
    val isDraft: Boolean,
    val headRef: String,
    val baseRef: String,
    val mergeState: String,
    val reviewDecision: String,
    val checksSuccess: Int,
    val checksFailure: Int,
    val checksPending: Int,
    val checksSkipped: Int,
    val autoMerge: Boolean,
    val updatedAt: String,
)

/** One ArgoCD Application from `/v1/argocd`. */
public data class AgentArgoApp(
    val name: String,
    val namespace: String,
    val project: String,
    val sync: String,
    val health: String,
    val revision: String,
    val lastSynced: String,
    val message: String,
)

/** `{ok, output}` -- what the PR and ArgoCD act endpoints reply with. */
public data class AgentActionResult(val ok: Boolean, val output: String)

/** `/v1/homespeaker`: what the Mac's HomeSpeaker app is doing, from its own config file. */
public data class AgentHomeSpeaker(
    val available: Boolean,
    val reason: String,
    val installed: Boolean,
    val appRunning: Boolean,
    val signedIn: Boolean,
    val enabled: Boolean,
    val defaultTarget: String,
    /** `headline`, `summary` or `full`. */
    val speechLength: String,
    /** HomeSpeaker pauses what the Mac is playing while it announces. */
    val pauseMedia: Boolean,
    /** Seconds after the estimated end of an announcement before resuming. */
    val pauseMediaExtraSeconds: Double,
    /** Set the speaker to [announceVolume] % for each announcement, then put it back. */
    val announceVolumeEnabled: Boolean,
    val announceVolume: Int,
    /**
     * The two outputs (agent v1.8): the Google Home speaker and this Mac. Null from an older agent,
     * which cannot switch them -- the dashboard then hides the switches rather than guessing.
     */
    val speakHome: Boolean?,
    val speakLocal: Boolean?,
    /** The Mac's voice, chosen on the Mac: its identifier and a name for people ("Aaron"). */
    val localVoice: String,
    val localVoiceName: String,
    val structureName: String,
    val quietHoursEnabled: Boolean,
    val quietHoursStart: String,
    val quietHoursEnd: String,
    val targets: List<AgentSpeakerTarget>,
    val last: AgentLastBroadcast?,
)

/**
 * `/v1/homespeaker/volume`: the default speaker's volume as HomeSpeaker reads it from Google.
 * [online] false means [percent] is only the last level the speaker had.
 */
public data class AgentSpeakerVolume(
    val available: Boolean,
    val reason: String,
    val speaker: String,
    val percent: Int,
    val muted: Boolean,
    val online: Boolean,
)

public data class AgentSpeakerTarget(
    val key: String,
    val name: String,
    val room: String,
    val type: String,
    val selected: Boolean,
)

public data class AgentLastBroadcast(
    val text: String,
    val target: String,
    val source: String,
    val at: String,
)

/** Whether the agent has somewhere to publish notifications, from `/healthz`. */
public data class AgentNotifyStatus(
    val configured: Boolean,
    val topic: String,
    /**
     * The mute switch. Separate from [configured] because the two answer different questions:
     * [configured] is "could the Mac ever push", [enabled] is "is it wanted right now". Muting must
     * not read on screen as an agent with missing flags.
     */
    val enabled: Boolean = true,
)

/**
 * `GET /v1/phone`: what the Mac agent believes about the phone bridge.
 *
 * [trustUntil] is null when the phone last reported a closed window, which is also what an agent
 * that has never heard from a phone reports -- the two are the same claim from the Mac's side.
 */
public data class AgentPhoneLink(
    val connected: Boolean,
    val since: String,
    val model: String,
    val tools: List<String>,
    val trustUntil: String?,
)

/**
 * The phone's side of the read-only agent.
 *
 * Deliberately the platform's own `HttpURLConnection` and `org.json`: two GETs returning small
 * documents do not justify a client library, and this app has no network dependency today.
 * Everything runs on the IO dispatcher; the timeouts are short because a stalled read must show up
 * as "unreachable" within a couple of seconds, not hang a dashboard.
 */
public class AgentClient(baseUrl: String, private val token: String = "") {
  private val base = normalize(baseUrl)

  // --- read: no auth, the tailnet is the boundary -----------------------

  public suspend fun metrics(): AgentMetrics =
      withContext(Dispatchers.IO) { parseMetrics(get("/v1/metrics")) }

  public suspend fun host(): AgentHost = withContext(Dispatchers.IO) { parseHost(get("/v1/host")) }

  public suspend fun processes(): List<AgentProcess> =
      withContext(Dispatchers.IO) { parseProcesses(get("/v1/processes")) }

  public suspend fun tools(): AgentTools =
      withContext(Dispatchers.IO) { parseTools(get("/v1/tools")) }

  public suspend fun antigravity(): AgentAntigravity =
      withContext(Dispatchers.IO) { parseAntigravity(get("/v1/antigravity")) }

  public suspend fun ollama(): AgentOllama =
      withContext(Dispatchers.IO) { parseOllama(get("/v1/ollama")) }

  public suspend fun vms(): AgentList<AgentVm> =
      withContext(Dispatchers.IO) { parseVms(get("/v1/vms")) }

  public suspend fun containers(): AgentList<AgentContainer> =
      withContext(Dispatchers.IO) { parseContainers(get("/v1/containers")) }

  public suspend fun k8s(): AgentList<AgentNode> =
      withContext(Dispatchers.IO) { parseK8s(get("/v1/k8s")) }

  public suspend fun audio(): AgentAudio =
      withContext(Dispatchers.IO) { parseAudio(get("/v1/audio")) }

  public suspend fun sessions(): AgentSessions =
      withContext(Dispatchers.IO) { parseSessions(get("/v1/sessions")) }

  public suspend fun promql(query: String): AgentPromql =
      withContext(Dispatchers.IO) {
        parsePromql(get("/v1/promql?q=" + URLEncoder.encode(query, "UTF-8")))
      }

  /** Whether the agent answers at all. What the phone waits on after a Wake-on-LAN. */
  public suspend fun healthy(): Boolean =
      withContext(Dispatchers.IO) { runCatching { get("/healthz") }.isSuccess }

  // --- pairing ----------------------------------------------------------

  /**
   * One pairing attempt. The token, or null when the Mac has no matching code.
   *
   * A 403 here is the ordinary case rather than a failure: it means nobody has run the agent's
   * `pair` subcommand yet, and the phone will simply ask again on the next tick.
   */
  public suspend fun pair(code: String): String? =
      withContext(Dispatchers.IO) {
        val body = JSONObject().put("code", code.filterNot { it.isWhitespace() }).toString()
        try {
          JSONObject(post("/v1/pair", body, authenticated = false)).optString("token").ifBlank {
            null
          }
        } catch (_: AgentAuthException) {
          null
        }
      }

  // --- act: bearer token ------------------------------------------------

  public suspend fun exec(kind: ExecKind, command: String, timeoutSeconds: Int = 0): AgentExec =
      withContext(Dispatchers.IO) {
        val body =
            JSONObject().put("kind", kind.wire).put("command", command).apply {
              if (timeoutSeconds > 0) put("timeout_seconds", timeoutSeconds)
            }
        parseExec(
            post("/v1/exec", body.toString(), readTimeoutMs = execReadTimeout(timeoutSeconds)))
      }

  public suspend fun clipboard(): String =
      withContext(Dispatchers.IO) { JSONObject(get("/v1/clipboard")).optString("text") }

  public suspend fun setClipboard(text: String) {
    withContext(Dispatchers.IO) { post("/v1/clipboard", JSONObject().put("text", text).toString()) }
  }

  public suspend fun setVolume(percent: Int): AgentAudio =
      withContext(Dispatchers.IO) {
        val body = JSONObject().put("volume_percent", percent.coerceIn(0, 100)).toString()
        parseAudio(post("/v1/audio", body))
      }

  public suspend fun power(action: String) {
    withContext(Dispatchers.IO) { post("/v1/power", JSONObject().put("action", action).toString()) }
  }

  // --- v1.2 read --------------------------------------------------------

  public suspend fun claudeSessions(): List<AgentClaudeSession> =
      withContext(Dispatchers.IO) { parseClaudeSessions(get("/v1/claude/sessions")) }

  public suspend fun prs(): AgentList<AgentPr> =
      withContext(Dispatchers.IO) { parsePrs(get("/v1/prs")) }

  public suspend fun argocd(): AgentList<AgentArgoApp> =
      withContext(Dispatchers.IO) { parseArgo(get("/v1/argocd")) }

  /** Whether the agent can publish notifications at all, and where. From `/healthz`. */
  public suspend fun notifyStatus(): AgentNotifyStatus =
      withContext(Dispatchers.IO) { parseNotifyStatus(get("/healthz")) }

  // --- v1.2 act ---------------------------------------------------------

  /** Resumes a Claude Code session with one more prompt. Replies in the `/v1/exec` shape. */
  public suspend fun claudeResume(sessionId: String, prompt: String): AgentExec =
      withContext(Dispatchers.IO) {
        val body = JSONObject().put("session_id", sessionId).put("prompt", prompt).toString()
        parseExec(post("/v1/claude/resume", body, readTimeoutMs = RESUME_TIMEOUT_MS))
      }

  /** `approve`, `merge`, `auto_merge` or `ready`. Anything else is a 400 from the agent. */
  public suspend fun prAction(repo: String, number: Int, action: String): AgentActionResult =
      withContext(Dispatchers.IO) {
        val body =
            JSONObject().put("repo", repo).put("number", number).put("action", action).toString()
        parseAction(post("/v1/prs/action", body, readTimeoutMs = ACTION_TIMEOUT_MS))
      }

  public suspend fun argoSync(name: String, namespace: String): AgentActionResult =
      withContext(Dispatchers.IO) {
        val body = JSONObject().put("name", name).put("namespace", namespace).toString()
        parseAction(post("/v1/argocd/sync", body, readTimeoutMs = ACTION_TIMEOUT_MS))
      }

  public suspend fun notifyTest(): Unit =
      withContext<Unit>(Dispatchers.IO) { post("/v1/notify/test", "{}") }

  // --- v1.6: Claude Code permission prompts -------------------------------

  /**
   * The switch and the prompts waiting on it. Act tier, because a pending prompt carries the
   * command or path Claude wants to touch -- so this needs the token even though it only reads.
   */
  public suspend fun claudePermissions(): AgentClaudePermissions =
      withContext(Dispatchers.IO) { parseClaudePermissions(get("/v1/claude/permissions")) }

  /**
   * Installs (or removes) the agent's PermissionRequest hook in Claude Code's settings on the Mac.
   *
   * The reply is what the Mac now holds. A 500 is the Mac refusing for a reason worth reading --
   * `settings.json` is not valid JSON, say -- and arrives as [AgentRequestException] with that
   * text, so the screen can print it as the Mac wrote it.
   */
  public suspend fun setClaudePermissionsEnabled(on: Boolean): AgentClaudeHook =
      withContext(Dispatchers.IO) {
        val body = JSONObject().put("enabled", on).toString()
        val o = JSONObject(post("/v1/claude/permissions/enabled", body))
        AgentClaudeHook(o.optBoolean("enabled", false), o.optString("settings_path"))
      }

  /**
   * Answers one prompt. Throws [AgentNotFoundException] when the agent no longer holds [id]: it was
   * answered on the Mac, or its wait ran out and the Mac's own dialog took over.
   */
  public suspend fun decideClaudePermission(id: String, allow: Boolean, message: String = "") {
    withContext(Dispatchers.IO) {
      val body =
          JSONObject().apply {
            put("id", id)
            put("decision", if (allow) "allow" else "deny")
            // The contract takes a message on deny only, and caps it at 300.
            if (!allow && message.isNotBlank()) {
              put("message", message.trim().take(DENY_MESSAGE_MAX))
            }
          }
      post("/v1/claude/permissions/decide", body.toString())
    }
  }

  // --- v1.7: Antigravity parity -------------------------------------------

  /** The newest Antigravity conversations. A 404 is an agent older than v1.7. */
  public suspend fun antigravitySessions(): AgentAntigravitySessions =
      withContext(Dispatchers.IO) { parseAntigravitySessions(get("/v1/antigravity/sessions")) }

  /**
   * Sends one prompt to Antigravity and hands back every line as agy prints it.
   *
   * Blank [conversationId] starts a new conversation; otherwise agy continues that one, in its own
   * workspace. The same event stream as [execStream], so Stop through [handle] works the same way:
   * hanging up is what makes the agent kill agy.
   */
  public suspend fun antigravityResume(
      conversationId: String,
      prompt: String,
      handle: ExecStreamHandle = ExecStreamHandle(),
      onLine: (String, String) -> Unit,
  ): ExecResult =
      withContext(Dispatchers.IO) {
        val body =
            JSONObject().put("conversation_id", conversationId).put("prompt", prompt).toString()
        streamLines("/v1/antigravity/resume", body, handle, onLine)
      }

  // --- v1.4: HomeSpeaker ---------------------------------------------------

  public suspend fun homeSpeaker(): AgentHomeSpeaker =
      withContext(Dispatchers.IO) { parseHomeSpeaker(get("/v1/homespeaker")) }

  /**
   * Changes only the fields given. The reply is the Mac's state read back from the file, which is
   * what the dashboard should show -- not what the phone asked for.
   */
  public suspend fun setHomeSpeaker(
      enabled: Boolean? = null,
      defaultTarget: String? = null,
      speechLength: String? = null,
      quietHoursEnabled: Boolean? = null,
      pauseMedia: Boolean? = null,
      pauseMediaExtraSeconds: Double? = null,
      announceVolumeEnabled: Boolean? = null,
      announceVolume: Int? = null,
      speakHome: Boolean? = null,
      speakLocal: Boolean? = null,
  ): AgentHomeSpeaker =
      withContext(Dispatchers.IO) {
        val body =
            JSONObject().apply {
              if (speakHome != null) put("speak_home", speakHome)
              if (speakLocal != null) put("speak_local", speakLocal)
              if (enabled != null) put("enabled", enabled)
              if (defaultTarget != null) put("default_target", defaultTarget)
              if (speechLength != null) put("speech_length", speechLength)
              if (quietHoursEnabled != null) put("quiet_hours_enabled", quietHoursEnabled)
              if (pauseMedia != null) put("pause_media", pauseMedia)
              if (pauseMediaExtraSeconds != null)
                  put("pause_media_extra_seconds", pauseMediaExtraSeconds)
              if (announceVolumeEnabled != null)
                  put("announce_volume_enabled", announceVolumeEnabled)
              if (announceVolume != null) put("announce_volume", announceVolume)
            }
        parseHomeSpeaker(
            post("/v1/homespeaker", body.toString(), readTimeoutMs = ACTION_TIMEOUT_MS))
      }

  /** The default speaker's volume. A round trip to Google through the Mac: seconds, not ms. */
  public suspend fun homeSpeakerVolume(): AgentSpeakerVolume =
      withContext(Dispatchers.IO) {
        parseSpeakerVolume(get("/v1/homespeaker/volume", readTimeoutMs = VOLUME_TIMEOUT_MS))
      }

  /**
   * Sets the level, or mutes / unmutes -- exactly one. Answers with what Google reports afterwards;
   * Google takes ~3 s to report a change and the Mac waits for it, so this can take ~15 s.
   */
  public suspend fun setHomeSpeakerVolume(
      percent: Int? = null,
      muted: Boolean? = null
  ): AgentSpeakerVolume =
      withContext(Dispatchers.IO) {
        val body =
            JSONObject().apply {
              if (percent != null) put("percent", percent.coerceIn(0, 100))
              if (muted != null) put("muted", muted)
            }
        parseSpeakerVolume(
            post("/v1/homespeaker/volume", body.toString(), readTimeoutMs = VOLUME_TIMEOUT_MS))
      }

  /** `HomeSpeaker --say` on the Mac: deliberate speech, so it overrides quiet hours. */
  public suspend fun homeSpeakerSay(text: String): AgentActionResult =
      withContext(Dispatchers.IO) {
        val body = JSONObject().put("text", text).toString()
        parseAction(post("/v1/homespeaker/say", body, readTimeoutMs = ACTION_TIMEOUT_MS))
      }

  /**
   * Turns the Mac's push notifications on or off, and returns the state it ended in.
   *
   * The agent persists this, so it survives the restart a launchd agent gets at every login. The
   * reply is parsed rather than assumed: what the Mac believes is the only state worth rendering.
   */
  public suspend fun setNotifications(enabled: Boolean): AgentNotifyStatus =
      withContext(Dispatchers.IO) {
        val body = JSONObject().put("enabled", enabled).toString()
        val json = JSONObject(post("/v1/notify/settings", body))
        AgentNotifyStatus(
            json.optBoolean("configured", false),
            json.optString("topic"),
            json.optBoolean("enabled", enabled),
        )
      }

  /**
   * A JPEG of the Mac's main display.
   *
   * Returns the bytes rather than a bitmap so this file stays free of Android graphics, and throws
   * [AgentUnavailableException] on the 503 that means macOS refused -- which is a sentence the user
   * can act on ("grant Screen Recording"), not a network error.
   */
  public suspend fun screen(
      width: Int = SCREEN_DEFAULT_WIDTH,
      region: Derive.PeekRegion = Derive.PeekRegion.Full,
  ): ByteArray =
      withContext(Dispatchers.IO) {
        val clamped = width.coerceIn(SCREEN_MIN_WIDTH, SCREEN_MAX_WIDTH)
        // Locale.ROOT: a comma decimal separator would be a 400 from the agent.
        val crop =
            if (region.isFull) ""
            else
                String.format(
                    Locale.ROOT,
                    "&x=%.4f&y=%.4f&w=%.4f&h=%.4f",
                    region.x,
                    region.y,
                    region.w,
                    region.h)
        getBytes("/v1/screen?width=$clamped$crop")
      }

  /**
   * Runs a command and hands back every line as the Mac produces it.
   *
   * The whole point of the endpoint: a `bazel build` that takes four minutes shows its first line
   * in under a second instead of nothing at all until it ends. [onLine] is called on an IO thread,
   * so the caller is responsible for getting onto the main one before touching UI state.
   *
   * There is no cancellation flag to poll. Stop closes the socket through [handle], the read
   * throws, and the agent -- which is watching for exactly that -- kills the process group.
   */
  public suspend fun execStream(
      kind: ExecKind,
      command: String,
      timeoutSeconds: Int = 0,
      handle: ExecStreamHandle = ExecStreamHandle(),
      onLine: (String, String) -> Unit,
  ): ExecResult =
      withContext(Dispatchers.IO) {
        val body =
            JSONObject().put("kind", kind.wire).put("command", command).apply {
              if (timeoutSeconds > 0) put("timeout_seconds", timeoutSeconds)
            }
        streamLines("/v1/exec/stream", body.toString(), handle, onLine)
      }

  /**
   * POSTs [body] to an endpoint that answers with `line` and `exit` events, and reads it to the
   * end. Runs on the caller's (IO) thread; [onLine] is called on it too.
   */
  private fun streamLines(
      path: String,
      body: String,
      handle: ExecStreamHandle,
      onLine: (String, String) -> Unit,
  ): ExecResult {
    val conn = URL(base + path).openConnection() as HttpURLConnection
    handle.attach(conn)
    var exitCode = STREAM_NO_EXIT
    var durationMs = 0
    val parser = SseParser()
    val consume = { event: SseEvent ->
      when (event.name) {
        "line" -> {
          val o = runCatching { JSONObject(event.data) }.getOrNull()
          if (o != null) onLine(o.optString("stream", "stdout"), o.optString("text"))
        }
        "exit" -> {
          val o = runCatching { JSONObject(event.data) }.getOrNull()
          if (o != null) {
            exitCode = o.optInt("exit_code", STREAM_NO_EXIT)
            durationMs = o.optInt("duration_ms", 0)
          }
        }
        else -> Unit
      }
    }
    try {
      conn.connectTimeout = CONNECT_TIMEOUT_MS
      // No read timeout: a keepalive comment arrives every 15 s while a
      // command is quiet, but a read deadline here would cut off a long
      // build the moment the agent had nothing to say.
      conn.readTimeout = 0
      conn.requestMethod = "POST"
      conn.doOutput = true
      conn.setRequestProperty("Accept", "text/event-stream")
      conn.setRequestProperty("Content-Type", "application/json")
      if (token.isNotBlank()) conn.setRequestProperty("Authorization", "Bearer $token")
      conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
      raiseFor(conn, path)
      conn.inputStream.reader(Charsets.UTF_8).use { reader ->
        val buffer = CharArray(STREAM_BUFFER)
        while (true) {
          val read = reader.read(buffer)
          if (read < 0) break
          parser.feed(String(buffer, 0, read), consume)
        }
      }
      parser.close(consume)
    } catch (e: java.io.IOException) {
      // A hang-up is not a failure: it is what Stop does. Anything else is.
      if (!handle.cancelled) throw e
    } finally {
      conn.disconnect()
    }
    return ExecResult(
        exitCode = exitCode,
        durationMs = durationMs,
        cancelled = handle.cancelled || exitCode == STREAM_NO_EXIT,
    )
  }

  // --- the phone bridge (v1.3) ------------------------------------------

  /**
   * Holds the phone's one outbound link open and hands back every event the agent sends.
   *
   * The same machinery as [execStream] and for the same reason: the agent replies to `POST
   * /v1/phone/link` with an event stream it never ends, and the phone reads it for as long as the
   * bridge is running. [body] arrives already encoded because the tool list belongs to the bridge,
   * not to this file -- `BridgePolicy.encodeLinkBody` builds it.
   *
   * [onEvent] runs on an IO thread. This function returns when the stream ends, however it ended:
   * the agent restarting, the tailnet dropping, or [handle] being cancelled. The caller decides
   * whether that is worth reconnecting for.
   */
  public suspend fun phoneLink(
      body: String,
      handle: ExecStreamHandle = ExecStreamHandle(),
      onEvent: (SseEvent) -> Unit,
  ): Unit =
      withContext(Dispatchers.IO) {
        val conn = URL(base + "/v1/phone/link").openConnection() as HttpURLConnection
        handle.attach(conn)
        val parser = SseParser()
        try {
          conn.connectTimeout = CONNECT_TIMEOUT_MS
          // No read deadline: `ping` arrives every 20 s, and a link that is
          // idle because nobody on the Mac has called a tool is the normal
          // case rather than a stall.
          conn.readTimeout = 0
          conn.requestMethod = "POST"
          conn.doOutput = true
          conn.setRequestProperty("Accept", "text/event-stream")
          conn.setRequestProperty("Content-Type", "application/json")
          if (token.isNotBlank()) conn.setRequestProperty("Authorization", "Bearer $token")
          conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
          raiseFor(conn, "/v1/phone/link")
          conn.inputStream.reader(Charsets.UTF_8).use { reader ->
            val buffer = CharArray(STREAM_BUFFER)
            while (true) {
              val read = reader.read(buffer)
              if (read < 0) break
              parser.feed(String(buffer, 0, read), onEvent)
            }
          }
          parser.close(onEvent)
        } catch (e: java.io.IOException) {
          // Stopping the bridge closes the socket, which is an IOException on
          // a thread blocked in read(). That is the Stop button working.
          if (!handle.cancelled) throw e
        } finally {
          conn.disconnect()
        }
      }

  /**
   * Answers one `call` event.
   *
   * A 404 means the agent has forgotten the id -- the Mac-side caller timed out, or a newer link
   * replaced ours mid-call. Swallowed rather than raised: there is nothing left to answer and
   * nothing the phone could do about it, and a thrown exception here would tear down a link that is
   * otherwise healthy.
   */
  public suspend fun phoneResult(
      id: String,
      text: String,
      isError: Boolean,
      imageBase64: String? = null,
      imageMimeType: String = BridgePolicy.JPEG,
  ): Unit =
      withContext<Unit>(Dispatchers.IO) {
        runCatching {
          post(
              "/v1/phone/result",
              BridgePolicy.encodeResult(id, text, isError, imageBase64, imageMimeType),
              readTimeoutMs = ACTION_TIMEOUT_MS,
          )
        }
      }

  /** `GET /v1/phone`: what the agent believes about the link, from the other end. */
  public suspend fun phone(): AgentPhoneLink =
      withContext(Dispatchers.IO) { parsePhone(get("/v1/phone")) }

  // --- transport --------------------------------------------------------

  private fun get(path: String, readTimeoutMs: Int = READ_TIMEOUT_MS): String {
    val conn = URL(base + path).openConnection() as HttpURLConnection
    try {
      conn.connectTimeout = CONNECT_TIMEOUT_MS
      conn.readTimeout = readTimeoutMs
      conn.requestMethod = "GET"
      conn.setRequestProperty("Accept", "application/json")
      if (token.isNotBlank()) conn.setRequestProperty("Authorization", "Bearer $token")
      raiseFor(conn, path)
      return conn.inputStream.bufferedReader().use { it.readText() }
    } finally {
      conn.disconnect()
    }
  }

  /** The one endpoint that answers with something other than JSON. */
  private fun getBytes(path: String): ByteArray {
    val conn = URL(base + path).openConnection() as HttpURLConnection
    try {
      conn.connectTimeout = CONNECT_TIMEOUT_MS
      // A screenshot is `screencapture` plus `sips`, which is a second or two
      // of real work on the Mac -- the dashboard read timeout would fail it
      // while it was succeeding.
      conn.readTimeout = SCREEN_TIMEOUT_MS
      conn.requestMethod = "GET"
      conn.setRequestProperty("Accept", "image/jpeg")
      if (token.isNotBlank()) conn.setRequestProperty("Authorization", "Bearer $token")
      raiseFor(conn, path)
      return conn.inputStream.use { it.readBytes() }
    } finally {
      conn.disconnect()
    }
  }

  private fun post(
      path: String,
      body: String,
      authenticated: Boolean = true,
      readTimeoutMs: Int = READ_TIMEOUT_MS,
  ): String {
    val conn = URL(base + path).openConnection() as HttpURLConnection
    try {
      conn.connectTimeout = CONNECT_TIMEOUT_MS
      conn.readTimeout = readTimeoutMs
      conn.requestMethod = "POST"
      conn.doOutput = true
      conn.setRequestProperty("Accept", "application/json")
      conn.setRequestProperty("Content-Type", "application/json")
      if (authenticated && token.isNotBlank()) {
        conn.setRequestProperty("Authorization", "Bearer $token")
      }
      conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
      raiseFor(conn, path)
      return conn.inputStream.bufferedReader().use { it.readText() }
    } finally {
      conn.disconnect()
    }
  }

  /**
   * Turns a status code into the right kind of failure.
   *
   * 401 and 403 get their own exception because they are the only ones the user can do something
   * about: everything else means the Mac is not answering, and this one means the phone has not
   * been let in. The body's `error` message is carried through, because a bare status code tells
   * nobody anything actionable.
   */
  private fun raiseFor(conn: HttpURLConnection, path: String) {
    val code = conn.responseCode
    if (code == HttpURLConnection.HTTP_OK) return
    if (code == HttpURLConnection.HTTP_UNAUTHORIZED || code == HttpURLConnection.HTTP_FORBIDDEN) {
      throw AgentAuthException("not paired (HTTP $code)")
    }
    val error =
        runCatching { conn.errorStream?.bufferedReader()?.use { it.readText() } }.getOrNull()
    val document = error?.let { runCatching { JSONObject(it) }.getOrNull() }
    if (code == HttpURLConnection.HTTP_NOT_FOUND) {
      val detail = document?.optString("error").orEmpty()
      throw AgentNotFoundException(detail.ifBlank { "agent: HTTP 404 for $path" })
    }
    // 503 is the Mac saying no for a reason the user can fix -- Screen
    // Recording is not granted -- rather than the network failing. It carries
    // `available:false` and a reason, and both must survive to the screen.
    if (code == HTTP_UNAVAILABLE) {
      val reason = document?.optString("reason").orEmpty()
      throw AgentUnavailableException(
          reason.ifBlank { "the agent cannot serve this, and it did not say why" })
    }
    val detail = document?.optString("error").orEmpty()
    throw AgentRequestException(
        code, detail, if (detail.isBlank()) "agent: HTTP $code for $path" else "agent: $detail")
  }

  /** An exec's read timeout has to outlast the command the Mac is running, plus a beat. */
  private fun execReadTimeout(timeoutSeconds: Int): Int =
      (if (timeoutSeconds > 0) timeoutSeconds else DEFAULT_EXEC_TIMEOUT_S) * 1000 +
          EXEC_TIMEOUT_SLACK_MS

  public companion object {
    private const val CONNECT_TIMEOUT_MS = 1500
    private const val READ_TIMEOUT_MS = 1500
    private const val DEFAULT_EXEC_TIMEOUT_S = 60
    private const val EXEC_TIMEOUT_SLACK_MS = 2000
    public const val DEFAULT_PORT: Int = 7411

    /** `HttpURLConnection` has no constant for 503. */
    private const val HTTP_UNAVAILABLE = 503

    /** `/v1/claude/resume` is bounded at 300 s on the agent; outlast it by a beat. */
    private const val RESUME_TIMEOUT_MS = 305_000

    /** A `gh pr merge` is a network round trip on the Mac's side too. */
    private const val ACTION_TIMEOUT_MS = 30_000
    /** The agent allows HomeSpeaker 45 s for a volume change; wait a little longer than that. */
    private const val VOLUME_TIMEOUT_MS = 50_000
    private const val SCREEN_TIMEOUT_MS = 10_000
    /** `/v1/claude/permissions/decide` refuses a longer deny message. */
    private const val DENY_MESSAGE_MAX = 300
    private const val SCREEN_DEFAULT_WIDTH = 800
    private const val SCREEN_MIN_WIDTH = 200
    private const val SCREEN_MAX_WIDTH = 1600
    private const val STREAM_BUFFER = 4096

    /** No `exit` event arrived: the stream ended without the agent saying how. */
    private const val STREAM_NO_EXIT = -1

    /**
     * Accepts what a person types - `100.124.228.116`, `atlas.coati-koi.ts.net:7411`,
     * `http://atlas:7411/` - and produces a base URL with a scheme and a port and no trailing
     * slash. The port default matches the agent's.
     */
    public fun normalize(input: String): String {
      // ALL whitespace, not just the ends: a phone keyboard auto-inserts a
      // space after "100." and a host can never legitimately contain one.
      var s = input.filterNot { it.isWhitespace() }.trimEnd('/')
      if (!s.startsWith("http://") && !s.startsWith("https://")) s = "http://$s"
      val afterScheme = s.substringAfter("://")
      if (!afterScheme.contains(':')) s = "$s:$DEFAULT_PORT"
      return s
    }

    public fun parseMetrics(json: String): AgentMetrics {
      val o = JSONObject(json)
      val cpu = o.getJSONObject("cpu")
      val mem = o.getJSONObject("memory")
      val bat = o.getJSONObject("battery")
      val disk = o.getJSONObject("disk")
      val net = o.getJSONObject("network")
      val th = o.getJSONObject("thermal")
      val un = o.optJSONObject("unavailable")
      return AgentMetrics(
          cpuReady = cpu.optBoolean("ready", false),
          cpuBusyPercent = cpu.optDouble("busy_percent", 0.0),
          load1 = cpu.optDouble("load_1", 0.0),
          memoryUsedBytes = mem.optLong("used_bytes", 0L),
          memoryTotalBytes = mem.optLong("total_bytes", 0L),
          memoryFreePercent = mem.optInt("free_percent", 0),
          batteryPresent = bat.optBoolean("present", false),
          batteryPercent = bat.optInt("percent", 0),
          onAc = bat.optBoolean("on_ac", false),
          charging = bat.optBoolean("charging", false),
          batteryTemperatureC = bat.optNullableDouble("temperature_c"),
          drawWatts = bat.optDouble("draw_watts", 0.0),
          systemWatts = bat.optNullableDouble("system_watts"),
          diskUsedPercent = disk.optDouble("used_percent", 0.0),
          diskUsedBytes = disk.optLong("used_bytes", 0L),
          diskAvailableBytes = disk.optLong("available_bytes", 0L),
          diskTotalBytes = disk.optLong("total_bytes", 0L),
          rxBytesPerSec = net.optDouble("rx_bytes_per_sec", 0.0),
          txBytesPerSec = net.optDouble("tx_bytes_per_sec", 0.0),
          throttled = th.optBoolean("throttled", false),
          cpuSpeedLimitPercent = th.optInt("cpu_speed_limit_percent", 100),
          uptimeSeconds = o.optLong("uptime_seconds", 0L),
          unavailable = un?.keys()?.asSequence()?.toSet() ?: emptySet(),
      )
    }

    public fun parseHost(json: String): AgentHost {
      val o = JSONObject(json)
      return AgentHost(
          hostname = o.optString("hostname"),
          model = o.optString("model"),
          chip = o.optString("chip"),
          cores = o.optInt("cores"),
          memoryBytes = o.optLong("memory_bytes"),
          osVersion = o.optString("os_version"),
          agentVersion = o.optString("agent_version"),
          macAddress = o.optString("mac_address"),
          wakeOnLan = o.optBoolean("wake_on_lan", false),
      )
    }

    public fun parseProcesses(json: String): List<AgentProcess> =
        JSONObject(json).optJSONArray("processes").mapObjects {
          AgentProcess(
              name = it.optString("name"),
              cpuPercent = it.optDouble("cpu_percent", 0.0),
              memoryBytes = it.optLong("memory_bytes", 0L),
          )
        }

    public fun parseTools(json: String): AgentTools {
      val t = JSONObject(json).optJSONObject("tools") ?: JSONObject()
      val out = mutableMapOf<String, AgentTool>()
      for (k in t.keys()) {
        val v = t.optJSONObject(k) ?: continue
        out[k] = AgentTool(v.optBoolean("available", false), v.optString("path"))
      }
      return AgentTools(out)
    }

    public fun parseAntigravity(json: String): AgentAntigravity {
      val o = JSONObject(json)
      return AgentAntigravity(
          available = o.optBoolean("available", false),
          reason = o.optString("reason"),
          version = o.optString("version"),
          models =
              o.optJSONArray("models").mapObjects { it.optString("id") to it.optString("label") },
          agents =
              (o.optJSONArray("agents") ?: JSONArray()).let { a ->
                (0 until a.length()).map { a.optString(it) }
              },
      )
    }

    public fun parseSpeakerVolume(json: String): AgentSpeakerVolume {
      val o = JSONObject(json)
      return AgentSpeakerVolume(
          available = o.optBoolean("available", false),
          reason = o.optString("reason"),
          speaker = o.optString("speaker"),
          percent = o.optInt("percent", 0),
          muted = o.optBoolean("muted", false),
          online = o.optBoolean("online", false),
      )
    }

    public fun parseHomeSpeaker(json: String): AgentHomeSpeaker {
      val o = JSONObject(json)
      val quiet = o.optJSONObject("quiet_hours")
      val last = o.optJSONObject("last")
      return AgentHomeSpeaker(
          available = o.optBoolean("available", false),
          reason = o.optString("reason"),
          installed = o.optBoolean("installed", false),
          appRunning = o.optBoolean("app_running", false),
          signedIn = o.optBoolean("signed_in", false),
          enabled = o.optBoolean("enabled", false),
          defaultTarget = o.optString("default_target"),
          speechLength = o.optString("speech_length").ifBlank { "summary" },
          // An agent older than v1.4.1 omits both: read as the app's own defaults.
          pauseMedia = o.optBoolean("pause_media", false),
          pauseMediaExtraSeconds = o.optDouble("pause_media_extra_seconds", 1.0),
          // Absent from an agent older than v1.5: the app's own defaults.
          announceVolumeEnabled = o.optBoolean("announce_volume_enabled", false),
          announceVolume = o.optInt("announce_volume", 60),
          // Absent from an agent older than v1.8: null, so the switches are hidden.
          speakHome = if (o.has("speak_home")) o.optBoolean("speak_home", true) else null,
          speakLocal = if (o.has("speak_local")) o.optBoolean("speak_local", false) else null,
          localVoice = o.optString("local_voice"),
          localVoiceName = o.optString("local_voice_name"),
          structureName = o.optString("structure_name"),
          quietHoursEnabled = quiet?.optBoolean("enabled", false) ?: false,
          quietHoursStart = quiet?.optString("start").orEmpty(),
          quietHoursEnd = quiet?.optString("end").orEmpty(),
          targets =
              o.optJSONArray("targets").mapObjects {
                AgentSpeakerTarget(
                    key = it.optString("key"),
                    name = it.optString("name"),
                    room = it.optString("room"),
                    type = it.optString("type"),
                    selected = it.optBoolean("selected", false),
                )
              },
          last =
              last?.let {
                AgentLastBroadcast(
                    text = it.optString("text"),
                    target = it.optString("target"),
                    source = it.optString("source"),
                    at = it.optString("at"),
                )
              },
      )
    }

    public fun parseOllama(json: String): AgentOllama {
      val o = JSONObject(json)
      return AgentOllama(
          available = o.optBoolean("available", false),
          reason = o.optString("reason"),
          models =
              o.optJSONArray("models").mapObjects {
                AgentOllamaModel(
                    name = it.optString("name"),
                    sizeBytes = it.optLong("size_bytes", 0L),
                    modified = it.optString("modified"),
                )
              },
          running =
              o.optJSONArray("running").mapObjects {
                AgentOllamaLoaded(
                    name = it.optString("name"),
                    sizeBytes = it.optLong("size_bytes", 0L),
                    processor = it.optString("processor"),
                    context = it.optInt("context"),
                    until = it.optString("until"),
                )
              },
      )
    }

    public fun parseVms(json: String): AgentList<AgentVm> {
      val o = JSONObject(json)
      return AgentList(
          available = o.optBoolean("available", false),
          reason = o.optString("reason"),
          items =
              o.optJSONArray("vms").mapObjects {
                AgentVm(
                    name = it.optString("name"),
                    status = it.optString("status"),
                    vmType = it.optString("vm_type"),
                    cpus = it.optInt("cpus"),
                    memoryBytes = it.optLong("memory_bytes", 0L),
                    diskBytes = it.optLong("disk_bytes", 0L),
                    arch = it.optString("arch"),
                )
              },
      )
    }

    public fun parseContainers(json: String): AgentList<AgentContainer> {
      val o = JSONObject(json)
      return AgentList(
          available = o.optBoolean("available", false),
          reason = o.optString("reason"),
          items =
              o.optJSONArray("containers").mapObjects {
                AgentContainer(
                    name = it.optString("name"),
                    image = it.optString("image"),
                    status = it.optString("status"),
                )
              },
          detail = o.optString("runtime"),
      )
    }

    public fun parseK8s(json: String): AgentList<AgentNode> {
      val o = JSONObject(json)
      return AgentList(
          available = o.optBoolean("available", false),
          reason = o.optString("reason"),
          items =
              o.optJSONArray("nodes").mapObjects { node ->
                AgentNode(
                    name = node.optString("name"),
                    ready = node.optBoolean("ready", false),
                    version = node.optString("version"),
                    roles =
                        node.optJSONArray("roles")?.let { roles ->
                          List(roles.length()) { roles.optString(it) }
                        } ?: emptyList(),
                )
              },
          detail = o.optString("context"),
      )
    }

    public fun parseAudio(json: String): AgentAudio {
      val o = JSONObject(json)
      return AgentAudio(
          volumePercent = o.optInt("volume_percent", 0),
          muted = o.optBoolean("muted", false),
      )
    }

    public fun parseSessions(json: String): AgentSessions {
      val o = JSONObject(json)
      return AgentSessions(
          sessions =
              o.optJSONArray("sessions").mapObjects {
                AgentSession(
                    project = it.optString("project"),
                    lastActive = it.optString("last_active"),
                    path = it.optString("path"),
                )
              },
          runningProcesses = o.optInt("running_processes", 0),
      )
    }

    public fun parseExec(json: String): AgentExec {
      val o = JSONObject(json)
      return AgentExec(
          exitCode = o.optInt("exit_code", 0),
          stdout = o.optString("stdout"),
          stderr = o.optString("stderr"),
          durationMs = o.optInt("duration_ms", 0),
          truncated = o.optBoolean("truncated", false),
      )
    }

    /**
     * Two documents behind one path.
     *
     * When Prometheus is configured the agent proxies its answer verbatim, so this is a real
     * Prometheus envelope; when it is not, the agent answers with its own `available:false` and a
     * reason. Distinguishing them by the presence of `data` rather than by `available` is
     * deliberate - a proxied Prometheus document has no `available` key at all, and `optBoolean`
     * would read that absence as false and hide a perfectly good result.
     */
    public fun parsePromql(json: String): AgentPromql {
      val o = JSONObject(json)
      val data = o.optJSONObject("data")
      if (data == null) {
        return AgentPromql(
            available = false,
            reason = o.optString("reason").ifBlank { "no data in the reply" },
            resultType = "",
            seriesCount = 0,
            firstValue = null,
        )
      }
      val result = data.optJSONArray("result")
      val first = result?.optJSONObject(0)
      // Instant vectors carry [timestamp, "value"]; range vectors carry a
      // list of those. Take the newest sample of whichever shape came back.
      val sample =
          first?.optJSONArray("value")
              ?: first?.optJSONArray("values")?.let { it.optJSONArray(it.length() - 1) }
      return AgentPromql(
          available = true,
          reason = "",
          resultType = data.optString("resultType"),
          series =
              (0 until (result?.length() ?: 0)).mapNotNull { i ->
                val item = result?.optJSONObject(i) ?: return@mapNotNull null
                val metric = item.optJSONObject("metric") ?: JSONObject()
                val labels = mutableMapOf<String, String>()
                for (k in metric.keys()) labels[k] = metric.optString(k)
                val v =
                    item.optJSONArray("value")
                        ?: item.optJSONArray("values")?.let { it.optJSONArray(it.length() - 1) }
                AgentSeries(labels, v?.optString(1)?.toDoubleOrNull())
              },
          seriesCount = result?.length() ?: 0,
          firstValue = sample?.optString(1)?.toDoubleOrNull(),
      )
    }

    public fun parseClaudeSessions(json: String): List<AgentClaudeSession> =
        JSONObject(json).optJSONArray("sessions").mapObjects {
          AgentClaudeSession(
              sessionId = it.optString("session_id"),
              project = it.optString("project"),
              cwd = it.optString("cwd"),
              path = it.optString("path"),
              lastActive = it.optString("last_active"),
              // "unknown" rather than "" so a session with nothing parseable
              // reads as a session the agent could not classify, not as one
              // with no state at all.
              state = it.optString("state").ifBlank { "unknown" },
              lastRole = it.optString("last_role"),
              lastText = it.optString("last_text"),
              lastTool = it.optString("last_tool"),
          )
        }

    public fun parseClaudePermissions(json: String): AgentClaudePermissions {
      val o = JSONObject(json)
      val pending =
          o.optJSONArray("pending").mapObjects {
            val expires = it.optString("expires_at")
            PendingPermission(
                id = it.optString("id"),
                sessionId = it.optString("session_id"),
                project = it.optString("project"),
                cwd = it.optString("cwd"),
                // A prompt with no tool name still needs answering; say so
                // rather than leaving the card's title blank.
                tool = it.optString("tool").ifBlank { "unknown tool" },
                summary = it.optString("summary"),
                detail = it.optString("detail"),
                createdAt = it.optString("created_at"),
                expiresAt = expires,
                expiresAtMs = epochMillis(expires),
            )
          }
      return AgentClaudePermissions(
          // Absent reads as off: an agent that does not say has not installed anything.
          enabled = o.optBoolean("enabled", false),
          waitSeconds = o.optInt("wait_seconds", 0),
          // The agent sends oldest first; sorted again here because the card
          // order is a promise the screen makes. An entry with no id is
          // dropped: there would be no way to answer it.
          pending =
              pending
                  .filter { it.id.isNotBlank() }
                  .sortedWith(compareBy({ epochMillis(it.createdAt) }, { it.createdAt })),
      )
    }

    public fun parseAntigravitySessions(json: String): AgentAntigravitySessions {
      val o = JSONObject(json)
      return AgentAntigravitySessions(
          // Absent reads as available when sessions came back: the list is the evidence.
          available = o.optBoolean("available", o.has("sessions")),
          reason = o.optString("reason"),
          sessions =
              o.optJSONArray("sessions")
                  .mapObjects {
                    AgentAntigravitySession(
                        id = it.optString("id"),
                        title = it.optString("title"),
                        preview = it.optString("preview"),
                        project = it.optString("project"),
                        steps = it.optInt("steps", 0),
                        updatedAt = it.optString("updated_at"),
                        state = it.optString("state").ifBlank { "unknown" },
                    )
                  }
                  // No id, no way to continue it.
                  .filter { it.id.isNotBlank() },
      )
    }

    /** RFC 3339 to epoch ms, 0 when unreadable. Offsets and a plain trailing Z both parse. */
    private fun epochMillis(iso: String): Long {
      val text = iso.trim()
      if (text.isEmpty()) return 0
      return runCatching { OffsetDateTime.parse(text).toInstant().toEpochMilli() }.getOrNull()
          ?: runCatching { Instant.parse(text).toEpochMilli() }.getOrNull()
          ?: 0
    }

    public fun parsePrs(json: String): AgentList<AgentPr> {
      val o = JSONObject(json)
      return AgentList(
          available = o.optBoolean("available", false),
          reason = o.optString("reason"),
          items =
              o.optJSONArray("prs").mapObjects { pr ->
                val checks = pr.optJSONObject("checks") ?: JSONObject()
                AgentPr(
                    repo = pr.optString("repo"),
                    number = pr.optInt("number"),
                    title = pr.optString("title"),
                    url = pr.optString("url"),
                    author = pr.optString("author"),
                    isDraft = pr.optBoolean("is_draft", false),
                    headRef = pr.optString("head_ref"),
                    baseRef = pr.optString("base_ref"),
                    mergeState = pr.optString("merge_state"),
                    reviewDecision = pr.optString("review_decision"),
                    checksSuccess = checks.optInt("success"),
                    checksFailure = checks.optInt("failure"),
                    checksPending = checks.optInt("pending"),
                    checksSkipped = checks.optInt("skipped"),
                    autoMerge = pr.optBoolean("auto_merge", false),
                    updatedAt = pr.optString("updated_at"),
                )
              },
          detail = o.optString("sampled_at"),
      )
    }

    public fun parseArgo(json: String): AgentList<AgentArgoApp> {
      val o = JSONObject(json)
      return AgentList(
          available = o.optBoolean("available", false),
          reason = o.optString("reason"),
          items =
              o.optJSONArray("apps").mapObjects {
                AgentArgoApp(
                    name = it.optString("name"),
                    namespace = it.optString("namespace"),
                    project = it.optString("project"),
                    sync = it.optString("sync"),
                    health = it.optString("health"),
                    revision = it.optString("revision"),
                    lastSynced = it.optString("last_synced"),
                    message = it.optString("message"),
                )
              },
      )
    }

    public fun parseAction(json: String): AgentActionResult {
      val o = JSONObject(json)
      return AgentActionResult(o.optBoolean("ok", false), o.optString("output"))
    }

    /**
     * `/healthz`'s new `notify` object.
     *
     * Absent on a v1.1 agent, which is not an error: it reads as "not configured", which is exactly
     * what an agent with no ntfy flags is.
     */
    public fun parseNotifyStatus(json: String): AgentNotifyStatus {
      val n = JSONObject(json).optJSONObject("notify") ?: return AgentNotifyStatus(false, "")
      // enabled defaults TRUE: an agent built before the switch existed omits the field and was
      // publishing, so reading its silence as "muted" would invent a state it is not in.
      return AgentNotifyStatus(
          n.optBoolean("configured", false),
          n.optString("topic"),
          n.optBoolean("enabled", true),
      )
    }

    /**
     * `GET /v1/phone`: the link as the AGENT sees it.
     *
     * Worth asking for even though the phone is the one holding the socket: a link this phone
     * thinks is up and the agent has already replaced is indistinguishable from a healthy one from
     * here, and the difference is whether tool calls arrive at all.
     */
    public fun parsePhone(json: String): AgentPhoneLink {
      val o = JSONObject(json)
      val device = o.optJSONObject("device")
      val tools = o.optJSONArray("tools")
      return AgentPhoneLink(
          connected = o.optBoolean("connected", false),
          since = o.optString("since"),
          model = device?.optString("model").orEmpty(),
          tools = (0 until (tools?.length() ?: 0)).mapNotNull { tools?.optString(it) },
          trustUntil = o.optString("trust_until").takeIf { it.isNotBlank() && it != "null" },
      )
    }

    /** `JSONArray` predates the collections API by two decades and iterates like it. */
    private fun <T> JSONArray?.mapObjects(build: (JSONObject) -> T): List<T> {
      val array = this ?: return emptyList()
      return (0 until array.length()).mapNotNull { array.optJSONObject(it)?.let(build) }
    }
  }
}

/**
 * A number the agent may send as JSON `null`, or leave out, meaning "no reading".
 *
 * `optDouble(key, 0.0)` turned both into a confident zero -- which is how a Mac with no battery
 * sensor reading came out as "battery 0°". NaN is folded in too, because `optDouble` returns it for
 * anything it cannot parse as a number.
 */
internal fun JSONObject.optNullableDouble(key: String): Double? {
  if (!has(key) || isNull(key)) return null
  return optDouble(key).takeUnless { it.isNaN() }
}
