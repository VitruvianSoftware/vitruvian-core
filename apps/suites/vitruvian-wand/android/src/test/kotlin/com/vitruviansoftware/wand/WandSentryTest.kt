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
  fun releaseNameIsTheVersionInVersionBzl() {
    val bzl = java.io.File("apps/suites/vitruvian-wand/version.bzl").readText()
    val written =
        Regex("""VITRUVIAN_WAND_VERSION = "([0-9]+\.[0-9]+\.[0-9]+)"""")
            .find(bzl)
            ?.groupValues
            ?.get(1)
    assertEquals(written, WandVersion.NAME)
    assertEquals("vitruvian-wand@$written", WandSentry.RELEASE)
  }

  @Test
  fun wandSentryStripsDeviceAndOsContextsAndMatchesOriginMainReleaseEnvDsn() {
    assertEquals(EnumSet.of(DeviceField.APP_VERSION), WandSentry.KEPT_DEVICE_FIELDS)

    val defaultOptions = SentryAndroidOptions()
    WandSentry.configureOptions(options = defaultOptions)
    assertEquals(WandSentry.DEFAULT_DSN, defaultOptions.dsn)
    assertEquals("vitruvian-wand@${WandVersion.NAME}", defaultOptions.release)
    assertEquals("production", defaultOptions.environment)

    val options =
        SentryAndroidOptions().apply {
          distinctId = "pre-existing-id"
          setTag("device.model", "Chromecast HD")
          setTag("os.version", "15")
        }
    WandSentry.configureOptions(
        options = options,
        dsn = "https://public@127.0.0.1:1/0",
        release = "vitruvian-wand@0.1.0",
    )

    assertEquals("https://public@127.0.0.1:1/0", options.dsn)
    assertEquals("vitruvian-wand@0.1.0", options.release)
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
          setTag("device.model", "Chromecast HD")
          setTag("os.version", "15")
          setTag("isSideLoaded", "true")
          setExtra("secret", "x")
          debugMeta = DebugMeta()
          serverName = "james-macbook-pro"
          threads = listOf(SentryThread().apply { name = "main" })
          setModule("io.sentry:sentry", "8.64.0")
          request = Request().apply { url = "http://10.0.2.2:7499/v1/state" }
          contexts.setApp(
              App().apply {
                appVersion = "0.1.0"
                permissions = mapOf("BLUETOOTH_SCAN" to "granted")
              })
          contexts.setDevice(
              Device().apply {
                model = "Chromecast HD"
                screenWidthPixels = 1920
                screenHeightPixels = 1080
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
    val processed = MainEventProcessor(options).process(event, hint)
    val sanitized = options.beforeSend!!.execute(processed, hint)!!

    assertEquals("vitruvian-wand@0.1.0", sanitized.release)
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
