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

import io.sentry.Sentry
import io.sentry.SentryOptions
import io.sentry.protocol.Device
import io.sentry.protocol.OperatingSystem
import io.sentry.protocol.SentryRuntime
import java.io.File
import java.util.Locale

/** Sub-pages inside `Screen.About`. */
public enum class AboutPage(public val title: String) {
  Main("About"),
  Privacy("Privacy"),
  License("License"),
  OpenSourceLicenses("Open-source licenses"),
}

/** One open-source library or typeface credited on the Open-source licenses screen. */
public data class OpenSourceLicense(
    val name: String,
    val detail: String,
    val license: String,
    val mavenTargets: Set<String> = emptySet(),
)

/**
 * Static identity, URLs, open-source notices, and pure helpers shared between the About / Privacy
 * screens, Sentry initialization, and JVM tests.
 */
public object AppInfo {
  public const val name: String = "Vitruvian Remote"
  public const val tagline: String =
      "A remote for your Mac: trackpad, keyboard, and a view of what it is doing."
  public const val copyrightNotice: String = "© 2026 VitruvianSoftware · MIT License"
  public const val repositoryURL: String = "https://github.com/VitruvianSoftware/vitruvian-remote"
  public const val repositoryLabel: String = "github.com/VitruvianSoftware/vitruvian-remote"
  public const val issuesURL: String = "$repositoryURL/issues"
  public const val websiteURL: String = "https://vitruviansoftware.dev"
  public const val donateURL: String =
      "https://vitruviansoftware.dev/donate/vitruvian-remote/?src=app-vitruvian-remote"
  public const val setupGuideURL: String = "$repositoryURL#readme"
  public const val supportBody: String =
      "Vitruvian Remote is free and open source, and it always will be. If you'd like to " +
          "support its development, you can give any amount you choose. Payments are handled " +
          "securely by Stripe."

  /**
   * All runtime `@maven` libraries across `apps/mobile/vitruvian-remote/BUILD` and
   * `packages/design-system-android/BUILD`, plus the bundled fonts from
   * `packages/design-system-android/fonts`. Checked in `AppInfoTest` so adding a new runtime
   * dependency without an attribution fails tests immediately.
   */
  public val openSourceLicenses: List<OpenSourceLicense> =
      listOf(
          OpenSourceLicense(
              name = "AndroidX Activity",
              detail = "androidx.activity:activity-compose",
              license = "Apache-2.0",
              mavenTargets = setOf("@maven//:androidx_activity_activity_compose"),
          ),
          OpenSourceLicense(
              name = "AndroidX Annotation",
              detail = "androidx.annotation:annotation",
              license = "Apache-2.0",
              mavenTargets = setOf("@maven//:androidx_annotation_annotation"),
          ),
          OpenSourceLicense(
              name = "AndroidX Compose",
              detail = "runtime, ui, foundation, animation, animation-core",
              license = "Apache-2.0",
              mavenTargets =
                  setOf(
                      "@maven//:androidx_compose_animation_animation",
                      "@maven//:androidx_compose_animation_animation_core",
                      "@maven//:androidx_compose_foundation_foundation",
                      "@maven//:androidx_compose_foundation_foundation_layout",
                      "@maven//:androidx_compose_runtime_runtime",
                      "@maven//:androidx_compose_ui_ui",
                      "@maven//:androidx_compose_ui_ui_graphics",
                      "@maven//:androidx_compose_ui_ui_text",
                      "@maven//:androidx_compose_ui_ui_unit",
                  ),
          ),
          OpenSourceLicense(
              name = "AndroidX Core",
              detail = "androidx.core:core",
              license = "Apache-2.0",
              mavenTargets = setOf("@maven//:androidx_core_core"),
          ),
          OpenSourceLicense(
              name = "AndroidX WindowManager",
              detail = "androidx.window:window, window-core",
              license = "Apache-2.0",
              mavenTargets =
                  setOf(
                      "@maven//:androidx_window_window",
                      "@maven//:androidx_window_window_core",
                  ),
          ),
          OpenSourceLicense(
              name = "Kotlin Coroutines",
              detail = "org.jetbrains.kotlinx:kotlinx-coroutines-android",
              license = "Apache-2.0",
              mavenTargets = setOf("@maven//:org_jetbrains_kotlinx_kotlinx_coroutines_android"),
          ),
          OpenSourceLicense(
              name = "Sentry SDK",
              detail = "io.sentry:sentry",
              license = "MIT",
              mavenTargets = setOf("@maven//:io_sentry_sentry"),
          ),
          OpenSourceLicense(
              name = "JetBrains Mono",
              detail = "The JetBrains Mono Project Authors · typeface",
              license = "SIL OFL 1.1",
          ),
          OpenSourceLicense(
              name = "IBM Plex Sans",
              detail = "IBM Corp. · typeface",
              license = "SIL OFL 1.1",
          ),
      )

