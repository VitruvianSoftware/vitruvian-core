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
    val batteryTemperatureC: Double,
    val drawWatts: Double,
    val diskUsedPercent: Double,
    val diskUsedBytes: Long,
    val diskAvailableBytes: Long,
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

/** Whether the agent has somewhere to publish notifications, from `/healthz`. */
public data class AgentNotifyStatus(val configured: Boolean, val topic: String)

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
        val conn = URL(base + "/v1/exec/stream").openConnection() as HttpURLConnection
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
          conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
          raiseFor(conn, "/v1/exec/stream")
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
        ExecResult(
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
  public suspend fun phoneResult(id: String, text: String, isError: Boolean): Unit =
      withContext<Unit>(Dispatchers.IO) {
        runCatching {
          post(
              "/v1/phone/result",
              BridgePolicy.encodeResult(id, text, isError),
              readTimeoutMs = ACTION_TIMEOUT_MS,
          )
        }
      }

  /** `GET /v1/phone`: what the agent believes about the link, from the other end. */
  public suspend fun phone(): AgentPhoneLink =
      withContext(Dispatchers.IO) { parsePhone(get("/v1/phone")) }

  // --- transport --------------------------------------------------------

  private fun get(path: String): String {
    val conn = URL(base + path).openConnection() as HttpURLConnection
    try {
      conn.connectTimeout = CONNECT_TIMEOUT_MS
      conn.readTimeout = READ_TIMEOUT_MS
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
    // 503 is the Mac saying no for a reason the user can fix -- Screen
    // Recording is not granted -- rather than the network failing. It carries
    // `available:false` and a reason, and both must survive to the screen.
    if (code == HTTP_UNAVAILABLE) {
      val reason = document?.optString("reason").orEmpty()
      throw AgentUnavailableException(
          reason.ifBlank { "the agent cannot serve this, and it did not say why" })
    }
    val detail = document?.optString("error").orEmpty()
    throw IllegalStateException(
        if (detail.isBlank()) "agent: HTTP $code for $path" else "agent: $detail")
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
    private const val SCREEN_TIMEOUT_MS = 10_000
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
          batteryTemperatureC = bat.optDouble("temperature_c", 0.0),
          drawWatts = bat.optDouble("draw_watts", 0.0),
          diskUsedPercent = disk.optDouble("used_percent", 0.0),
          diskUsedBytes = disk.optLong("used_bytes", 0L),
          diskAvailableBytes = disk.optLong("available_bytes", 0L),
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
      return AgentNotifyStatus(n.optBoolean("configured", false), n.optString("topic"))
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
