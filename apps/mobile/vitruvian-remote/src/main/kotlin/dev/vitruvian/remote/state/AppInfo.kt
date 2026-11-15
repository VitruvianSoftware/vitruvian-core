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

  /** Statements rendered on the Privacy page, each verified against the app's actual code. */
  public const val privacyCrashReportsStatement: String =
      "Crash reports: if the app crashes, a report (the error, the app version and your phone " +
          "model) is sent to Vitruvian Software's own crash server, so we can fix it. It never " +
          "includes your texts, contacts, files or what you type. You can turn this off below."

  public val privacyLeadingStatements: List<String> = listOf("No account and no ads.")

  public val privacyTrailingStatements: List<String> =
      listOf(
          "This phone talks only to the Macs you add, over your own network or Tailscale. " +
              "Trackpad and keys go straight to your Mac over Bluetooth.",
          "Phone Bridge is off until you turn it on. When it's on, AI agents on your own Mac " +
              "can use only the permissions you grant (texts, contacts, call history, location, " +
              "notifications, screen control), and every request is listed in Settings.",
          "Alerts come from your Mac through the ntfy server you set up, if any.",
          "Dictation uses your phone's speech service, which may send audio to its provider.",
          "Donate and the links here open in your browser. The app never handles payment details.",
      )

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
