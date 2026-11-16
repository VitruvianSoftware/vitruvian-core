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

package dev.vitruvian.crashprivacy

import io.sentry.DataCollection
import io.sentry.KeyValueCollectionBehavior
import io.sentry.Sentry
import io.sentry.SentryOpenTelemetryMode
import io.sentry.SentryOptions
import io.sentry.android.core.SentryAndroidOptions
import io.sentry.protocol.Device
import io.sentry.protocol.OperatingSystem
import java.io.File
import java.util.Locale

/**
 * Device and app metadata fields that a caller may explicitly opt in to retain on crash reports.
 */
public enum class DeviceField {
  MODEL,
  SCREEN,
  MEMORY,
  OS_VERSION,
  APP_VERSION,
}

/** Caller-supplied device metadata retained only for fields enabled in [DeviceField]. */
public data class PrivateSentryDevice(
    val androidRelease: String = "",
    val model: String = "",
    val screenWidthPx: Int? = null,
    val screenHeightPx: Int? = null,
    val memorySizeBytes: Long? = null,
)

private const val SENTRY_CACHE_DIR_NAME: String = "sentry"

/** Base cache directory passed to `SentryOptions.cacheDirPath`. */
public fun sentryCacheDir(appCacheDir: File): File = File(appCacheDir, SENTRY_CACHE_DIR_NAME)

/**
 * Deletes Sentry's on-disk cache directory (`<appCacheDir>/sentry`, containing the DSN-hashed
 * envelope cache, `outbox`, `.options-cache`, `.scope-cache`, and marker files) when crash
 * reporting is disabled so previously queued reports never leave the device.
 */
public fun clearSentryCache(appCacheDir: File) {
  val target = sentryCacheDir(appCacheDir)
  if (target.exists()) {
    target.deleteRecursively()
  }
}

/**
 * Sets `options.shutdownTimeoutMillis = 0` so queued events are not flushed, closes Sentry, and
 * deletes `<appCacheDir>/sentry` right after.
 */
public fun disableCrashReporting(
    appCacheDir: File,
    options: SentryOptions = Sentry.getCurrentScopes().options,
    closeSentry: () -> Unit = { Sentry.close() },
    deleteCache: (File) -> Unit = ::clearSentryCache,
) {
  options.shutdownTimeoutMillis = 0L
  closeSentry()
  deleteCache(appCacheDir)
}

private fun createAllOffDataCollection(): DataCollection =
    DataCollection().apply {
      userInfo = false
      cookies = KeyValueCollectionBehavior.off()
      urlQueryParams = KeyValueCollectionBehavior.off()
      httpBodies = emptySet()
      databaseQueryData = false
      filePaths = false
      httpHeaders.request = KeyValueCollectionBehavior.off()
      httpHeaders.response = KeyValueCollectionBehavior.off()
      graphql.document = false
      graphql.variables = false
    }

/**
 * Configures [SentryAndroidOptions] for privacy-hardened crash reporting: disables PII,
 * breadcrumbs, server hostname, extra threads, ANR/tombstone/NDK/exit tracking, screenshots, view
 * hierarchy, tracing, profiling, replay, logs, metrics, and OTel, scrubs addresses, and strips
 * every device/OS/app field not explicitly opted into via [keepDeviceFields].
 */