  public const val DEFAULT_SENTRY_DSN: String =
      "https://ae2f3e2be71221701a6608b02c1bc344@sentry-ingest.ipv1337.dev/4"

  /** Device details included in crash reports; excludes PII, IP, texts, contacts, and hosts. */
  public data class CrashReportDeviceDetails(
      val androidRelease: String = "",
      val model: String = "",
      val screenWidthPx: Int? = null,
      val screenHeightPx: Int? = null,
      val memorySizeBytes: Long? = null,
  )

  /** Statements rendered on the Privacy page, each verified against the app's actual code. */
  public const val privacyCrashReportsStatement: String =
      "Crash reports (on by default): if the app crashes, it sends a report to Vitruvian " +
          "Software's own crash server (sentry-ingest.ipv1337.dev) so we can fix the problem. " +
          "A report contains the error and where in the app it happened, the time, the app " +
          "and Android versions, your phone model, screen size and total memory, and a random " +
          "report ID. It never contains your texts, contacts, files, what you type, your Macs' " +
          "addresses, or a record of what you did in the app. The app doesn't add your IP " +
          "address, though like any connection the server can see the address a report " +
          "comes from. Turning this off stops reports right away and deletes any that " +
          "haven't been sent yet."

  /** Canonical Phone Bridge capabilities shared across Settings, Phone Bridge, and Privacy. */
  public val phoneBridgeCapabilities: List<String> =
      listOf(
          "texts",
          "contacts",
          "call history",
          "location",
          "notifications",
          "screen control",
      )

  public val phoneBridgeCapabilitiesCommaList: String = phoneBridgeCapabilities.joinToString(", ")

  public val phoneBridgeCapabilitiesProseList: String =
      when (phoneBridgeCapabilities.size) {
        0 -> ""
        1 -> phoneBridgeCapabilities.single()
        else ->
            phoneBridgeCapabilities.dropLast(1).joinToString(", ") +
                " and " +
                phoneBridgeCapabilities.last()
      }

  public val phoneBridgeScreenSummary: String =
      "Off by default. When on, AI agents on your own Mac can use " +
          "$phoneBridgeCapabilitiesProseList on this phone within the permissions you grant, " +
          "and ask before sending or calling."

  public val privacyLeadingStatements: List<String> = listOf("No account and no ads.")

  public val privacyTrailingStatements: List<String> =
      listOf(
          "This phone talks to the Macs you add, and to Vitruvian Software's crash server if " +
              "crash reports are on. Trackpad and keys go straight to your Mac over Bluetooth.",
          "Phone Bridge is off until you turn it on. When it's on, AI agents on your own Mac " +
              "can use only the permissions you grant ($phoneBridgeCapabilitiesCommaList). " +
              "The most recent requests are listed on the Phone Bridge page.",
          "Alerts come from your Mac through the ntfy server you set up, if any; this app does not contact ntfy.",
          "Dictation uses your phone's speech service, which may send audio to its provider.",
          "Donate and the links here open in your browser. The app never handles payment details.",
      )

  private const val SENTRY_CACHE_DIR_NAME: String = "sentry"

  /** Base cache directory passed to `SentryOptions.cacheDirPath`. */
  public fun sentryCacheDir(appCacheDir: File): File = File(appCacheDir, SENTRY_CACHE_DIR_NAME)

  /**
   * Deletes Sentry's on-disk cache directory (`<appCacheDir>/sentry`, containing the DSN-hashed
   * envelope cache, `outbox`, `.options-cache`, `.scope-cache`, and marker files) when crash
   * reporting is disabled so previously queued reports never leave the phone.
   */
  public fun clearSentryCache(appCacheDir: File) {
    val target = sentryCacheDir(appCacheDir)
    if (target.exists()) {
      target.deleteRecursively()
    }
  }

  /**
   * Closes Sentry and deletes `<appCacheDir>/sentry` right after so previously queued or newly
   * closed crash envelopes do not remain on disk.
   */
  public fun disableCrashReporting(
      appCacheDir: File,
      closeSentry: () -> Unit = { Sentry.close() },
  ) {
    closeSentry()
    clearSentryCache(appCacheDir)
  }

