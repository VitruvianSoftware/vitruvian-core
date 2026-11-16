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

import io.sentry.Attachment
import io.sentry.Breadcrumb
import io.sentry.Hint
import io.sentry.MainEventProcessor
import io.sentry.OptionsContainer
import io.sentry.Scope
import io.sentry.Sentry
import io.sentry.SentryEnvelope
import io.sentry.SentryEvent
import io.sentry.SentryLogEvent
import io.sentry.SentryLogLevel
import io.sentry.SentryMetricsEvent
import io.sentry.SentryOpenTelemetryMode
import io.sentry.SentryOptions
import io.sentry.SentryReplayEvent
import io.sentry.android.core.SentryAndroidOptions
import io.sentry.android.core.cache.AndroidEnvelopeCache
import io.sentry.cache.EnvelopeCache
import io.sentry.cache.PersistingOptionsObserver
import io.sentry.protocol.App
import io.sentry.protocol.DebugMeta
import io.sentry.protocol.Device
import io.sentry.protocol.FeatureFlag
import io.sentry.protocol.FeatureFlags
import io.sentry.protocol.Message
import io.sentry.protocol.OperatingSystem
import io.sentry.protocol.SentryId
import io.sentry.protocol.SentryRuntime
import io.sentry.protocol.SentryTransaction
import io.sentry.protocol.TransactionInfo
import io.sentry.protocol.User
import io.sentry.util.Platform
import java.io.File
import java.io.StringWriter
import java.nio.file.Files
import java.util.EnumSet
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