public fun configurePrivateSentry(
    options: SentryAndroidOptions,
    dsn: String,
    keepDeviceFields: Set<DeviceField>,
    release: String? = null,
    environment: String = "production",
    device: PrivateSentryDevice = PrivateSentryDevice(),
    appCacheDir: File? = null,
) {
  val keptRelease =
      if (DeviceField.APP_VERSION in keepDeviceFields) {
        release?.trim()?.takeIf { it.isNotEmpty() }
      } else {
        null
      }

  options.dsn = dsn
  options.release = keptRelease
  options.environment = environment
  if (appCacheDir != null) {
    options.cacheDirPath = sentryCacheDir(appCacheDir).absolutePath
  }
  options.setDataCollection(createAllOffDataCollection())
  options.distinctId = null
  // Sentry 8.x uses DisabledQueue when maxBreadcrumbs <= 0; beforeBreadcrumb and beforeSend
  // remain as defense-in-depth.
  options.maxBreadcrumbs = 0
  options.maxFeatureFlags = 0
  options.isAttachServerName = false
  options.serverName = null
  options.isAttachThreads = false
  options.isSendModules = false
  options.isEnableAutoSessionTracking = false
  options.isSendClientReports = false

  // No breadcrumbs (disable all Android auto-breadcrumbs plus drop anything added manually).
  options.enableAllAutoBreadcrumbs(false)
  options.isEnableSystemEventBreadcrumbsExtras = false
  options.beforeBreadcrumb = SentryOptions.BeforeBreadcrumbCallback { _, _ -> null }

  // Disable Android crash/exit integrations that capture thread dumps, historical exits, or NDK.
  options.isAnrEnabled = false
  options.isAnrReportInDebug = false
  options.isReportHistoricalAnrs = false
  options.isAttachAnrThreadDump = false
  options.anrProfilingSampleRate = null
  options.isEnableNdkAppHangTracking = false
  options.isTombstoneEnabled = false
  options.isReportHistoricalTombstones = false
  options.isAttachRawTombstone = false
  options.isMemoryLimiterEnabled = false
  options.isReportHistoricalMemoryLimiterExits = false
  options.isEnableNdk = false
  options.isEnableScopeSync = false

  // Disable Android screenshot, view hierarchy, frame tracking, extra IPC/storage/root checks,
  // and shake-to-feedback dialogs.
  options.isAttachScreenshot = false
  options.isAttachViewHierarchy = false
  options.isEnableFramesTracking = false
  options.isCollectAdditionalContext = false
  options.isCollectExternalStorageContext = false
  options.isEnableRootCheck = false
  options.feedbackOptions.isUseShakeGesture = false
  options.feedbackOptions.isEnableAttachScreenshot = false

  // Leave performance tracing and profiling unset/disabled (tracesSampleRate stays null).
  options.tracesSampleRate = null
  options.tracesSampler = null
  options.isEnableAutoActivityLifecycleTracing = false
  options.isEnableActivityLifecycleTracingAutoFinish = false
  options.isEnableUserInteractionTracing = false
  options.isEnableTimeToFullDisplayTracing = false
  options.isEnablePerformanceV2 = false
  options.isEnableStandaloneAppStartTracing = false
  options.isEnableAutoTraceIdGeneration = false
  options.isEnableScreenTracking = false
  options.setTracePropagationTargets(emptyList())
  options.webViewTracing.allowedHosts = emptyList()
  options.beforeSendTransaction = SentryOptions.BeforeSendTransactionCallback { _, _ -> null }
  options.profilesSampleRate = null
  options.profilesSampler = null
  options.profileSessionSampleRate = null
  options.isStartProfilerOnAppStart = false
  options.isEnableAppStartProfiling = false

  // Disable 8.x session replay, logs, metrics, backpressure monitoring, OTel, scope persistence,
  // and spotlight.
  options.sessionReplay.sessionSampleRate = null
  options.sessionReplay.onErrorSampleRate = null
  options.sessionReplay.isTrackConfiguration = false
  options.beforeSendReplay = SentryOptions.BeforeSendReplayCallback { _, _ -> null }

  options.logs.isEnabled = false
  options.logs.beforeSend = SentryOptions.Logs.BeforeSendLogCallback { _ -> null }
  options.metrics.isEnabled = false
  options.metrics.beforeSend = SentryOptions.Metrics.BeforeSendMetricCallback { _, _ -> null }

  options.isEnableBackpressureHandling = false
  options.openTelemetryMode = SentryOpenTelemetryMode.OFF
  options.isCaptureOpenTelemetryEvents = false
  options.isEnableScopePersistence = false
  options.isEnableSpotlight = false

  val keptModel =
      if (DeviceField.MODEL in keepDeviceFields) {
        device.model.trim().takeIf { it.isNotEmpty() }
      } else {
        null
      }
  val keptOsVersion =
      if (DeviceField.OS_VERSION in keepDeviceFields) {
        device.androidRelease.trim().takeIf { it.isNotEmpty() }
      } else {
        null
      }
  val keptScreenWidth = if (DeviceField.SCREEN in keepDeviceFields) device.screenWidthPx else null
  val keptScreenHeight = if (DeviceField.SCREEN in keepDeviceFields) device.screenHeightPx else null
  val keptMemorySize = if (DeviceField.MEMORY in keepDeviceFields) device.memorySizeBytes else null

  val boundedTags = buildMap {
    keptModel?.let { put("device.model", it) }
    keptOsVersion?.let { put("os.version", it) }
  }
  options.tags.clear()
  boundedTags.forEach { (key, value) -> options.setTag(key, value) }

  options.beforeSend =
      SentryOptions.BeforeSendCallback { event, hint ->
        hint.clearAttachments()
        event.breadcrumbs = null
        // DefaultAndroidEventProcessor attaches User(id = Installation.id); drop user completely.
        event.user = null
        event.request = null
        event.serverName = null
        event.dist = null
        event.extras = null
        event.debugMeta = null
        if (DeviceField.APP_VERSION in keepDeviceFields) {
          if (keptRelease != null) {
            event.release = keptRelease
          }
        } else {
          event.release = null
        }
        event.tags = if (boundedTags.isEmpty()) null else HashMap(boundedTags)
        if (event.threads != null) {
          event.threads = null
        }
        event.exceptions?.forEach { exception ->
          exception.value = exception.value?.let(::scrubCrashMessage)
        }
        event.message?.let { msg ->
          msg.formatted = msg.formatted?.let(::scrubCrashMessage)
          msg.message = msg.message?.let(::scrubCrashMessage)
          msg.params = msg.params?.map { param -> param?.let(::scrubCrashMessage) }
        }
        event.contexts.clear()
        if (keptOsVersion != null) {
          event.contexts.setOperatingSystem(
              OperatingSystem().apply {
                name = "Android"
                version = keptOsVersion
              })
        }
        if (keptModel != null ||
            keptScreenWidth != null ||
            keptScreenHeight != null ||
            keptMemorySize != null) {
          event.contexts.setDevice(
              Device().apply {
                model = keptModel
                screenWidthPixels = keptScreenWidth
                screenHeightPixels = keptScreenHeight
                memorySize = keptMemorySize
              })
        }
        event
      }
}

