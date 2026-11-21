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

import dev.vitruvian.crashprivacy.DeviceField
import dev.vitruvian.crashprivacy.PrivateSentryDevice
import dev.vitruvian.crashprivacy.clearSentryCache as clearSharedSentryCache
import dev.vitruvian.crashprivacy.configurePrivateSentry
import dev.vitruvian.crashprivacy.disableCrashReporting as disableSharedCrashReporting
import dev.vitruvian.crashprivacy.scrubCrashMessage as scrubSharedCrashMessage
import dev.vitruvian.crashprivacy.sentryCacheDir as sharedSentryCacheDir
import io.sentry.Sentry
import io.sentry.SentryOptions
import io.sentry.android.core.SentryAndroidOptions
import java.io.File
import java.util.EnumSet

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
   * `packages/design-system/android/BUILD`, plus the bundled fonts from
   * `packages/design-system/android/fonts`. Checked in `AppInfoTest` so adding a new runtime
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
              name = "Sentry Android SDK",
              detail = "io.sentry:sentry-android-core",
              license = "MIT",
              mavenTargets = setOf("@maven//:io_sentry_sentry_android_core"),
          ),
          OpenSourceLicense(
              name = "Google ML Kit GenAI Text-to-Speech",
              detail = "com.google.mlkit:genai-text-to-speech, genai-common, common",
              license = "ML Kit Terms of Service",
              mavenTargets =
                  setOf(
                      "@maven//:com_google_mlkit_common",
                      "@maven//:com_google_mlkit_genai_common",
                      "@maven//:com_google_mlkit_genai_text_to_speech",
                  ),
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
          "address, and the crash server is set not to store it. Turning this off stops " +
          "reports right away and deletes any that haven't been sent yet."

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
          "This phone talks to the Macs you add, to Vitruvian Software's crash server if " +
              "crash reports are on, and to vitruviansoftware.dev to check for updates when " +
              "you open About. Tapping Update downloads the new version from Vitruvian's " +
              "releases on GitHub. Trackpad and keys go straight to your Mac over Bluetooth.",
          "Phone Bridge is off until you turn it on. When it's on, AI agents on your own Mac " +
              "can use only the permissions you grant ($phoneBridgeCapabilitiesCommaList). " +
              "The most recent requests are listed on the Phone Bridge page.",
          "Alerts come from your Mac through the ntfy server you set up, if any; this app does not contact ntfy.",
          "Dictation uses your phone's speech service, which may send audio to its provider.",
          "Donate and the links here open in your browser. The app never handles payment details.",
      )

  /**
   * Device and app fields retained by Vitruvian Remote, matching [privacyCrashReportsStatement].
   */
  public val CRASH_REPORT_DEVICE_FIELDS: Set<DeviceField> =
      EnumSet.of(
          DeviceField.MODEL,
          DeviceField.SCREEN,
          DeviceField.MEMORY,
          DeviceField.OS_VERSION,
          DeviceField.APP_VERSION,
      )

  /** Base cache directory passed to `SentryOptions.cacheDirPath`. */
  public fun sentryCacheDir(appCacheDir: File): File = sharedSentryCacheDir(appCacheDir)

  /**
   * Deletes Sentry's on-disk cache directory (`<appCacheDir>/sentry`, containing the DSN-hashed
   * envelope cache, `outbox`, `.options-cache`, `.scope-cache`, and marker files) when crash
   * reporting is disabled so previously queued reports never leave the phone.
   */
  public fun clearSentryCache(appCacheDir: File) {
    clearSharedSentryCache(appCacheDir)
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
    disableSharedCrashReporting(
        appCacheDir = appCacheDir,
        options = options,
        closeSentry = closeSentry,
        deleteCache = deleteCache,
    )
  }

  /**
   * Configures Sentry on [SentryAndroidOptions] via [configurePrivateSentry] using Vitruvian
   * Remote's documented [CRASH_REPORT_DEVICE_FIELDS].
   */
  public fun configureSentryOptions(
      options: SentryAndroidOptions,
      dsn: String = DEFAULT_SENTRY_DSN,
      appVersion: String?,
      device: CrashReportDeviceDetails = CrashReportDeviceDetails(),
      appCacheDir: File? = null,
  ) {
    configurePrivateSentry(
        options = options,
        dsn = dsn,
        keepDeviceFields = CRASH_REPORT_DEVICE_FIELDS,
        release = sentryRelease(appVersion),
        environment = "production",
        device =
            PrivateSentryDevice(
                androidRelease = device.androidRelease,
                model = device.model,
                screenWidthPx = device.screenWidthPx,
                screenHeightPx = device.screenHeightPx,
                memorySizeBytes = device.memorySizeBytes,
            ),
        appCacheDir = appCacheDir,
    )
  }

  /**
   * Replaces URLs, IPv4/IPv6 literals, host:port pairs, and dotted hostnames with `<address>` while
   * leaving ordinary Java/Kotlin exception and package names untouched.
   */
  public fun scrubCrashMessage(message: String): String = scrubSharedCrashMessage(message)

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
}