  /**
   * Configures Sentry directly on the plain Java SDK `SentryOptions` so every privacy setting (no
   * PII, no breadcrumbs, no server hostname, no other thread stacks, no tracing/profiling, and
   * bounded device details) is provable in JVM unit tests.
   */
  public fun configureSentryOptions(
      options: SentryOptions,
      dsn: String = DEFAULT_SENTRY_DSN,
      appVersion: String?,
      device: CrashReportDeviceDetails = CrashReportDeviceDetails(),
      appCacheDir: File? = null,
  ) {
    options.dsn = dsn
    options.release = sentryRelease(appVersion)
    options.environment = "production"
    if (appCacheDir != null) {
      options.cacheDirPath = sentryCacheDir(appCacheDir).absolutePath
    }
    options.isSendDefaultPii = false
    // Sentry 7.14.0 builds CircularFifoQueue(maxBreadcrumbs) inside Scope.<init> and throws if <=
    // 0;
    // beforeBreadcrumb drops every breadcrumb before insertion and beforeSend clears
    // event.breadcrumbs.
    options.maxBreadcrumbs = 1
    options.isAttachServerName = false
    options.serverName = null
    options.isAttachThreads = false
    options.isSendModules = false
    options.isEnableAutoSessionTracking = false
    options.isSendClientReports = false

    // No breadcrumbs (so no taps, URLs, or Mac addresses).
    options.beforeBreadcrumb = SentryOptions.BeforeBreadcrumbCallback { _, _ -> null }

    // Leave performance tracing unset/disabled (tracesSampleRate stays null).
    options.enableTracing = false
    options.tracesSampleRate = null
    options.tracesSampler = null
    options.profilesSampleRate = null
    options.profilesSampler = null
    options.setTracePropagationTargets(emptyList())
    options.beforeSendTransaction = SentryOptions.BeforeSendTransactionCallback { _, _ -> null }

    val cleanModel = device.model.trim().takeIf { it.isNotEmpty() }
    val cleanOs = device.androidRelease.trim().takeIf { it.isNotEmpty() }
    cleanModel?.let { options.setTag("device.model", it) }
    cleanOs?.let { options.setTag("os.version", it) }

    options.beforeSend =
        SentryOptions.BeforeSendCallback { event, hint ->
          hint.clearAttachments()
          event.breadcrumbs = null
          // MainEventProcessor.mergeUser sets user.ipAddress = "{{auto}}" even when sendDefaultPii
          // is false; dropping user prevents IP inference and strips any user context.
          event.user = null
          event.request = null
          event.serverName = null
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
          event.contexts.remove(SentryRuntime.TYPE)
          if (cleanOs != null) {
            event.contexts.setOperatingSystem(
                OperatingSystem().apply {
                  name = "Android"
                  version = cleanOs
                })
          }
          if (cleanModel != null ||
              device.screenWidthPx != null ||
              device.screenHeightPx != null ||
              device.memorySizeBytes != null) {
            event.contexts.setDevice(
                Device().apply {
                  model = cleanModel
                  screenWidthPixels = device.screenWidthPx
                  screenHeightPixels = device.screenHeightPx
                  memorySize = device.memorySizeBytes
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
    if (raw.startsWith("::") &&
        right.size == 1 &&
        '.' !in right[0] &&
        !right[0].all(Char::isDigit)) {
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
          if (target.endsWith(':') &&
              !target.endsWith("::") &&
              !isValidSocketAddressTarget(target)) {
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

  public fun normalizeVersion(version: String?): String =
      version?.trim()?.takeIf { it.isNotEmpty() } ?: "dev"

  public fun isPrerelease(version: String): Boolean {
    val core = version.trim().substringBefore('+')
    return core.isNotEmpty() && !core.equals("dev", ignoreCase = true) && '-' in core
  }

  public fun sentryRelease(version: String?): String =
      "vitruvian-remote@${normalizeVersion(version)}"

  public fun versionCopyLine(
      version: String,
      androidRelease: String,
      deviceModel: String,
  ): String {
    val ver = normalizeVersion(version)
    val rel = androidRelease.trim().ifEmpty { "unknown" }
    val model = deviceModel.trim().ifEmpty { "unknown" }
    return "$name $ver (Android $rel, $model)"
  }

  public fun macHelperLine(
      isLive: Boolean,
      agentVersion: String?,
      shortHostName: String,
  ): String? {
    if (!isLive) return null
    val ver = agentVersion?.trim()?.removePrefix("v")?.takeIf { it.isNotEmpty() } ?: return null
    val host = shortHostName.trim().takeIf { it.isNotEmpty() && it != "no host" } ?: return null
    return "Mac helper v$ver on $host"
  }

  public fun parentOfAboutPage(page: AboutPage): AboutPage? =
      if (page == AboutPage.Main) null else AboutPage.Main

  public fun shouldAllowWhileUnpaired(screenName: String): Boolean =
      screenName == "Hosts" || screenName == "About" || screenName == "PhoneBridge"
}
