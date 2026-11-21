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
import io.sentry.Attachment
import io.sentry.Breadcrumb
import io.sentry.Hint
import io.sentry.MainEventProcessor
import io.sentry.SentryEvent
import io.sentry.android.core.SentryAndroidOptions
import io.sentry.protocol.App
import io.sentry.protocol.Device
import io.sentry.protocol.OperatingSystem
import io.sentry.protocol.SentryRuntime
import io.sentry.protocol.User
import java.io.File
import java.util.EnumSet
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

public class AppInfoTest {
  private fun resolvePath(rel: String): File {
    val direct = File(rel)
    if (direct.exists()) return direct
    val base = System.getenv("TEST_SRCDIR") ?: error("TEST_SRCDIR unset and missing $rel")
    return listOf("_main", "vitruvian_core", "")
        .map { sub -> if (sub.isEmpty()) File(base, rel) else File(File(base, sub), rel) }
        .firstOrNull { it.exists() } ?: error("Runfile not found: $rel")
  }

  @Test
  public fun `donate URL is pinned and public URLs match spec`() {
    assertEquals("Vitruvian Remote", AppInfo.name)
    assertEquals(
        "https://vitruviansoftware.dev/donate/vitruvian-remote/?src=app-vitruvian-remote",
        AppInfo.donateURL,
    )
    assertEquals("https://github.com/VitruvianSoftware/vitruvian-remote", AppInfo.repositoryURL)
    assertEquals(
        "https://github.com/VitruvianSoftware/vitruvian-remote/issues",
        AppInfo.issuesURL,
    )
    assertEquals("https://vitruviansoftware.dev", AppInfo.websiteURL)
    assertEquals(
        "https://github.com/VitruvianSoftware/vitruvian-remote#readme",
        AppInfo.setupGuideURL,
    )
  }

  @Test
  public fun `no URL or source file in the app references stripe dot com`() {
    val srcMain = resolvePath("apps/mobile/vitruvian-remote/src/main")
    val files =
        srcMain
            .walkTopDown()
            .filter { file ->
              file.isFile &&
                  file.extension.lowercase(Locale.ROOT) in setOf("kt", "xml", "txt", "json")
            }
            .toList()
    assertTrue("Expected at least 20 files under src/main, got ${files.size}", files.size >= 20)
    val offenders =
        files.filter { file -> file.readText().contains("stripe.com", ignoreCase = true) }
    assertTrue(
        "No app source/resource may embed stripe.com: ${offenders.map { it.path }}",
        offenders.isEmpty(),
    )
  }

  @Test
  public fun `bundled raw license matches repo LICENSE file`() {
    val repoLicense = resolvePath("apps/mobile/vitruvian-remote/LICENSE").readText()
    val bundledLicense =
        resolvePath("apps/mobile/vitruvian-remote/src/main/res/raw/app_license.txt").readText()
    assertEquals(repoLicense, bundledLicense)
    assertTrue(repoLicense.startsWith("MIT License"))
  }

