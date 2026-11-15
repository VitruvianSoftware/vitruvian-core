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

import io.sentry.Attachment
import io.sentry.Breadcrumb
import io.sentry.Hint
import io.sentry.MainEventProcessor
import io.sentry.SentryEvent
import io.sentry.SentryOptions
import io.sentry.protocol.SentryTransaction
import io.sentry.protocol.TransactionInfo
import io.sentry.protocol.User
import java.io.File
import java.nio.file.Files
import java.util.Locale
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

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
    val dsBuildText = resolvePath("packages/design-system-android/BUILD").readText()
    val runtimeMavenTargets =
        extractRuntimeMavenDeps(appBuildText) + extractRuntimeMavenDeps(dsBuildText)
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
            "packages/design-system-android/BUILD must have an AppInfo.openSourceLicenses entry",
        runtimeMavenTargets,
        coveredTargets,
    )

    val byName = AppInfo.openSourceLicenses.associateBy { it.name }
    assertEquals("Apache-2.0", byName.getValue("AndroidX Annotation").license)
    assertEquals("Apache-2.0", byName.getValue("AndroidX Compose").license)
    assertEquals("MIT", byName.getValue("Sentry SDK").license)
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

    assertTrue(AppInfo.shouldAllowWhileUnpaired("Hosts"))
    assertTrue(AppInfo.shouldAllowWhileUnpaired("About"))
    assertTrue(AppInfo.shouldAllowWhileUnpaired("PhoneBridge"))
    assertFalse(AppInfo.shouldAllowWhileUnpaired("Home"))
    assertFalse(AppInfo.shouldAllowWhileUnpaired("Apps"))
  }

  @Test
  public fun `privacy copy states exact crash server and report contents`() {
    val talkStatement = AppInfo.privacyTrailingStatements.first()
    assertTrue(
        talkStatement.startsWith(
            "This phone talks to the Macs you add, and to Vitruvian Software's crash server if crash reports are on.",
        ),
    )
    assertFalse(talkStatement.contains("talks only to the Macs you add"))

    assertTrue(
        AppInfo.privacyCrashReportsStatement.contains(
            "the error and where in the app it happened, the app version, the Android version, " +
                "and device details such as model, screen size and memory. Never your texts, " +
                "contacts, files, what you type, or your Macs' addresses.",
        ),
    )

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
  }

  @Test
  public fun `configureSentryOptions disables PII breadcrumbs tracing screenshots and view hierarchy`() {
    class AndroidLikeOptions : SentryOptions() {
      var attachScreenshot: Boolean = true
      var attachViewHierarchy: Boolean = true
    }

    val options = AndroidLikeOptions()
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
    assertFalse(options.isSendDefaultPii)
    assertFalse(options.isAttachServerName)
    assertNull(options.serverName)
    assertFalse(options.isSendModules)
    assertFalse(options.isEnableAutoSessionTracking)
    assertFalse(options.isSendClientReports)

    assertEquals(0, options.maxBreadcrumbs)
    assertNull(options.beforeBreadcrumb!!.execute(Breadcrumb.info("tap"), Hint()))
    assertFalse(options.isEnableUserInteractionBreadcrumbs)
    assertFalse(options.isEnableScreenTracking)
    assertTrue(options.gestureTargetLocators.isEmpty())

    assertFalse(options.isEnableUserInteractionTracing)
    assertEquals(false, options.enableTracing)
    assertFalse(options.isTracingEnabled)
    assertNull(options.tracesSampleRate)
    assertNull(options.tracesSampler)
    assertNull(options.profilesSampleRate)
    assertNull(options.profilesSampler)
    assertFalse(options.isProfilingEnabled)
    assertFalse(options.isEnableAppStartProfiling)
    assertFalse(options.isEnableTimeToFullDisplayTracing)
    assertTrue(options.tracePropagationTargets.isEmpty())
    val tx =
        SentryTransaction("tx", 0.0, 1.0, emptyList(), emptyMap(), emptyMap(), TransactionInfo("m"))
    assertNull(options.beforeSendTransaction!!.execute(tx, Hint()))

    assertTrue(options.viewHierarchyExporters.isEmpty())
    assertFalse(options.attachScreenshot)
    assertFalse(options.attachViewHierarchy)
  }

  @Test
  public fun `configureSentryOptions beforeSend strips user IP breadcrumbs and attachments and keeps bounded device details`() {
    val options = SentryOptions()
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

    val rawEvent =
        SentryEvent(RuntimeException("boom")).apply {
          addBreadcrumb(Breadcrumb.info("tap"))
          user = User().apply { email = "user@example.com" }
        }
    val hint =
        Hint().apply {
          screenshot = Attachment.fromScreenshot(byteArrayOf(1, 2, 3))
          viewHierarchy = Attachment(byteArrayOf(4, 5), "view-hierarchy.json")
          addAttachment(Attachment(byteArrayOf(6, 7), "extra.txt"))
        }

    // MainEventProcessor runs before beforeSend in SentryClient and sets user.ipAddress="{{auto}}".
    val processed = MainEventProcessor(options).process(rawEvent, hint)
    val sanitized = options.beforeSend!!.execute(processed, hint)!!

    assertEquals("vitruvian-remote@0.1.40", sanitized.release)
    assertNotNull(sanitized.exceptions)
    assertTrue(sanitized.exceptions!!.isNotEmpty())
    assertNull(sanitized.user)
    assertNull(sanitized.breadcrumbs)
    assertNull(sanitized.request)
    assertNull(sanitized.serverName)
    assertNull(hint.screenshot)
    assertNull(hint.viewHierarchy)
    assertTrue(hint.attachments.isEmpty())

    assertEquals("Android", sanitized.contexts.operatingSystem?.name)
    assertEquals("15", sanitized.contexts.operatingSystem?.version)
    val device = sanitized.contexts.device!!
    assertEquals("Pixel Fold", device.model)
    assertEquals(2208, device.screenWidthPixels)
    assertEquals(1840, device.screenHeightPixels)
    assertEquals(12_884_901_888L, device.memorySize)
    assertNull(device.name)
    assertNull(device.id)
    assertNull(device.timezone)
    assertNull(device.locale)
  }

  @Test
  public fun `clearSentryCache removes SDK cache and outbox dirs without touching unrelated cache files`() {
    val appCacheDir = Files.createTempDirectory("vitruvian-sentry-cache-test").toFile()
    try {
      val options = SentryOptions()
      AppInfo.configureSentryOptions(
          options = options,
          dsn = "https://examplePublicKey@o0.ingest.sentry.io/0",
          appVersion = "0.1.40",
          appCacheDir = appCacheDir,
      )

      val dsnCacheDir = File(options.cacheDirPath!!)
      val outboxDir = File(options.outboxPath!!)
      val sentryBaseDir = AppInfo.sentryCacheDir(appCacheDir)
      assertTrue(dsnCacheDir.absolutePath.startsWith(sentryBaseDir.absolutePath + File.separator))
      assertEquals(File(dsnCacheDir, "outbox").absolutePath, outboxDir.absolutePath)

      dsnCacheDir.mkdirs()
      outboxDir.mkdirs()
      val queuedEnvelope = File(outboxDir, "queued.envelope").apply { writeText("envelope") }
      val cachedEnvelope = File(dsnCacheDir, "cached.envelope").apply { writeText("cached") }
      val legacyDir = File(appCacheDir, "io.sentry.cache").apply { mkdirs() }
      val legacyScope = File(legacyDir, "scope.json").apply { writeText("{}") }
      val unrelatedDir = File(appCacheDir, "http").apply { mkdirs() }
      val unrelatedFile = File(unrelatedDir, "keep.bin").apply { writeText("keep") }

      AppInfo.clearSentryCache(appCacheDir)

      assertFalse(sentryBaseDir.exists())
      assertFalse(dsnCacheDir.exists())
      assertFalse(outboxDir.exists())
      assertFalse(queuedEnvelope.exists())
      assertFalse(cachedEnvelope.exists())
      assertFalse(legacyDir.exists())
      assertFalse(legacyScope.exists())
      assertTrue(unrelatedFile.exists())

      AppInfo.clearSentryCache(appCacheDir)
      assertTrue(unrelatedFile.exists())
    } finally {
      appCacheDir.deleteRecursively()
    }
  }

  @Test
  public fun `AndroidManifest disables Sentry auto-init`() {
    val manifestFile = resolvePath("apps/mobile/vitruvian-remote/src/main/AndroidManifest.xml")
    val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
    val doc = factory.newDocumentBuilder().parse(manifestFile)
    val androidNs = "http://schemas.android.com/apk/res/android"
    val metaNodes = doc.getElementsByTagName("meta-data")
    val autoInitValues =
        (0 until metaNodes.length)
            .mapNotNull { metaNodes.item(it) as? Element }
            .filter { el ->
              el.parentNode?.nodeName == "application" &&
                  el.getAttributeNS(androidNs, "name") == "io.sentry.auto-init"
            }
            .map { el -> el.getAttributeNS(androidNs, "value") }
    assertEquals(listOf("false"), autoInitValues)
  }
}