private const val ADDRESS_PLACEHOLDER: String = "<address>"

private val URL_REGEX = Regex("""(?<![A-Za-z0-9+.-])[A-Za-z][A-Za-z0-9+.-]*://[^\s"'<>]+""")

private val UNABLE_TO_RESOLVE_HOST_REGEX =
    Regex("""(?i)(unable to resolve host\s+["'])([^"']+)(["'])""")

private val SLASH_SOCKET_ADDR_REGEX =
    Regex(
        """(^|[\s"'(\[{,=])(?:[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?)?/(\[[0-9A-Fa-f:.]+(?:%[A-Za-z0-9._-]+)?\](?::\d{1,5})?|[0-9A-Fa-f:.]+(?:%[A-Za-z0-9._-]+)?)(?![A-Za-z0-9_]|(?:\.\d))""",
    )

private val BRACKETED_IPV6_REGEX =
    Regex("""\[([0-9A-Fa-f:.]+)(?:%[A-Za-z0-9._-]+)?\](?::(\d{1,5}))?""")

private val BARE_IPV6_REGEX =
    Regex(
        """(?<![A-Za-z0-9_:])([0-9A-Fa-f:]+(?:\.\d{1,3}){0,3})(?:%[A-Za-z0-9._-]+)?(?![A-Za-z0-9_])""")

private val IPV4_WITH_OPTIONAL_PORT_REGEX =
    Regex(
        """(?<![A-Za-z0-9_]|(?:\d\.))(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?(?![A-Za-z0-9_]|(?:\.\d))""")

private val HOST_PORT_REGEX =
    Regex(
        """(?<![A-Za-z0-9_/:.<>-])([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*):([1-9]\d{0,4})(?![A-Za-z0-9_:])""",
    )

private val DOTTED_HOSTNAME_REGEX =
    Regex(
        """(?<![A-Za-z0-9_/:.<>-])([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+)(?![A-Za-z0-9_>-])""",
    )