  /**
   * Extracts every `@maven` runtime dependency referenced by top-level rules in a Starlark `BUILD`
   * file, excluding `*_test` rules, `kt_compiler_plugin`, and `testonly = True` targets.
   */
  private fun extractRuntimeMavenDeps(buildText: String): Set<String> {
    val testonlyRegex = Regex("""\btestonly\s*=\s*True\b""")
    val mavenRegex = Regex("""["'](@maven//:[A-Za-z0-9_]+)["']""")
    val result = linkedSetOf<String>()
    val n = buildText.length
    var i = 0

    fun skipStringOrComment() {
      when {
        buildText[i] == '#' -> {
          while (i < n && buildText[i] != '\n') i++
        }
        buildText.startsWith("\"\"\"", i) || buildText.startsWith("'''", i) -> {
          val quote = buildText.substring(i, i + 3)
          i += 3
          while (i < n && !buildText.startsWith(quote, i)) {
            if (buildText[i] == '\\' && i + 1 < n) i += 2 else i++
          }
          if (i < n) i += 3
        }
        buildText[i] == '"' || buildText[i] == '\'' -> {
          val quote = buildText[i++]
          while (i < n && buildText[i] != quote) {
            if (buildText[i] == '\\' && i + 1 < n) i += 2 else i++
          }
          if (i < n) i++
        }
      }
    }

    fun stripComments(block: String): String =
        buildString(block.length) {
          var j = 0
          val m = block.length
          while (j < m) {
            val c = block[j]
            if (c == '#') {
              while (j < m && block[j] != '\n') j++
            } else if (block.startsWith("\"\"\"", j) || block.startsWith("'''", j)) {
              val quote = block.substring(j, j + 3)
              append(quote)
              j += 3
              while (j < m && !block.startsWith(quote, j)) {
                if (block[j] == '\\' && j + 1 < m) {
                  append(block[j])
                  append(block[j + 1])
                  j += 2
                } else {
                  append(block[j++])
                }
              }
              if (j < m) {
                append(quote)
                j += 3
              }
            } else if (c == '"' || c == '\'') {
              val quote = c
              append(quote)
              j++
              while (j < m && block[j] != quote) {
                if (block[j] == '\\' && j + 1 < m) {
                  append(block[j])
                  append(block[j + 1])
                  j += 2
                } else {
                  append(block[j++])
                }
              }
              if (j < m) {
                append(quote)
                j++
              }
            } else {
              append(c)
              j++
            }
          }
        }

    while (i < n) {
      val ch = buildText[i]
      if (ch == '#' || ch == '"' || ch == '\'') {
        skipStringOrComment()
        continue
      }
      if ((i == 0 || buildText[i - 1] == '\n') && (ch.isLetter() || ch == '_')) {
        val nameStart = i
        while (i < n && (buildText[i].isLetterOrDigit() || buildText[i] == '_')) i++
        val ruleName = buildText.substring(nameStart, i)
        while (i < n && (buildText[i] == ' ' || buildText[i] == '\t')) i++
        if (i < n && buildText[i] == '(') {
          val openParen = i
          var depth = 1
          i++
          while (i < n && depth > 0) {
            val c = buildText[i]
            when {
              c == '#' || c == '"' || c == '\'' -> skipStringOrComment()
              c == '(' -> {
                depth++
                i++
              }
              c == ')' -> {
                depth--
                i++
              }
              else -> i++
            }
          }
          val block = stripComments(buildText.substring(openParen, i))
          val excludedRule =
              ruleName.endsWith("_test") ||
                  ruleName == "kt_compiler_plugin" ||
                  testonlyRegex.containsMatchIn(block)
          if (!excludedRule) {
            mavenRegex.findAll(block).forEach { result.add(it.groupValues[1]) }
          }
          continue
        }
      }
      i++
    }
    return result
  }

  @Test
  public fun `every runtime maven dependency in app and design system BUILD has an open source license entry`() {
    val appBuildText = resolvePath("apps/mobile/vitruvian-remote/BUILD").readText()
    val dsBuildText = resolvePath("packages/design-system/android/BUILD").readText()
    val crashPrivacyBuildText = resolvePath("packages/android-crash-privacy/BUILD").readText()
    val runtimeMavenTargets =
        extractRuntimeMavenDeps(appBuildText) +
            extractRuntimeMavenDeps(dsBuildText) +
            extractRuntimeMavenDeps(crashPrivacyBuildText)
    assertTrue("Expected runtime @maven deps across BUILD files", runtimeMavenTargets.isNotEmpty())
    assertTrue(
        "Design-system runtime dep androidx_annotation_annotation must be checked",
        "@maven//:androidx_annotation_annotation" in runtimeMavenTargets,
    )
    assertTrue(
        "Design-system runtime dep androidx_compose_animation_animation_core must be checked",
        "@maven//:androidx_compose_animation_animation_core" in runtimeMavenTargets,
    )
    assertFalse(
        "Test-only junit must be excluded from runtime license list",
        "@maven//:junit_junit" in runtimeMavenTargets,
    )
    assertFalse(
        "Compiler plugin must be excluded from runtime license list",
        "@maven//:org_jetbrains_kotlin_kotlin_compose_compiler_plugin_embeddable" in
            runtimeMavenTargets,
    )

    val coveredTargetsList = AppInfo.openSourceLicenses.flatMap { it.mavenTargets }
    val coveredTargets = coveredTargetsList.toSet()
    assertEquals(
        "Every @maven target must appear at most once in AppInfo.openSourceLicenses",
        coveredTargets.size,
        coveredTargetsList.size,
    )
    AppInfo.openSourceLicenses.forEach { entry ->
      assertTrue("License entry name must not be blank", entry.name.isNotBlank())
      assertTrue("License entry detail must not be blank", entry.detail.isNotBlank())
      assertTrue("License entry license must not be blank", entry.license.isNotBlank())
    }
    assertEquals(
        "Every runtime @maven dep in apps/mobile/vitruvian-remote/BUILD and " +
            "packages/design-system/android/BUILD must have an AppInfo.openSourceLicenses entry",
        runtimeMavenTargets,
        coveredTargets,
    )

    val byName = AppInfo.openSourceLicenses.associateBy { it.name }
    assertEquals("Apache-2.0", byName.getValue("AndroidX Annotation").license)
    assertEquals("Apache-2.0", byName.getValue("AndroidX Compose").license)
    assertEquals("MIT", byName.getValue("Sentry SDK").license)
    assertEquals("MIT", byName.getValue("Sentry Android SDK").license)
    assertEquals("SIL OFL 1.1", byName.getValue("JetBrains Mono").license)
    assertEquals("SIL OFL 1.1", byName.getValue("IBM Plex Sans").license)
  }

