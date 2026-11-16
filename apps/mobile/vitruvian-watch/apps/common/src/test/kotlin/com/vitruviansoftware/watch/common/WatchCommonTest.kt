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

package com.vitruviansoftware.watch.common

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

class WatchCommonTest {

  @Test
  fun homelabGaugeReflectsHealthyAndAlertStates() {
    val healthy =
        HomelabSummary(
                readyNodes = 3,
                totalNodes = 3,
                healthyPods = 94,
                totalPods = 94,
                firingAlerts = 0,
            )
            .deriveGauge()
    assertEquals("100%", healthy.shortText)
    assertEquals(100f, healthy.value, 0.01f)
    assertEquals(PulseTone.Healthy, healthy.tone)

    val degraded =
        HomelabSummary(
                readyNodes = 3,
                totalNodes = 3,
                healthyPods = 90,
                totalPods = 94,
                firingAlerts = 2,
            )
            .deriveGauge()
    assertEquals("2!", degraded.shortText)
    assertEquals(PulseTone.Critical, degraded.tone)
    assertTrue(degraded.value < 80f)
  }

  @Test
  fun mergeQueueGaugeTracksQueuedAndFailingPrs() {
    val queued = MergeQueueSummary(openPrs = 4, queuedPrs = 1, failingPrs = 0).deriveGauge()
    assertEquals("1Q", queued.shortText)
    assertEquals(PulseTone.Warning, queued.tone)
    assertEquals(100f, queued.value, 0.01f)

    val failing = MergeQueueSummary(openPrs = 4, queuedPrs = 1, failingPrs = 1).deriveGauge()
    assertEquals("1✗", failing.shortText)
    assertEquals(PulseTone.Critical, failing.tone)
    assertEquals(75f, failing.value, 0.01f)
  }

  @Test
  fun roborockGaugeFormatsCleaningAndDockedStates() {
    val cleaning =
        RoborockSummary(
                state = "cleaning",
                batteryPercent = 86,
                roomName = "Lake Office",
                cleanAreaSqm = 18,
            )
            .deriveGauge()
    assertEquals("CLN", cleaning.shortText)
    assertEquals(PulseTone.Warning, cleaning.tone)
    assertTrue(cleaning.longText.contains("Lake Office"))

    val docked = RoborockSummary(state = "docked", batteryPercent = 100).deriveGauge()
    assertEquals("100%", docked.shortText)
    assertEquals(PulseTone.Healthy, docked.tone)
  }

  @Test
  fun rotaryVolumeAccumulatorIntegratesFractionalCrownScrollAndUnmutes() {
    val acc = RotaryVolumeAccumulator(pixelsPerStep = 20f)

    // Sub-detent scroll should not step volume yet.
    val step0 = acc.onScroll(currentVolume = 40, muted = true, scrollPixels = 12f)
    assertEquals(40, step0.newVolume)
    assertEquals(0, step0.deltaSteps)
    assertFalse(step0.unmuted)

    // Crossing the 20px detent steps volume +1 and unmutes.
    val step1 = acc.onScroll(currentVolume = 40, muted = true, scrollPixels = 10f)
    assertEquals(41, step1.newVolume)
    assertEquals(1, step1.deltaSteps)
    assertTrue(step1.unmuted)

    // Reversing direction clears residual and clamps at bounds.
    val stepDown = acc.onScroll(currentVolume = 1, muted = false, scrollPixels = -60f)
    assertEquals(0, stepDown.newVolume)
    assertEquals(-1, stepDown.deltaSteps)
  }

  @Test
  fun speakerRoomAndRoborockPayloadsMatchCliAndMcpContracts() {
    assertEquals(
        "speaker-broadcast --enable --set-target lake_office",
        SpeakerRoom.LAKE_OFFICE.toSpeakerBroadcastCliCommand(),
    )
    assertEquals(
        "speaker-broadcast --disable",
        SpeakerRoom.MUTE.toSpeakerBroadcastCliCommand(),
    )
    assertEquals(
        """{"tool":"roborock","action":"clean_room_office","segmentId":16}""",
        RoborockAction.CLEAN_OFFICE.toJsonPayload(),
    )
  }