private val NON_HOST_FILE_EXTENSIONS =
    setOf(
        "kt",
        "kts",
        "java",
        "rs",
        "ts",
        "tsx",
        "js",
        "jsx",
        "mjs",
        "cjs",
        "py",
        "go",
        "swift",
        "c",
        "cc",
        "cpp",
        "h",
        "hpp",
        "m",
        "mm",
        "xml",
        "json",
        "yaml",
        "yml",
        "toml",
        "md",
        "txt",
        "gradle",
        "bzl",
        "bazel",
        "sh",
    )

private val BARE_RUNTIME_PACKAGES =
    setOf(
        "java.io",
        "kotlin.io",
        "kotlinx.io",
        "java.net",
        "javax.net",
        "android.net",
        "android.app",
        "io.sentry",
    )

private val HOSTNAME_TLDS =
    setOf(
        "local",
        "lan",
        "arpa",
        "internal",
        "intranet",
        "corp",
        "private",
        "localdomain",
        "home",
        "box",
        "localhost",
        "test",
        "example",
        "invalid",
        "net",
        "com",
        "org",
        "edu",
        "gov",
        "mil",
        "int",
        "dev",
        "app",
        "cloud",
        "io",
        "ai",
        "co",
        "me",
        "sh",
        "xyz",
        "info",
        "biz",
        "tech",
        "host",
        "network",
        "systems",
        "online",
        "site",
        "services",
        "digital",
        "uk",
        "de",
        "fr",
        "ca",
        "au",
        "jp",
        "eu",
        "us",
        "ch",
        "nl",
        "se",
        "no",
        "fi",
        "dk",
        "ie",
        "es",
        "it",
        "pt",
        "be",
        "at",
        "pl",
        "cz",
        "nz",
        "sg",
        "hk",
        "kr",
        "tw",
        "in",
        "br",
        "il",
        "za",
    )

private fun isValidPort(raw: String): Boolean {
  val port = raw.toIntOrNull() ?: return false
  return port in 1..65535
}

private fun isValidIpv4(raw: String): Boolean {
  val parts = raw.split('.')
  if (parts.size != 4) return false
  return parts.all { part ->
    part.isNotEmpty() &&
        part.length <= 3 &&
        (part.length == 1 || part[0] != '0') &&
        part.all(Char::isDigit) &&
        part.toInt() in 0..255
  }
}

private fun isHexGroup(raw: String): Boolean =
    raw.length in 1..4 && raw.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }

private fun isValidIpv6(raw: String): Boolean {
  if (raw.count { it == ':' } < 2) return false
  if (raw.startsWith(':') && !raw.startsWith("::")) return false
  if (raw.endsWith(':') && !raw.endsWith("::")) return false
  val halves = raw.split("::", limit = 3)
  if (halves.size > 2) return false
  val hasCompression = halves.size == 2
  val left =
      if (halves[0].isEmpty()) {
        if (hasCompression) emptyList() else return false
      } else {
        halves[0].split(':')
      }
  val right =
      if (!hasCompression) {
        emptyList()
      } else if (halves[1].isEmpty()) {
        emptyList()
      } else {
        halves[1].split(':')
      }
  val groups = left + right
  if (groups.isEmpty()) return false
  if (raw.startsWith("::") && right.size == 1 && '.' !in right[0] && !right[0].all(Char::isDigit)) {
    return false
  }
  var count = 0
  for (index in groups.indices) {
    val group = groups[index]
    if (group.isEmpty()) return false
    if ('.' in group) {
      if (index != groups.lastIndex || !isValidIpv4(group)) return false
      count += 2
    } else {
      if (!isHexGroup(group)) return false
      count += 1
    }
  }
  return if (hasCompression) count < 8 else count == 8
}

private fun isValidSocketAddressTarget(raw: String): Boolean {
  if (raw.startsWith("[")) {
    val closeIdx = raw.indexOf(']')
    if (closeIdx <= 1) return false
    val addr = raw.substring(1, closeIdx).substringBefore('%')
    val rest = raw.substring(closeIdx + 1)
    val portValid = rest.isEmpty() || (rest.startsWith(':') && isValidPort(rest.substring(1)))
    return portValid && isValidIpv6(addr)
  }
  val withoutZone = raw.substringBefore('%')
  if (withoutZone.count { it == ':' } == 1 && '.' in withoutZone) {
    val hostPart = withoutZone.substringBefore(':')
    val portPart = withoutZone.substringAfter(':')
    return isValidIpv4(hostPart) && isValidPort(portPart)
  }
  return isValidIpv4(withoutZone) || isValidIpv6(withoutZone)
}