  @Test
  public fun `extractRuntimeMavenDeps keeps secondary runtime libs and excludes test and plugin rules`() {
    val syntheticBuild =
        """
        # "@maven//:commented_out_dep"
        kt_compiler_plugin(
            name = "compiler",
            deps = ["@maven//:plugin_only"],
        )
        kt_jvm_library(
            name = "helper",
            deps = ["@maven//:runtime_helper"],
        )
        java_import(
            name = "test_stub",
            testonly = True,
            deps = ["@maven//:testonly_dep"],
        )
        kt_jvm_test(
            name = "unit_test",
            deps = ["@maven//:junit_junit"],
        )
        """
            .trimIndent()

    assertEquals(setOf("@maven//:runtime_helper"), extractRuntimeMavenDeps(syntheticBuild))
  }

  @Test
  public fun `version prerelease release copy and About back helpers work`() {
    assertFalse(AppInfo.isPrerelease("0.1.40"))
    assertFalse(AppInfo.isPrerelease("dev"))
    assertFalse(AppInfo.isPrerelease("0.1.40+build1"))
    assertTrue(AppInfo.isPrerelease("0.1.40-beta.1"))
    assertTrue(AppInfo.isPrerelease("0.1.40-rc.2"))
    assertTrue(AppInfo.isPrerelease("0.1.40-alpha"))

    assertEquals("vitruvian-remote@0.1.40", AppInfo.sentryRelease("0.1.40"))
    assertEquals("vitruvian-remote@dev", AppInfo.sentryRelease(""))
    assertEquals("vitruvian-remote@dev", AppInfo.sentryRelease(null))

    assertEquals(
        "Vitruvian Remote 0.1.40 (Android 15, Pixel Fold)",
        AppInfo.versionCopyLine("0.1.40", "15", "Pixel Fold"),
    )
    assertEquals(
        "Mac helper v0.1.40 on atlas",
        AppInfo.macHelperLine(isLive = true, agentVersion = "0.1.40", shortHostName = "atlas"),
    )
    assertEquals(
        "Mac helper v0.1.40 on atlas",
        AppInfo.macHelperLine(isLive = true, agentVersion = "v0.1.40", shortHostName = "atlas"),
    )
    assertNull(
        AppInfo.macHelperLine(isLive = false, agentVersion = "0.1.40", shortHostName = "atlas"),
    )
    assertNull(
        AppInfo.macHelperLine(isLive = true, agentVersion = "", shortHostName = "atlas"),
    )
    assertNull(
        AppInfo.macHelperLine(isLive = true, agentVersion = "0.1.40", shortHostName = "no host"),
    )

    assertNull(AppInfo.parentOfAboutPage(AboutPage.Main))
    assertEquals(AboutPage.Main, AppInfo.parentOfAboutPage(AboutPage.Privacy))
    assertEquals(AboutPage.Main, AppInfo.parentOfAboutPage(AboutPage.License))
    assertEquals(AboutPage.Main, AppInfo.parentOfAboutPage(AboutPage.OpenSourceLicenses))
  }