  @Test
  fun voiceRouterSelectsSpecialistAgentAndEncodesApprovals() {
    val ridgeReq = VoiceAgentRouter.route("Check why pod grafana is flapping in k3s")
    assertEquals(SpecialistAgent.RIDGE, ridgeReq.routedAgent)

    val scoutReq = VoiceAgentRouter.route("Enqueue pull request 3839 in merge queue")
    assertEquals(SpecialistAgent.SCOUT, scoutReq.routedAgent)

    val atlasReq = VoiceAgentRouter.route("Preview pulumi gateway route changes")
    assertEquals(SpecialistAgent.ATLAS, atlasReq.routedAgent)

    val item =
        PendingApprovalItem(
            id = "pr-3839",
            title = "PR #3839",
            subtitle = "Daytona Platinum 126506",
            agent = SpecialistAgent.SCOUT,
            prNumber = 3839,
        )
    assertEquals(
        """{"itemId":"pr-3839","decision":"approve_enqueue","agent":"scout","prNumber":3839}""",
        VoiceAgentRouter.encodeApproval(item, ApprovalDecision.APPROVE_AND_ENQUEUE),
    )
  }

  private fun resolvePath(rel: String): File {
    val direct = File(rel)
    if (direct.exists()) return direct
    val base = System.getenv("TEST_SRCDIR") ?: error("TEST_SRCDIR unset and missing $rel")
    return listOf("_main", "vitruvian_core", "")
        .map { sub -> if (sub.isEmpty()) File(base, rel) else File(File(base, sub), rel) }
        .firstOrNull { it.exists() } ?: error("Runfile not found: $rel")
  }

  @Test
  fun watchManifestsDisableSentryAutoInit() {
    val manifests =
        listOf(
            "apps/mobile/vitruvian-watch/apps/common/src/main/AndroidManifest.xml",
            "apps/mobile/vitruvian-watch/apps/code/src/main/AndroidManifest.xml",
            "apps/mobile/vitruvian-watch/apps/home-control/src/main/AndroidManifest.xml",
            "apps/mobile/vitruvian-watch/apps/remote/src/main/AndroidManifest.xml",
            "apps/mobile/vitruvian-watch/apps/vitruvian-pulse/src/main/AndroidManifest.xml",
        )
    val pattern =
        Regex("""<meta-data[^>]*android:name="io\.sentry\.auto-init"[^>]*android:value="false"""")
    for (manifestPath in manifests) {
      val manifest = resolvePath(manifestPath).readText()
      assertTrue(
          "Missing io.sentry.auto-init=false in $manifestPath", pattern.containsMatchIn(manifest))
    }
  }

  @Test
  fun watchSentryConfiguresNoExtraDataDefaultsAndScrubsEvents() {
    val options = SentryAndroidOptions().apply { distinctId = "pre-existing-id" }
    WatchSentry.configureOptions(
        options = options,
        appName = "vitruvian-watch-test",
        dsn = "https://public@127.0.0.1:1/0",
        osVersion = "14",
        deviceModel = "Pixel Watch 3",
    )

    assertEquals("vitruvian-watch-test@1.0", options.release)
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
          contexts.setApp(App().apply { permissions = mapOf("VIBRATE" to "granted") })
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
    assertEquals(mapOf("device.model" to "Pixel Watch 3", "os.version" to "14"), sanitized.tags)
    assertNull(sanitized.contexts.app)
    assertNull(sanitized.contexts.runtime)
    assertNull(sanitized.contexts.featureFlags)
    assertEquals("Pixel Watch 3", sanitized.contexts.device?.model)
    assertNull(sanitized.contexts.device?.manufacturer)
    assertNull(sanitized.contexts.device?.timezone)
    assertEquals("Android", sanitized.contexts.operatingSystem?.name)
    assertEquals("14", sanitized.contexts.operatingSystem?.version)
    assertNull(sanitized.contexts.operatingSystem?.kernelVersion)
    assertTrue(hint.attachments.isEmpty())
  }

  @Test
  fun watchSentryInitializesWhenPlatformIsAndroid() {
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
            WatchSentry.configureOptions(
                options = opts,
                appName = "vitruvian-watch-test",
                dsn = "https://public@127.0.0.1:1/0",
            )
          },
          true,
      )
      assertTrue(Sentry.isEnabled())
      assertEquals("vitruvian-watch-test@1.0", Sentry.getCurrentScopes().options.release)
      assertEquals(0, Sentry.getCurrentScopes().options.maxBreadcrumbs)
    } finally {
      Sentry.close()
      isAndroidField.setBoolean(null, originalIsAndroid)
    }
  }
}
