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

import io.sentry.SentryOptions
import io.sentry.protocol.Device
import io.sentry.protocol.OperatingSystem
import java.io.File

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
   * Direct `@maven` libraries from `apps/mobile/vitruvian-remote/BUILD` (`:lib`) and the bundled
   * fonts from `packages/design-system-android/fonts`. Checked in `AppInfoTest` so adding a new
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
              name = "AndroidX Compose",
              detail = "runtime, ui, foundation, animation",
              license = "Apache-2.0",
              mavenTargets =
                  setOf(
                      "@maven//:androidx_compose_animation_animation",
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
      "Crash reports: if the app crashes, a report is sent to Vitruvian Software's own crash " +
          "server, so we can fix it: the error and where in the app it happened, the app " +
          "version, the Android version, and device details such as model, screen size and " +
          "memory. Never your texts, contacts, files, what you type, or your Macs' addresses. " +
          "You can turn this off below."

  public val privacyLeadingStatements: List<String> = listOf("No account and no ads.")

  public val privacyTrailingStatements: List<String> =
      listOf(
          "This phone talks to the Macs you add, and to Vitruvian Software's crash server if " +
              "crash reports are on. Trackpad and keys go straight to your Mac over Bluetooth.",
          "Phone Bridge is off until you turn it on. When it's on, AI agents on your own Mac " +
              "can use only the permissions you grant (texts, contacts, call history, location, " +
              "notifications, screen control), and every request is listed in Settings.",
          "Alerts come from your Mac through the ntfy server you set up, if any.",
          "Dictation uses your phone's speech service, which may send audio to its provider.",
          "Donate and the links here open in your browser. The app never handles payment details.",
      )

  private const val SENTRY_CACHE_DIR_NAME: String = "sentry"
  private val SENTRY_CACHE_DIRS: List<String> = listOf(SENTRY_CACHE_DIR_NAME, "io.sentry.cache")

  /** Base cache directory passed to `SentryOptions.cacheDirPath`. */
  public fun sentryCacheDir(appCacheDir: File): File = File(appCacheDir, SENTRY_CACHE_DIR_NAME)

  /**
   * Deletes Sentry's cached envelopes and outbox directory under [appCacheDir] when crash reporting
   * is disabled so previously queued reports never leave the phone.
   */
  public fun clearSentryCache(appCacheDir: File) {
    for (dirName in SENTRY_CACHE_DIRS) {
      val target = File(appCacheDir, dirName)
      if (target.exists()) {
        target.deleteRecursively()
      }
    }
  }

  /**
   * Configures Sentry in a pure helper so every privacy claim (no PII, no breadcrumbs, no
   * performance tracing, no screenshots or view hierarchy, and bounded device details) is provable
   * in JVM unit tests.
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
    options.isAttachServerName = false
    options.serverName = null
    options.isSendModules = false
    options.isEnableAutoSessionTracking = false
    options.isSendClientReports = false

    // No breadcrumbs (so no taps, URLs, or Mac addresses).
    options.maxBreadcrumbs = 0
    options.beforeBreadcrumb = SentryOptions.BeforeBreadcrumbCallback { _, _ -> null }
    options.isEnableUserInteractionBreadcrumbs = false
    options.isEnableScreenTracking = false
    options.gestureTargetLocators = emptyList()

    // No user-interaction or performance tracing / profiling.
    options.isEnableUserInteractionTracing = false
    options.enableTracing = false
    options.tracesSampleRate = null
    options.tracesSampler = null
    options.profilesSampleRate = null
    options.profilesSampler = null
    options.isEnableAppStartProfiling = false
    options.isEnableTimeToFullDisplayTracing = false
    options.setTracePropagationTargets(emptyList())
    options.beforeSendTransaction = SentryOptions.BeforeSendTransactionCallback { _, _ -> null }

    // No screenshots or view hierarchy (on core SentryOptions + subclass setters if present).
    options.viewHierarchyExporters = emptyList()
    setBooleanOptionIfPresent(options, "setAttachScreenshot", false)
    setBooleanOptionIfPresent(options, "setAttachViewHierarchy", false)

    val cleanModel = device.model.trim().takeIf { it.isNotEmpty() }
    val cleanOs = device.androidRelease.trim().takeIf { it.isNotEmpty() }
    cleanModel?.let { options.setTag("device.model", it) }
    cleanOs?.let { options.setTag("os.version", it) }

    options.beforeSend =
        SentryOptions.BeforeSendCallback { event, hint ->
          hint.screenshot = null
          hint.viewHierarchy = null
          hint.threadDump = null
          hint.replayRecording = null
          hint.clearAttachments()
          event.breadcrumbs = null
          // MainEventProcessor.mergeUser sets user.ipAddress = "{{auto}}" even when sendDefaultPii
          // is false; dropping user prevents IP inference and strips any user context.
          event.user = null
          event.request = null
          event.serverName = null
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

  private fun setBooleanOptionIfPresent(target: Any, setterName: String, value: Boolean) {
    runCatching {
      target.javaClass.getMethod(setterName, Boolean::class.javaPrimitiveType).invoke(target, value)
    }
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