  @Test
  public fun `privacy copy states exact crash server and report contents`() {
    val talkStatement = AppInfo.privacyTrailingStatements.first()
    assertTrue(
        talkStatement.startsWith(
            "This phone talks to the Macs you add, to Vitruvian Software's crash server if " +
                "crash reports are on, and to vitruviansoftware.dev to check for updates when " +
                "you open About.",
        ),
    )
    assertFalse(talkStatement.contains("talks only to the Macs you add"))

    assertTrue(
        AppInfo.privacyCrashReportsStatement.contains(
            "it sends a report to Vitruvian Software's own crash server " +
                "(sentry-ingest.ipv1337.dev)",
        ),
    )
    assertTrue(
        AppInfo.privacyCrashReportsStatement.contains(
            "the error and where in the app it happened, the time, the app and Android " +
                "versions, your phone model, screen size and total memory, and a random " +
                "report ID.",
        ),
    )
    assertTrue(
        AppInfo.privacyCrashReportsStatement.contains(
            "It never contains your texts, contacts, files, what you type, your Macs' " +
                "addresses, or a record of what you did in the app.",
        ),
    )
    // The server drops IP addresses (Sentry org setting scrubIPAddresses, managed as code in
    // infrastructure/pulumi/platform/sentry); the copy says so instead of "the server can see it".
    assertTrue(
        AppInfo.privacyCrashReportsStatement.contains(
            "The app doesn't add your IP address, and the crash server is set not to store it.",
        ),
    )
    // Plain words only: no tool names or jargon a user would have to decode.
    for (forbidden in
        listOf("such as", "screenshot", "view hierarchy", "SDK", "PII", "breadcrumb", "user IP")) {
      assertFalse(
          "privacyCrashReportsStatement must not claim '$forbidden'",
          AppInfo.privacyCrashReportsStatement.contains(forbidden, ignoreCase = true),
      )
    }

    assertEquals(
        listOf(
            "texts",
            "contacts",
            "call history",
            "location",
            "notifications",
            "screen control",
        ),
        AppInfo.phoneBridgeCapabilities,
    )
    for (capability in AppInfo.phoneBridgeCapabilities) {
      assertTrue(
          "phoneBridgeScreenSummary missing '$capability'",
          AppInfo.phoneBridgeScreenSummary.contains(capability),
      )
      assertTrue(
          "privacyTrailingStatements[1] missing '$capability'",
          AppInfo.privacyTrailingStatements[1].contains(capability),
      )
    }
    assertTrue(
        AppInfo.privacyTrailingStatements[1].endsWith(
            "The most recent requests are listed on the Phone Bridge page.",
        ),
    )
    assertFalse(
        AppInfo.privacyTrailingStatements.any { it.contains("every request is listed") },
    )
  }

  private fun findForbiddenSentryReflectionTokens(source: String): List<String> {
    val forbiddenTokens =
        listOf(
            "java.lang.reflect",
            "kotlin.reflect",
            ".getMethod(",
            ".getDeclaredMethod(",
            ".methods",
            ".declaredMethods",
            ".getField(",
            ".getDeclaredField(",
            "Class.forName(",
            ".javaClass",
            "::class.java",
            "setBooleanOptionIfPresent",
        )
    return forbiddenTokens.filter { token -> source.contains(token) }
  }

