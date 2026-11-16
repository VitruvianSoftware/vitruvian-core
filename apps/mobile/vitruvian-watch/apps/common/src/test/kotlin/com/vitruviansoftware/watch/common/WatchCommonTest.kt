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

import dev.vitruvian.crashprivacy.DeviceField
import io.sentry.Attachment
import io.sentry.Breadcrumb
import io.sentry.Hint
import io.sentry.MainEventProcessor
import io.sentry.OptionsContainer
import io.sentry.Sentry
import io.sentry.SentryEvent
import io.sentry.android.core.SentryAndroidOptions
import io.sentry.protocol.App
import io.sentry.protocol.DebugMeta
import io.sentry.protocol.Device
import io.sentry.protocol.FeatureFlag
import io.sentry.protocol.FeatureFlags
import io.sentry.protocol.OperatingSystem
import io.sentry.protocol.Request
import io.sentry.protocol.SentryRuntime
import io.sentry.protocol.SentryThread
import io.sentry.protocol.User
import io.sentry.util.Platform
import java.io.File
import java.util.EnumSet
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
  fun watchSentryStripsDeviceAndOsContextsAndMatchesOriginMainReleaseEnvDsn() {
    assertEquals(EnumSet.of(DeviceField.APP_VERSION), WatchSentry.KEPT_DEVICE_FIELDS)

    val defaultOptions = SentryAndroidOptions()
    WatchSentry.configureOptions(options = defaultOptions)
    assertEquals(WatchSentry.DEFAULT_DSN, defaultOptions.dsn)
    assertEquals("vitruvian-watch@1.0", defaultOptions.release)
    assertEquals("production", defaultOptions.environment)

    for (appName in
        listOf(
            "vitruvian-watch-code",
            "vitruvian-watch-home",
            "vitruvian-watch-remote",
            "vitruvian-pulse",
        )) {
      val options =
          SentryAndroidOptions().apply {
            distinctId = "pre-existing-id"
            setTag("device.model", "Pixel Watch 3")
            setTag("os.version", "14")
          }
      WatchSentry.configureOptions(
          options = options,
          appName = appName,
          dsn = "https://public@127.0.0.1:1/0",
      )

      assertEquals("https://public@127.0.0.1:1/0", options.dsn)
      assertEquals("$appName@1.0", options.release)
      assertEquals("production", options.environment)
      assertTrue(options.dataCollection.isExplicitlyConfigured)
      assertFalse(options.dataCollectionResolver.isUserInfo)
      assertNull(options.distinctId)
      assertEquals(0, options.maxBreadcrumbs)
      assertTrue(options.tags.isEmpty())

      val event =
          SentryEvent(RuntimeException("boom")).apply {
            addBreadcrumb(Breadcrumb.info("tap"))
            user =
                User().apply {
                  id = "install-id"
                  email = "user@example.com"
                }
            dist = "1"
            setTag("device.model", "Pixel Watch 3")
            setTag("os.version", "14")
            setTag("isSideLoaded", "true")
            setExtra("secret", "x")
            debugMeta = DebugMeta()
            serverName = "james-macbook-pro"
            threads = listOf(SentryThread().apply { name = "main" })
            setModule("io.sentry:sentry", "8.64.0")
            request = Request().apply { url = "http://10.0.2.2:7499/v1/state" }
            contexts.setApp(
                App().apply {
                  appVersion = "1.0"
                  permissions = mapOf("VIBRATE" to "granted")
                })
            contexts.setDevice(
                Device().apply {
                  model = "Pixel Watch 3"
                  screenWidthPixels = 454
                  screenHeightPixels = 454
                  memorySize = 2_147_483_648L
                  manufacturer = "Google"
                  timezone = TimeZone.getTimeZone("UTC")
                })
            contexts.setOperatingSystem(
                OperatingSystem().apply {
                  name = "Android"
                  version = "14"
                  kernelVersion = "6.1"
                })
            contexts.setRuntime(SentryRuntime().apply { name = "ART" })
            contexts.setFeatureFlags(FeatureFlags(listOf(FeatureFlag("flag", true))))
          }
      val hint = Hint().apply { addAttachment(Attachment(byteArrayOf(1), "a.txt")) }
      val processed = MainEventProcessor(options).process(event, hint)
      val sanitized = options.beforeSend!!.execute(processed, hint)!!

      assertEquals("$appName@1.0", sanitized.release)
      assertEquals("production", sanitized.environment)
      assertNull(sanitized.user)
      assertNull(sanitized.breadcrumbs)
      assertNull(sanitized.dist)
      assertTrue(sanitized.extras.isNullOrEmpty())
      assertNull(sanitized.debugMeta)
      // What 7.14 sent on origin/main and these apps must no longer send.
      assertNull(sanitized.serverName)
      assertTrue(sanitized.threads.isNullOrEmpty())
      assertNull(sanitized.getModule("io.sentry:sentry"))
      assertNull(sanitized.request)
      assertNull(sanitized.tags)
      assertTrue(sanitized.contexts.isEmpty())
      assertNull(sanitized.contexts.device)
      assertNull(sanitized.contexts.operatingSystem)
      assertNull(sanitized.contexts.app)
      assertNull(sanitized.contexts.runtime)
      assertNull(sanitized.contexts.featureFlags)
      assertTrue(hint.attachments.isEmpty())
    }
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
