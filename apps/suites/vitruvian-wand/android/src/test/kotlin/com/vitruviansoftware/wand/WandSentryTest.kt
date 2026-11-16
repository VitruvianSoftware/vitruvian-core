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

package com.vitruviansoftware.wand

import io.sentry.Attachment
import io.sentry.Breadcrumb
import io.sentry.Hint
import io.sentry.OptionsContainer
import io.sentry.Sentry
import io.sentry.SentryEvent
import io.sentry.SentryLogEvent
import io.sentry.SentryLogLevel
import io.sentry.SentryMetricsEvent
import io.sentry.SentryOpenTelemetryMode
import io.sentry.SentryReplayEvent
import io.sentry.android.core.SentryAndroidOptions
import io.sentry.protocol.App
import io.sentry.protocol.DebugMeta
import io.sentry.protocol.Device
import io.sentry.protocol.FeatureFlag
import io.sentry.protocol.FeatureFlags
import io.sentry.protocol.OperatingSystem
import io.sentry.protocol.SentryId
import io.sentry.protocol.SentryRuntime
import io.sentry.protocol.SentryTransaction
import io.sentry.protocol.TransactionInfo
import io.sentry.protocol.User
import io.sentry.util.Platform
import java.io.File
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WandSentryTest {

  private fun resolvePath(rel: String): File {
    val direct = File(rel)
    if (direct.exists()) return direct
    val base = System.getenv("TEST_SRCDIR") ?: error("TEST_SRCDIR unset and missing $rel")
    return listOf("_main", "vitruvian_core", "")
        .map { sub -> if (sub.isEmpty()) File(base, rel) else File(File(base, sub), rel) }
        .firstOrNull { it.exists() } ?: error("Runfile not found: $rel")
  }

  @Test
  fun manifestDisablesSentryAutoInitAndMainActivityUsesWandSentry() {
    val manifest =
        resolvePath("apps/suites/vitruvian-wand/android/src/main/AndroidManifest.xml").readText()
    assertTrue(
        "Expected io.sentry.auto-init=false in Wand AndroidManifest.xml",
        Regex("""<meta-data[^>]*android:name="io\.sentry\.auto-init"[^>]*android:value="false"""")
            .containsMatchIn(manifest),
    )
    val mainActivity =
        resolvePath(
                "apps/suites/vitruvian-wand/android/src/main/kotlin/com/vitruviansoftware/wand/MainActivity.kt")
            .readText()
    assertTrue(mainActivity.contains("WandSentry.init(this)"))
    assertFalse(Regex("""(?<!Wand)Sentry\.init\(""").containsMatchIn(mainActivity))
  }

  @Test
  fun wandSentryConfiguresNoExtraDataDefaultsAndScrubsEvents() {
    val options = SentryAndroidOptions().apply { distinctId = "pre-existing-id" }
    WandSentry.configureOptions(
        options = options,
        dsn = "https://public@127.0.0.1:1/0",
        release = "vitruvian-wand@0.1.0",
        osVersion = "15",
        deviceModel = "Chromecast HD",
    )

    assertEquals("vitruvian-wand@0.1.0", options.release)
    assertEquals("production", options.environment)
    assertFalse(options.isSendDefaultPii)
    assertNull(options.distinctId)
    assertEquals(0, options.maxBreadcrumbs)
    assertEquals(0, options.maxFeatureFlags)
    assertNull(options.beforeBreadcrumb!!.execute(Breadcrumb.info("tap"), Hint()))
    assertFalse(options.isAttachServerName)
    assertNull(options.serverName)
    assertFalse(options.isAttachThreads)
    assertFalse(options.isSendModules)
    assertFalse(options.isEnableAutoSessionTracking)
    assertFalse(options.isSendClientReports)

    assertFalse(options.isEnableActivityLifecycleBreadcrumbs)
    assertFalse(options.isEnableAppLifecycleBreadcrumbs)
    assertFalse(options.isEnableSystemEventBreadcrumbs)
    assertFalse(options.isEnableSystemEventBreadcrumbsExtras)
    assertFalse(options.isEnableAppComponentBreadcrumbs)
    assertFalse(options.isEnableNetworkEventBreadcrumbs)
    assertFalse(options.isEnableUserInteractionBreadcrumbs)

    assertFalse(options.isAnrEnabled)
    assertFalse(options.isAnrReportInDebug)
    assertFalse(options.isReportHistoricalAnrs)
    assertFalse(options.isAttachAnrThreadDump)
    assertNull(options.anrProfilingSampleRate)
    assertFalse(options.isEnableNdkAppHangTracking)
    assertFalse(options.isTombstoneEnabled)
    assertFalse(options.isReportHistoricalTombstones)
    assertFalse(options.isAttachRawTombstone)
    assertFalse(options.isMemoryLimiterEnabled)
    assertFalse(options.isReportHistoricalMemoryLimiterExits)
    assertFalse(options.isEnableNdk)
    assertFalse(options.isEnableScopeSync)

    assertFalse(options.isAttachScreenshot)
    assertFalse(options.isAttachViewHierarchy)
    assertFalse(options.isEnableFramesTracking)
    assertFalse(options.isCollectAdditionalContext)
    assertFalse(options.isCollectExternalStorageContext)
    assertFalse(options.isEnableRootCheck)
    assertFalse(options.feedbackOptions.isUseShakeGesture)
    assertFalse(options.feedbackOptions.isEnableAttachScreenshot)

    assertFalse(options.isTracingEnabled)
    assertNull(options.tracesSampleRate)
    assertNull(options.tracesSampler)
    assertFalse(options.isEnableAutoActivityLifecycleTracing)
    assertFalse(options.isEnableActivityLifecycleTracingAutoFinish)
    assertFalse(options.isEnableUserInteractionTracing)
    assertFalse(options.isEnableTimeToFullDisplayTracing)
    assertFalse(options.isEnablePerformanceV2)
    assertFalse(options.isEnableStandaloneAppStartTracing)
    assertFalse(options.isEnableAutoTraceIdGeneration)
    assertFalse(options.isEnableScreenTracking)
    assertTrue(options.tracePropagationTargets.isEmpty())
    assertTrue(options.webViewTracing.allowedHosts.isEmpty())
    val tx = SentryTransaction("tx", 0.0, 1.0, emptyList(), emptyMap(), TransactionInfo("m"))
    assertNull(options.beforeSendTransaction!!.execute(tx, Hint()))

    assertNull(options.profilesSampleRate)
    assertNull(options.profilesSampler)
    assertNull(options.profileSessionSampleRate)
    assertFalse(options.isStartProfilerOnAppStart)
    assertFalse(options.isEnableAppStartProfiling)
    assertFalse(options.isContinuousProfilingEnabled)

    assertNull(options.sessionReplay.sessionSampleRate)
    assertNull(options.sessionReplay.onErrorSampleRate)
    assertFalse(options.sessionReplay.isTrackConfiguration)
    assertNull(options.beforeSendReplay!!.execute(SentryReplayEvent(), Hint()))
    assertFalse(options.logs.isEnabled)
    assertNull(
        options.logs.beforeSend!!.execute(
            SentryLogEvent(SentryId(), 0.0, "msg", SentryLogLevel.INFO)))
    assertFalse(options.metrics.isEnabled)
    assertNull(
        options.metrics.beforeSend!!.execute(
            SentryMetricsEvent(SentryId(), 0.0, "metric", "counter", 1.0), Hint()))

    assertFalse(options.isEnableBackpressureHandling)
    assertEquals(SentryOpenTelemetryMode.OFF, options.openTelemetryMode)
    assertFalse(options.isCaptureOpenTelemetryEvents)
    assertFalse(options.isEnableScopePersistence)
    assertFalse(options.isEnableSpotlight)

    val event =
        SentryEvent(RuntimeException("boom")).apply {
          addBreadcrumb(Breadcrumb.info("tap"))
          user =
              User().apply {
                id = "install-id"
                email = "user@example.com"
              }
          dist = "1"
          setTag("isSideLoaded", "true")
          setExtra("secret", "x")
          debugMeta = DebugMeta()
          contexts.setApp(App().apply { permissions = mapOf("BLUETOOTH_SCAN" to "granted") })
          contexts.setDevice(
              Device().apply {
                manufacturer = "Google"
                timezone = TimeZone.getTimeZone("UTC")
              })
          contexts.setOperatingSystem(
              OperatingSystem().apply {
                name = "Android"
                kernelVersion = "6.1"
              })
          contexts.setRuntime(SentryRuntime().apply { name = "ART" })
          contexts.setFeatureFlags(FeatureFlags(listOf(FeatureFlag("flag", true))))
        }
    val hint = Hint().apply { addAttachment(Attachment(byteArrayOf(1), "a.txt")) }
    val sanitized = options.beforeSend!!.execute(event, hint)!!
    assertNull(sanitized.user)
    assertNull(sanitized.breadcrumbs)
    assertNull(sanitized.dist)
    assertTrue(sanitized.extras.isNullOrEmpty())
    assertNull(sanitized.debugMeta)
    assertEquals(mapOf("device.model" to "Chromecast HD", "os.version" to "15"), sanitized.tags)
    assertNull(sanitized.contexts.app)
    assertNull(sanitized.contexts.runtime)
    assertNull(sanitized.contexts.featureFlags)
    assertEquals("Chromecast HD", sanitized.contexts.device?.model)
    assertNull(sanitized.contexts.device?.manufacturer)
    assertNull(sanitized.contexts.device?.timezone)
    assertEquals("Android", sanitized.contexts.operatingSystem?.name)
    assertEquals("15", sanitized.contexts.operatingSystem?.version)
    assertNull(sanitized.contexts.operatingSystem?.kernelVersion)
    assertTrue(hint.attachments.isEmpty())
  }

  @Test
  fun wandSentryInitializesWhenPlatformIsAndroid() {
    val isAndroidField =
        Platform::class.java.getDeclaredField("isAndroid").apply { isAccessible = true }
    val originalIsAndroid = isAndroidField.getBoolean(null)
    try {
      isAndroidField.setBoolean(null, true)
      val thrown =
          try {
            Sentry.init { opts -> opts.dsn = "https://public@127.0.0.1:1/0" }
            null
          } catch (e: IllegalArgumentException) {
            e
          }
      assertNotNull(thrown)
      assertTrue(thrown!!.message!!.contains("SentryAndroid.init"))

      Sentry.init(
          OptionsContainer.create(SentryAndroidOptions::class.java),
          { opts ->
            WandSentry.configureOptions(
                options = opts,
                dsn = "https://public@127.0.0.1:1/0",
                release = "vitruvian-wand@0.1.0",
            )
          },
          true,
      )
      assertTrue(Sentry.isEnabled())
      assertEquals("vitruvian-wand@0.1.0", Sentry.getCurrentScopes().options.release)
      assertEquals(0, Sentry.getCurrentScopes().options.maxBreadcrumbs)
    } finally {
      Sentry.close()
      isAndroidField.setBoolean(null, originalIsAndroid)
    }
  }
}