  @Test
  public fun `configureSentryOptions does not use reflection`() {
    val reflectionSample =
        "target.javaClass.getMethod(\"setAttachScreenshot\", Boolean::class.javaPrimitiveType)"
    assertTrue(
        "Reflection detector must catch reflection if reintroduced",
        findForbiddenSentryReflectionTokens(reflectionSample).isNotEmpty(),
    )

    val appInfoSource =
        resolvePath(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/AppInfo.kt")
            .readText()
    assertEquals(emptyList<String>(), findForbiddenSentryReflectionTokens(appInfoSource))
  }

  @Test
  public fun `manifest disables sentry auto-init and MainActivity uses SentryAndroid init`() {
    val manifest =
        resolvePath("apps/mobile/vitruvian-remote/src/main/AndroidManifest.xml").readText()
    val appSection = manifest.substringAfter("<application")
    assertTrue(
        "Expected io.sentry.auto-init metadata in <application>",
        Regex("""<meta-data[^>]*android:name="io\.sentry\.auto-init"[^>]*android:value="false"""")
            .containsMatchIn(appSection),
    )
    val mainActivity =
        resolvePath(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/MainActivity.kt")
            .readText()
    assertTrue(mainActivity.contains("SentryAndroid.init(this)"))
    assertFalse(mainActivity.contains("Sentry.init("))
  }

  @Test
  public fun `AppInfo keeps Remote's documented device and app fields while delegating to shared helper`() {
    assertEquals(
        EnumSet.of(
            DeviceField.MODEL,
            DeviceField.SCREEN,
            DeviceField.MEMORY,
            DeviceField.OS_VERSION,
            DeviceField.APP_VERSION,
        ),
        AppInfo.CRASH_REPORT_DEVICE_FIELDS,
    )

    val options = SentryAndroidOptions().apply { distinctId = "pre-existing-id" }
    AppInfo.configureSentryOptions(
        options = options,
        dsn = "https://examplePublicKey@o0.ingest.sentry.io/0",
        appVersion = "0.1.40",
        device =
            AppInfo.CrashReportDeviceDetails(
                androidRelease = "15",
                model = "Pixel Fold",
                screenWidthPx = 2208,
                screenHeightPx = 1840,
                memorySizeBytes = 12_884_901_888L,
            ),
    )

    assertEquals("vitruvian-remote@0.1.40", options.release)
    assertEquals("production", options.environment)
    assertTrue(options.dataCollection.isExplicitlyConfigured)
    assertFalse(options.dataCollectionResolver.isUserInfo)
    assertNull(options.distinctId)
    assertEquals(0, options.maxBreadcrumbs)
    assertEquals(mapOf("device.model" to "Pixel Fold", "os.version" to "15"), options.tags)

    val rawEvent =
        SentryEvent(RuntimeException("Failed to connect to 192.168.1.20:7411")).apply {
          addBreadcrumb(Breadcrumb.info("tap"))
          user =
              User().apply {
                id = "install-id"
                email = "user@example.com"
              }
          dist = "144"
          setTag("isSideLoaded", "true")
          setExtra("secret", "1")
          contexts.setApp(App().apply { appName = "Vitruvian Remote" })
          contexts.setDevice(
              Device().apply {
                manufacturer = "Google"
                timezone = TimeZone.getTimeZone("UTC")
              })
          contexts.setOperatingSystem(
              OperatingSystem().apply {
                name = "Android"
                version = "15"
                kernelVersion = "6.1"
              })
          contexts.setRuntime(SentryRuntime().apply { name = "Android Runtime" })
        }
    val hint = Hint().apply { addAttachment(Attachment(byteArrayOf(6, 7), "extra.txt")) }
    val processed = MainEventProcessor(options).process(rawEvent, hint)
    val sanitized = options.beforeSend!!.execute(processed, hint)!!

    assertEquals("vitruvian-remote@0.1.40", sanitized.release)
    assertEquals("production", sanitized.environment)
    assertEquals("Failed to connect to <address>", sanitized.exceptions!!.single().value)
    assertEquals(mapOf("device.model" to "Pixel Fold", "os.version" to "15"), sanitized.tags)
    assertNull(sanitized.user)
    assertNull(sanitized.breadcrumbs)
    assertNull(sanitized.dist)
    assertTrue(sanitized.extras.isNullOrEmpty())
    assertNull(sanitized.contexts.app)
    assertNull(sanitized.contexts.runtime)
    assertTrue(hint.attachments.isEmpty())

    assertEquals("Android", sanitized.contexts.operatingSystem?.name)
    assertEquals("15", sanitized.contexts.operatingSystem?.version)
    assertNull(sanitized.contexts.operatingSystem?.kernelVersion)

    val device = sanitized.contexts.device!!
    assertEquals("Pixel Fold", device.model)
    assertEquals(2208, device.screenWidthPixels)
    assertEquals(1840, device.screenHeightPixels)
    assertEquals(12_884_901_888L, device.memorySize)
    assertNull(device.manufacturer)
    assertNull(device.timezone)
  }
}