/**
 * Replaces URLs, IPv4/IPv6 literals, host:port pairs, and dotted hostnames with `<address>` while
 * leaving ordinary Java/Kotlin exception and package names untouched.
 */
public fun scrubCrashMessage(message: String): String {
  var result =
      URL_REGEX.replace(message) { match ->
        var core = match.value
        var suffix = ""
        while (core.isNotEmpty()) {
          val tail = core.last()
          val shouldTrim = tail in ".,;!?)}" || tail == ':' || (tail == ']' && '[' !in core)
          if (!shouldTrim) break
          suffix = tail + suffix
          core = core.dropLast(1)
        }
        if (core.endsWith("://")) match.value else "$ADDRESS_PLACEHOLDER$suffix"
      }

  result =
      UNABLE_TO_RESOLVE_HOST_REGEX.replace(result) { match ->
        "${match.groupValues[1]}$ADDRESS_PLACEHOLDER${match.groupValues[3]}"
      }

  result =
      SLASH_SOCKET_ADDR_REGEX.replace(result) { match ->
        var target = match.groupValues[2]
        var suffix = ""
        while (target.endsWith('.')) {
          suffix = "." + suffix
          target = target.dropLast(1)
        }
        if (target.endsWith(':') && !target.endsWith("::") && !isValidSocketAddressTarget(target)) {
          suffix = ":" + suffix
          target = target.dropLast(1)
        }
        if (isValidSocketAddressTarget(target)) {
          "${match.groupValues[1]}$ADDRESS_PLACEHOLDER$suffix"
        } else {
          match.value
        }
      }

  result =
      BRACKETED_IPV6_REGEX.replace(result) { match ->
        val addr = match.groupValues[1]
        val port = match.groupValues[2]
        if (isValidIpv6(addr) && (port.isEmpty() || isValidPort(port))) {
          ADDRESS_PLACEHOLDER
        } else {
          match.value
        }
      }

  result =
      BARE_IPV6_REGEX.replace(result) { match ->
        var addr = match.groupValues[1]
        var suffix = ""
        if (addr.endsWith(':') && !addr.endsWith("::") && !isValidIpv6(addr)) {
          suffix = ":"
          addr = addr.dropLast(1)
        }
        if (isValidIpv6(addr)) "$ADDRESS_PLACEHOLDER$suffix" else match.value
      }

  result =
      IPV4_WITH_OPTIONAL_PORT_REGEX.replace(result) { match ->
        val ip = match.groupValues[1]
        val port = match.groupValues[2]
        when {
          !isValidIpv4(ip) -> match.value
          port.isEmpty() || isValidPort(port) -> ADDRESS_PLACEHOLDER
          else -> "$ADDRESS_PLACEHOLDER:$port"
        }
      }

  result =
      HOST_PORT_REGEX.replace(result) { match ->
        val host = match.groupValues[1]
        val port = match.groupValues[2]
        val labels = host.split('.')
        val isSourceFile =
            labels.size == 2 && labels[1].lowercase(Locale.ROOT) in NON_HOST_FILE_EXTENSIONS
        if (host.length <= 253 &&
            host.any { it in 'A'..'Z' || it in 'a'..'z' } &&
            isValidPort(port) &&
            !isSourceFile) {
          ADDRESS_PLACEHOLDER
        } else {
          match.value
        }
      }

  result =
      DOTTED_HOSTNAME_REGEX.replace(result) { match ->
        val candidate = match.groupValues[1]
        val labels = candidate.split('.')
        val last = labels.last()
        val tld = last.lowercase(Locale.ROOT)
        val hasTypeSuffix = labels.any { it.endsWith("Exception") || it.endsWith("Error") }
        val validTldCase = last == tld || last == tld.uppercase(Locale.ROOT)
        if (candidate.length <= 253 &&
            candidate !in BARE_RUNTIME_PACKAGES &&
            !hasTypeSuffix &&
            validTldCase &&
            tld in HOSTNAME_TLDS) {
          ADDRESS_PLACEHOLDER
        } else {
          match.value
        }
      }

  return result
}