public class CrashPrivacyTest {
  private fun resolvePath(rel: String): File {
    val direct = File(rel)
    if (direct.exists()) return direct
    val base = System.getenv("TEST_SRCDIR") ?: error("TEST_SRCDIR unset and missing $rel")
    return listOf("_main", "vitruvian_core", "")
        .map { sub -> if (sub.isEmpty()) File(base, rel) else File(File(base, sub), rel) }
        .firstOrNull { it.exists() } ?: error("Runfile not found: $rel")
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
  public fun `configurePrivateSentry does not use reflection`() {
    val reflectionSample =
        "target.javaClass.getMethod(\"setAttachScreenshot\", Boolean::class.javaPrimitiveType)"
    assertTrue(
        "Reflection detector must catch reflection if reintroduced",
        findForbiddenSentryReflectionTokens(reflectionSample).isNotEmpty(),
    )

    val source =
        resolvePath(
                "packages/android-crash-privacy/src/main/kotlin/dev/vitruvian/crashprivacy/CrashPrivacy.kt")
            .readText()
    assertEquals(emptyList<String>(), findForbiddenSentryReflectionTokens(source))
  }

  @Test
  public fun `configurePrivateSentry sets Android and Java SDK privacy options directly`() {
    val options =
        SentryAndroidOptions().apply {
          distinctId = "pre-existing-id"
          setTag("stale", "value")
        }
    configurePrivateSentry(
        options = options,
        dsn = "https://examplePublicKey@o0.ingest.sentry.io/0",
        keepDeviceFields = EnumSet.allOf(DeviceField::class.java),
        release = "vitruvian-remote@0.1.40",
        device =
            PrivateSentryDevice(
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
    assertNull(options.distinctId)
    assertEquals(0, options.maxBreadcrumbs)
    assertEquals(0, options.maxFeatureFlags)
    assertNull(options.beforeBreadcrumb!!.execute(Breadcrumb.info("tap"), Hint()))
    val scope = Scope(options).apply { addBreadcrumb(Breadcrumb.info("tap")) }
    assertTrue(scope.breadcrumbs.isEmpty())
    assertFalse(options.isAttachServerName)
    assertNull(options.serverName)
    assertFalse(options.isAttachThreads)
    assertFalse(options.isSendModules)
    assertFalse(options.isEnableAutoSessionTracking)
    assertFalse(options.isSendClientReports)

    // Android auto-breadcrumbs.
    assertFalse(options.isEnableActivityLifecycleBreadcrumbs)
    assertFalse(options.isEnableAppLifecycleBreadcrumbs)
    assertFalse(options.isEnableSystemEventBreadcrumbs)
    assertFalse(options.isEnableSystemEventBreadcrumbsExtras)
    assertFalse(options.isEnableAppComponentBreadcrumbs)
    assertFalse(options.isEnableNetworkEventBreadcrumbs)
    assertFalse(options.isEnableUserInteractionBreadcrumbs)

    // Android ANR / tombstone / memory-limiter / NDK.
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

    // Android screenshots, view hierarchy, frames, extra IPC/storage/root checks, and feedback.
    assertFalse(options.isAttachScreenshot)
    assertFalse(options.isAttachViewHierarchy)
    assertFalse(options.isEnableFramesTracking)
    assertFalse(options.isCollectAdditionalContext)
    assertFalse(options.isCollectExternalStorageContext)
    assertFalse(options.isEnableRootCheck)
    assertFalse(options.feedbackOptions.isUseShakeGesture)
    assertFalse(options.feedbackOptions.isEnableAttachScreenshot)

    // Tracing & profiling.
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
    assertNull(options.profilesSampleRate)
    assertNull(options.profilesSampler)
    assertFalse(options.isProfilingEnabled)
    assertNull(options.profileSessionSampleRate)
    assertFalse(options.isStartProfilerOnAppStart)
    assertFalse(options.isEnableAppStartProfiling)
    assertFalse(options.isContinuousProfilingEnabled)
    assertTrue(options.tracePropagationTargets.isEmpty())
    assertTrue(options.webViewTracing.allowedHosts.isEmpty())
    val tx = SentryTransaction("tx", 0.0, 1.0, emptyList(), emptyMap(), TransactionInfo("m"))
    assertNull(options.beforeSendTransaction!!.execute(tx, Hint()))

    // Replay, logs, metrics, backpressure, OTel, scope persistence, spotlight.
    assertNull(options.sessionReplay.sessionSampleRate)
    assertNull(options.sessionReplay.onErrorSampleRate)
    assertFalse(options.sessionReplay.isTrackConfiguration)
    assertFalse(options.sessionReplay.isSessionReplayEnabled)
    assertFalse(options.sessionReplay.isSessionReplayForErrorsEnabled)
    assertNull(options.beforeSendReplay!!.execute(SentryReplayEvent(), Hint()))

    assertFalse(options.logs.isEnabled)
    assertNotNull(options.logs.beforeSend)
    assertNull(
        options.logs.beforeSend!!.execute(
            SentryLogEvent(SentryId(), 0.0, "msg", SentryLogLevel.INFO)))
    assertFalse(options.metrics.isEnabled)
    assertNotNull(options.metrics.beforeSend)
    assertNull(
        options.metrics.beforeSend!!.execute(
            SentryMetricsEvent(SentryId(), 0.0, "metric", "counter", 1.0),
            Hint(),
        ))

    assertFalse(options.isEnableBackpressureHandling)
    assertEquals(SentryOpenTelemetryMode.OFF, options.openTelemetryMode)
    assertFalse(options.isCaptureOpenTelemetryEvents)
    assertFalse(options.isEnableScopePersistence)
    assertFalse(options.isEnableSpotlight)
    assertEquals(
        setOf(
            "io.sentry.UncaughtExceptionHandlerIntegration",
            "io.sentry.ShutdownHookIntegration",
        ),
        options.integrations.map { it.javaClass.name }.toSet(),
    )

    assertEquals(mapOf("device.model" to "Pixel Fold", "os.version" to "15"), options.tags)
  }

  /*
   * Plain Java io.sentry:sentry:7.14.0 defaults (origin/main baseline for Watch & Wand):
   *
   * Verified against sentry-7.14.0.jar:
   * - Explicit options set by Watch & Wand on origin/main:
   *   - Watch (code, home-control, remote, vitruvian-pulse): dsn, release="$appName@1.0",
   *     environment="production".
   *   - Wand: dsn, release="vitruvian-wand@0.1.0", environment="production".
   * - Default integrations in SentryOptions():
   *   - UncaughtExceptionHandlerIntegration (enableUncaughtExceptionHandler = true)
   *   - ShutdownHookIntegration (enableShutdownHook = true)
   *   - SpotlightIntegration (registered, inert while enableSpotlight = false)
   *   - Zero Android integrations (no ANR, NDK, tombstones, auto-breadcrumbs, screenshots,
   *     view hierarchy, or frame tracking).
   * - Default event processors & contexts in SentryOptions():
   *   - MainEventProcessor, DuplicateEventDetectionEventProcessor (enableDeduplication = true).
   *   - SentryRuntimeEventProcessor (contexts.runtime = java.vendor/java.version) was added ONLY
   *     when Platform.isJvm() == true (!"The Android Project".equals(java.vendor)); on Android,
   *     Platform.isJvm() is false so SentryRuntimeEventProcessor was NOT registered.
   *   - No processor in sentry-7.14.0.jar sets contexts.device, contexts.operatingSystem,
   *     contexts.app, contexts.browser, or contexts.gpu. On Android, event.contexts was empty {}
   *     and no device/OS tags were added.
   * - Default PII, breadcrumbs, and telemetry options in SentryOptions():
   *   - sendDefaultPii = false (MainEventProcessor.mergeUser set user.ipAddress="{{auto}}" when
   *     user was null; configurePrivateSentry drops event.user completely and sends less).
   *   - maxBreadcrumbs = 100 with zero auto-breadcrumb integrations (no breadcrumbs captured unless
   *     added manually; Watch/Wand added none).
   *   - attachStacktrace = true, attachThreads = false.
   *   - attachServerName = true (stripped to false / null here).
   *   - sendModules = true, enableAutoSessionTracking = true, sendClientReports = true (all
   *     disabled here).
   *   - tracesSampleRate = null, profilesSampleRate = null (tracing and profiling off).
   *
   * Therefore Watch & Wand may keep ONLY dsn, release (DeviceField.APP_VERSION), environment,
   * core crash fields (event_id, timestamp, platform, level, sdk, scrubbed exceptions/message),
   * and zero device/OS/app/runtime contexts or tags.
   */
  @Test
  public fun `configurePrivateSentry Watch and Wand mode keeps only release and environment with zero device or OS fields`() {
    val options =
        SentryAndroidOptions().apply {
          release = "prepopulated-from-manifest@9.9.9"
          setTag("device.model", "stale-model")
          setTag("os.version", "99")
        }
    configurePrivateSentry(
        options = options,
        dsn = "https://examplePublicKey@o0.ingest.sentry.io/0",
        keepDeviceFields = setOf(DeviceField.APP_VERSION),
        release = "vitruvian-wand@0.1.0",
        environment = "production",
        device =
            PrivateSentryDevice(
                androidRelease = "15",
                model = "Pixel Watch 3",
                screenWidthPx = 454,
                screenHeightPx = 454,
                memorySizeBytes = 2_147_483_648L,
            ),
    )

    assertEquals("https://examplePublicKey@o0.ingest.sentry.io/0", options.dsn)
    assertEquals("vitruvian-wand@0.1.0", options.release)
    assertEquals("production", options.environment)
    assertTrue(options.tags.isEmpty())

    val rawEvent =
        SentryEvent(RuntimeException("boom")).apply {
          addBreadcrumb(Breadcrumb.info("tap"))
          user =
              User().apply {
                id = "install-id"
                email = "user@example.com"
                ipAddress = "{{auto}}"
              }
          dist = "1"
          setTag("device.model", "Pixel Watch 3")
          setTag("os.version", "15")
          setTag("isSideLoaded", "true")
          setExtra("secret", "x")
          debugMeta = DebugMeta()
          contexts.setApp(App().apply { appVersion = "0.1.0" })
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
                version = "15"
                kernelVersion = "6.1"
              })
          contexts.setRuntime(SentryRuntime().apply { name = "ART" })
          contexts.setFeatureFlags(FeatureFlags(listOf(FeatureFlag("flag", true))))
        }
    val hint = Hint().apply { addAttachment(Attachment(byteArrayOf(1), "a.txt")) }
    val processed = MainEventProcessor(options).process(rawEvent, hint)
    val sanitized = options.beforeSend!!.execute(processed, hint)!!

    assertEquals("vitruvian-wand@0.1.0", sanitized.release)
    assertEquals("production", sanitized.environment)
    assertNull(sanitized.user)
    assertNull(sanitized.breadcrumbs)
    assertNull(sanitized.dist)
    assertTrue(sanitized.extras.isNullOrEmpty())
    assertNull(sanitized.debugMeta)
    assertNull(sanitized.tags)
    assertTrue(sanitized.contexts.isEmpty())
    assertNull(sanitized.contexts.device)
    assertNull(sanitized.contexts.operatingSystem)
    assertNull(sanitized.contexts.app)
    assertNull(sanitized.contexts.runtime)
    assertNull(sanitized.contexts.featureFlags)
    assertTrue(hint.attachments.isEmpty())
  }

  @Test
  public fun `configurePrivateSentry keeps only the exact DeviceField flags requested`() {
    val fullDevice =
        PrivateSentryDevice(
            androidRelease = "15",
            model = "Pixel Fold",
            screenWidthPx = 2208,
            screenHeightPx = 1840,
            memorySizeBytes = 12_884_901_888L,
        )

    fun runWith(fields: Set<DeviceField>): Pair<SentryAndroidOptions, SentryEvent> {
      val options = SentryAndroidOptions().apply { release = "manifest-default@1.0" }
      configurePrivateSentry(
          options = options,
          dsn = "https://examplePublicKey@o0.ingest.sentry.io/0",
          keepDeviceFields = fields,
          release = "app@1.2.3",
          device = fullDevice,
      )
      val raw =
          SentryEvent(RuntimeException("boom")).apply {
            release = "raw@9.9.9"
            contexts.setDevice(Device().apply { model = "Injected" })
            contexts.setOperatingSystem(OperatingSystem().apply { version = "99" })
          }
      val sanitized =
          options.beforeSend!!.execute(MainEventProcessor(options).process(raw, Hint()), Hint())!!
      return options to sanitized
    }

    val (noneOpts, noneEvent) = runWith(emptySet())
    assertNull(noneOpts.release)
    assertNull(noneEvent.release)
    assertTrue(noneOpts.tags.isEmpty())
    assertNull(noneEvent.tags)
    assertNull(noneEvent.contexts.device)
    assertNull(noneEvent.contexts.operatingSystem)

    val (modelOpts, modelEvent) = runWith(setOf(DeviceField.MODEL))
    assertNull(modelOpts.release)
    assertNull(modelEvent.release)
    assertEquals(mapOf("device.model" to "Pixel Fold"), modelOpts.tags)
    assertEquals(mapOf("device.model" to "Pixel Fold"), modelEvent.tags)
    assertNull(modelEvent.contexts.operatingSystem)
    assertEquals("Pixel Fold", modelEvent.contexts.device!!.model)
    assertNull(modelEvent.contexts.device!!.screenWidthPixels)
    assertNull(modelEvent.contexts.device!!.screenHeightPixels)
    assertNull(modelEvent.contexts.device!!.memorySize)

    val (screenOpts, screenEvent) = runWith(setOf(DeviceField.SCREEN))
    assertTrue(screenOpts.tags.isEmpty())
    assertNull(screenEvent.tags)
    assertNull(screenEvent.contexts.operatingSystem)
    assertNull(screenEvent.contexts.device!!.model)
    assertEquals(2208, screenEvent.contexts.device!!.screenWidthPixels)
    assertEquals(1840, screenEvent.contexts.device!!.screenHeightPixels)
    assertNull(screenEvent.contexts.device!!.memorySize)

    val (_, memEvent) = runWith(setOf(DeviceField.MEMORY))
    assertNull(memEvent.tags)
    assertNull(memEvent.contexts.operatingSystem)
    assertNull(memEvent.contexts.device!!.model)
    assertNull(memEvent.contexts.device!!.screenWidthPixels)
    assertEquals(12_884_901_888L, memEvent.contexts.device!!.memorySize)

    val (osOpts, osEvent) = runWith(setOf(DeviceField.OS_VERSION))
    assertEquals(mapOf("os.version" to "15"), osOpts.tags)
    assertEquals(mapOf("os.version" to "15"), osEvent.tags)
    assertNull(osEvent.contexts.device)
    assertEquals("Android", osEvent.contexts.operatingSystem!!.name)
    assertEquals("15", osEvent.contexts.operatingSystem!!.version)
  }

  @Test
  public fun `configurePrivateSentry beforeSend strips Android contexts user tags dist extras and attachments and keeps bounded device details`() {
    val options = SentryAndroidOptions()
    configurePrivateSentry(
        options = options,
        dsn = "https://examplePublicKey@o0.ingest.sentry.io/0",
        keepDeviceFields = EnumSet.allOf(DeviceField::class.java),
        release = "vitruvian-remote@0.1.40",
        device =
            PrivateSentryDevice(
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
          user =
              User().apply {
                id = "install-id"
                email = "user@example.com"
                ipAddress = "{{auto}}"
              }
          dist = "144"
          setTag("isSideLoaded", "true")
          setTag("installerStore", "com.android.vending")
          setExtra("secret", "1")
          debugMeta = DebugMeta()
          contexts.setApp(
              App().apply {
                permissions = mapOf("READ_SMS" to "granted")
                appName = "Vitruvian Remote"
                appIdentifier = "dev.vitruvian.remote"
                inForeground = true
              })
          contexts.setDevice(
              Device().apply {
                manufacturer = "Google"
                brand = "google"
                locale = "en_US"
                timezone = TimeZone.getTimeZone("UTC")
                storageSize = 128_000_000_000L
                batteryLevel = 80f
                id = "install-id"
              })
          contexts.setOperatingSystem(
              OperatingSystem().apply {
                name = "Android"
                version = "15"
                build = "AP4A"
                kernelVersion = "6.1"
                isRooted = false
              })
          contexts["os_linux"] = OperatingSystem().apply { name = "Linux" }
          contexts.setRuntime(SentryRuntime().apply { name = "Android Runtime" })
          contexts.setFeatureFlags(FeatureFlags(listOf(FeatureFlag("flag", true))))
        }
    val hint = Hint().apply { addAttachment(Attachment(byteArrayOf(6, 7), "extra.txt")) }

    val processed = MainEventProcessor(options).process(rawEvent, hint)
    assertNull(processed.threads)
    val sanitized = options.beforeSend!!.execute(processed, hint)!!

    assertEquals("vitruvian-remote@0.1.40", sanitized.release)
    assertNotNull(sanitized.exceptions)
    assertTrue(sanitized.exceptions!!.isNotEmpty())
    assertNull(sanitized.user)
    assertNull(sanitized.breadcrumbs)
    assertNull(sanitized.request)
    assertNull(sanitized.serverName)
    assertNull(sanitized.dist)
    assertTrue(sanitized.extras.isNullOrEmpty())
    assertNull(sanitized.debugMeta)
    assertEquals(mapOf("device.model" to "Pixel Fold", "os.version" to "15"), sanitized.tags)
    assertTrue(sanitized.threads.isNullOrEmpty())
    assertNull(sanitized.contexts.app)
    assertNull(sanitized.contexts.runtime)
    assertNull(sanitized.contexts.featureFlags)
    assertNull(sanitized.contexts["os_linux"])
    assertTrue(hint.attachments.isEmpty())

    assertEquals("Android", sanitized.contexts.operatingSystem?.name)
    assertEquals("15", sanitized.contexts.operatingSystem?.version)
    assertNull(sanitized.contexts.operatingSystem?.build)
    assertNull(sanitized.contexts.operatingSystem?.kernelVersion)
    assertNull(sanitized.contexts.operatingSystem?.isRooted)

    val device = sanitized.contexts.device!!
    assertEquals("Pixel Fold", device.model)
    assertEquals(2208, device.screenWidthPixels)
    assertEquals(1840, device.screenHeightPixels)
    assertEquals(12_884_901_888L, device.memorySize)
    assertNull(device.manufacturer)
    assertNull(device.brand)
    assertNull(device.storageSize)
    assertNull(device.batteryLevel)
    assertNull(device.name)
    assertNull(device.id)
    assertNull(device.timezone)
    assertNull(device.locale)
  }

  @Test
  public fun `clearSentryCache removes AndroidEnvelopeCache options cache and outbox dirs without touching unrelated cache files`() {
    val appCacheDir = Files.createTempDirectory("vitruvian-sentry-cache-test").toFile()
    try {
      val options = SentryAndroidOptions()
      configurePrivateSentry(
          options = options,
          dsn = "https://examplePublicKey@o0.ingest.sentry.io/0",
          keepDeviceFields = setOf(DeviceField.APP_VERSION),
          release = "vitruvian-remote@0.1.40",
          appCacheDir = appCacheDir,
      )

      val sentryBaseDir = sentryCacheDir(appCacheDir)
      val dsnCacheDir = File(options.cacheDirPath!!)
      val outboxDir = File(options.outboxPath!!)
      assertEquals(sentryBaseDir.absolutePath, dsnCacheDir.parentFile.absolutePath)
      assertTrue(dsnCacheDir.absolutePath.startsWith(sentryBaseDir.absolutePath + File.separator))
      assertEquals(File(dsnCacheDir, "outbox").absolutePath, outboxDir.absolutePath)

      dsnCacheDir.mkdirs()
      outboxDir.mkdirs()
      val envelope =
          SentryEnvelope.from(
              options.serializer, SentryEvent(RuntimeException("cached")), options.sdkVersion)
      val androidCache = AndroidEnvelopeCache(options)
      assertEquals(dsnCacheDir.absolutePath, androidCache.directory.absolutePath)
      EnvelopeCache.create(options).store(envelope, Hint())
      AndroidEnvelopeCache.markAnrReported(options, 123L)
      PersistingOptionsObserver(options).setRelease(options.release)
      val queuedOutbox = File(outboxDir, "queued.envelope").apply { writeText("envelope") }

      assertTrue(
          "Expected EnvelopeCache to write a .envelope file inside ${dsnCacheDir.absolutePath}",
          dsnCacheDir.listFiles().orEmpty().any { it.isFile && it.name.endsWith(".envelope") },
      )
      assertTrue(
          "Expected AndroidEnvelopeCache marker file inside ${dsnCacheDir.absolutePath}",
          File(dsnCacheDir, AndroidEnvelopeCache.LAST_ANR_REPORT).exists(),
      )
      assertTrue(
          "Expected PersistingOptionsObserver to populate .options-cache inside ${dsnCacheDir.absolutePath}",
          File(dsnCacheDir, PersistingOptionsObserver.OPTIONS_CACHE).exists(),
      )

      val unrelatedDir = File(appCacheDir, "http").apply { mkdirs() }
      val unrelatedFile = File(unrelatedDir, "keep.bin").apply { writeText("keep") }

      clearSentryCache(appCacheDir)

      assertFalse(sentryBaseDir.exists())
      assertFalse(dsnCacheDir.exists())
      assertFalse(outboxDir.exists())
      assertFalse(queuedOutbox.exists())
      assertTrue(unrelatedFile.exists())

      clearSentryCache(appCacheDir)
      assertTrue(unrelatedFile.exists())
    } finally {
      appCacheDir.deleteRecursively()
    }
  }

  @Test
  public fun `scrubCrashMessage replaces IPs URLs host-port pairs and hostnames without touching Java class names`() {
    assertEquals(
        "Failed to connect to <address>",
        scrubCrashMessage("Failed to connect to /10.0.2.2:7499"),
    )
    assertEquals(
        "<address>",
        scrubCrashMessage("http://192.168.1.20:7411/v1/state"),
    )
    assertEquals(
        "Unable to resolve host \"<address>\"",
        scrubCrashMessage("Unable to resolve host \"james-mbp.tail1234.ts.net\""),
    )
    assertEquals(
        "java.net.ConnectException: timeout",
        scrubCrashMessage("java.net.ConnectException: timeout"),
    )

    assertEquals(
        "Failed to connect to <address>",
        scrubCrashMessage("Failed to connect to [fd7a:115c:a1e0::1]:7411"),
    )
    assertEquals(
        "Socket unreachable on <address>",
        scrubCrashMessage("Socket unreachable on fe80::1%wlan0"),
    )
    assertEquals(
        "Peer <address> closed connection",
        scrubCrashMessage("Peer 2001:0db8:85a3:0000:0000:8a2e:0370:7334 closed connection"),
    )
    assertEquals(
        "java.net.ConnectException: Failed to connect to <address>",
        scrubCrashMessage(
            "java.net.ConnectException: Failed to connect to james-mbp.tail1234.ts.net/100.64.0.12:7411",
        ),
    )
    assertEquals(
        "Lookup failed for <address>, <address>, <address>, and <address>",
        scrubCrashMessage(
            "Lookup failed for studio.local, mini.lan, nas.home.arpa, and James-MBP.local",
        ),
    )
    assertEquals(
        "Dial <address> or <address> failed",
        scrubCrashMessage("Dial mac-studio:7411 or localhost:7499 failed"),
    )

    assertEquals(
        "java.io.IOException: unexpected EOF at Wire.kt:1009 (04:50:19, v0.1.41)",
        scrubCrashMessage(
            "java.io.IOException: unexpected EOF at Wire.kt:1009 (04:50:19, v0.1.41)",
        ),
    )
    assertEquals(
        "dev.vitruvian.remote.state.AgentAuthException: not paired (HTTP 401)",
        scrubCrashMessage(
            "dev.vitruvian.remote.state.AgentAuthException: not paired (HTTP 401)",
        ),
    )
  }

  @Test
  public fun `configurePrivateSentry beforeSend scrubs addresses from exceptions and event message`() {
    val options = SentryAndroidOptions()
    configurePrivateSentry(
        options = options,
        dsn = "https://examplePublicKey@o0.ingest.sentry.io/0",
        keepDeviceFields = setOf(DeviceField.APP_VERSION),
        release = "vitruvian-remote@0.1.41",
    )

    val cause = IllegalStateException("Unable to resolve host \"james-mbp.tail1234.ts.net\"")
    val root =
        RuntimeException(
            "Failed to connect to /10.0.2.2:7499 while fetching http://192.168.1.20:7411/v1/state",
            cause,
        )
    val rawEvent =
        SentryEvent(root).apply {
          message =
              Message().apply {
                message = "Request to %s failed via %s"
                formatted =
                    "Request to http://192.168.1.20:7411/v1/state failed via studio.local:7411"
                params = listOf("10.0.2.2:7499", "james-mbp.tail1234.ts.net")
              }
        }
    val hint = Hint()
    val processed = MainEventProcessor(options).process(rawEvent, hint)
    val sanitized = options.beforeSend!!.execute(processed, hint)!!

    val values = sanitized.exceptions!!.map { it.value.orEmpty() }
    assertTrue(values.any { it.contains("Unable to resolve host \"<address>\"") })
    assertTrue(
        values.any { it == "Failed to connect to <address> while fetching <address>" },
    )
    assertEquals(
        "Request to <address> failed via <address>",
        sanitized.message!!.formatted,
    )
    assertEquals("Request to %s failed via %s", sanitized.message!!.message)
    assertEquals(listOf("<address>", "<address>"), sanitized.message!!.params)

    val json = StringWriter().also { options.serializer.serialize(sanitized, it) }.toString()
    for (leaked in
        listOf(
            "10.0.2.2",
            "7499",
            "192.168.1.20",
            "7411",
            "james-mbp",
            "tail1234.ts.net",
            "studio.local",
        )) {
      assertFalse("Serialized event must not contain '$leaked': $json", json.contains(leaked))
    }

    val benignRaw = SentryEvent(RuntimeException("java.net.ConnectException: timeout"))
    val benignProcessed = MainEventProcessor(options).process(benignRaw, Hint())
    val benignSanitized = options.beforeSend!!.execute(benignProcessed, Hint())!!
    assertEquals(
        "java.net.ConnectException: timeout",
        benignSanitized.exceptions!!.single().value,
    )
  }

  @Test
  public fun `disableCrashReporting sets shutdownTimeoutMillis to zero before close and cache clear`() {
    val cacheDir = Files.createTempDirectory("vitruvian-sentry-disable-order").toFile()
    try {
      val sentryDir = sentryCacheDir(cacheDir)
      File(sentryDir, "outbox").apply { mkdirs() }
      File(sentryDir, "outbox/queued.envelope").writeText("queued")
      val steps = mutableListOf<String>()
      val recordingOptions =
          object : SentryOptions() {
            override fun setShutdownTimeoutMillis(shutdownTimeoutMillis: Long) {
              super.setShutdownTimeoutMillis(shutdownTimeoutMillis)
              steps += "setTimeout:$shutdownTimeoutMillis"
            }
          }
      assertEquals(2000L, recordingOptions.shutdownTimeoutMillis)

      disableCrashReporting(
          appCacheDir = cacheDir,
          options = recordingOptions,
          closeSentry = {
            assertEquals(0L, recordingOptions.shutdownTimeoutMillis)
            assertTrue(sentryDir.exists())
            steps += "close"
          },
          deleteCache = { dir ->
            steps += "deleteCache"
            clearSentryCache(dir)
          },
      )

      assertEquals(listOf("setTimeout:0", "close", "deleteCache"), steps)
      assertEquals(0L, recordingOptions.shutdownTimeoutMillis)
      assertFalse(sentryDir.exists())

      File(sentryDir, "outbox").apply { mkdirs() }
      File(sentryDir, "outbox/queued.envelope").writeText("queued")
      Sentry.init(
          OptionsContainer.create(SentryAndroidOptions::class.java),
          { opts ->
            configurePrivateSentry(
                options = opts,
                dsn = "https://public@127.0.0.1:1/0",
                keepDeviceFields = setOf(DeviceField.APP_VERSION),
                release = "vitruvian-remote@0.1.41",
                appCacheDir = cacheDir,
            )
          },
          true,
      )
      val liveOptions = Sentry.getCurrentScopes().options
      assertEquals(2000L, liveOptions.shutdownTimeoutMillis)

      disableCrashReporting(cacheDir)

      assertEquals(0L, liveOptions.shutdownTimeoutMillis)
      assertFalse(Sentry.isEnabled())
      assertFalse(sentryDir.exists())
    } finally {
      Sentry.close()
      cacheDir.deleteRecursively()
    }
  }

  @Test
  public fun `SentryAndroidOptions succeeds when Platform isAndroid is true while raw Sentry init throws`() {
    val cacheDir = Files.createTempDirectory("vitruvian-sentry-android-check").toFile()
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
      assertNotNull(
          "Expected plain Sentry.init to throw IllegalArgumentException on Android", thrown)
      assertTrue(thrown!!.message!!.contains("SentryAndroid.init"))

      Sentry.init(
          OptionsContainer.create(SentryAndroidOptions::class.java),
          { opts ->
            configurePrivateSentry(
                options = opts,
                dsn = "https://public@127.0.0.1:1/0",
                keepDeviceFields = setOf(DeviceField.APP_VERSION),
                release = "vitruvian-remote@0.1.44",
                appCacheDir = cacheDir,
            )
          },
          true,
      )
      assertTrue(Sentry.isEnabled())
      assertEquals(0, Sentry.getCurrentScopes().options.maxBreadcrumbs)
    } finally {
      Sentry.close()
      isAndroidField.setBoolean(null, originalIsAndroid)
      cacheDir.deleteRecursively()
    }
  }
}
