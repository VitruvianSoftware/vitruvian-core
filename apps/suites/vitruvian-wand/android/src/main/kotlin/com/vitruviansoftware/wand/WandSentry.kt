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

import android.content.Context
import android.os.Build
import io.sentry.SentryOpenTelemetryMode
import io.sentry.SentryOptions
import io.sentry.android.core.SentryAndroid
import io.sentry.android.core.SentryAndroidOptions
import io.sentry.protocol.Device
import io.sentry.protocol.OperatingSystem

object WandSentry {
  const val DEFAULT_DSN: String =
      "https://9cf2abc1bfe2c6145e8b5334b2c9ff4c@sentry-ingest.ipv1337.dev/9"

  fun init(
      context: Context,
      dsn: String = System.getenv("SENTRY_DSN") ?: DEFAULT_DSN,
      release: String = "vitruvian-wand@0.1.0",
  ) {
    SentryAndroid.init(context) { options ->
      configureOptions(
          options = options,
          dsn = dsn,
          release = release,
          osVersion = Build.VERSION.RELEASE,
          deviceModel = Build.MODEL,
      )
    }
  }

  fun configureOptions(
      options: SentryAndroidOptions,
      dsn: String = DEFAULT_DSN,
      release: String = "vitruvian-wand@0.1.0",
      osVersion: String? = null,
      deviceModel: String? = null,
  ) {
    options.dsn = dsn
    options.release = release
    options.environment = "production"
    options.isSendDefaultPii = false
    options.distinctId = null
    options.maxBreadcrumbs = 0
    options.maxFeatureFlags = 0
    options.isAttachServerName = false
    options.serverName = null
    options.isAttachThreads = false
    options.isSendModules = false
    options.isEnableAutoSessionTracking = false
    options.isSendClientReports = false

    options.enableAllAutoBreadcrumbs(false)
    options.isEnableSystemEventBreadcrumbsExtras = false
    options.beforeBreadcrumb = SentryOptions.BeforeBreadcrumbCallback { _, _ -> null }

    options.isAnrEnabled = false
    options.isAnrReportInDebug = false
    options.isReportHistoricalAnrs = false
    options.isAttachAnrThreadDump = false
    options.anrProfilingSampleRate = null
    options.isEnableNdkAppHangTracking = false
    options.isTombstoneEnabled = false
    options.isReportHistoricalTombstones = false
    options.isAttachRawTombstone = false
    options.isMemoryLimiterEnabled = false
    options.isReportHistoricalMemoryLimiterExits = false
    options.isEnableNdk = false
    options.isEnableScopeSync = false

    options.isAttachScreenshot = false
    options.isAttachViewHierarchy = false
    options.isEnableFramesTracking = false
    options.isCollectAdditionalContext = false
    options.isCollectExternalStorageContext = false
    options.isEnableRootCheck = false
    options.feedbackOptions.isUseShakeGesture = false
    options.feedbackOptions.isEnableAttachScreenshot = false

    options.tracesSampleRate = null
    options.tracesSampler = null
    options.isEnableAutoActivityLifecycleTracing = false
    options.isEnableActivityLifecycleTracingAutoFinish = false
    options.isEnableUserInteractionTracing = false
    options.isEnableTimeToFullDisplayTracing = false
    options.isEnablePerformanceV2 = false
    options.isEnableStandaloneAppStartTracing = false
    options.isEnableAutoTraceIdGeneration = false
    options.isEnableScreenTracking = false
    options.setTracePropagationTargets(emptyList())
    options.webViewTracing.allowedHosts = emptyList()
    options.beforeSendTransaction = SentryOptions.BeforeSendTransactionCallback { _, _ -> null }
    options.profilesSampleRate = null
    options.profilesSampler = null
    options.profileSessionSampleRate = null
    options.isStartProfilerOnAppStart = false
    options.isEnableAppStartProfiling = false

    options.sessionReplay.sessionSampleRate = null
    options.sessionReplay.onErrorSampleRate = null
    options.sessionReplay.isTrackConfiguration = false
    options.beforeSendReplay = SentryOptions.BeforeSendReplayCallback { _, _ -> null }

    options.logs.isEnabled = false
    options.logs.beforeSend = SentryOptions.Logs.BeforeSendLogCallback { _ -> null }
    options.metrics.isEnabled = false
    options.metrics.beforeSend = SentryOptions.Metrics.BeforeSendMetricCallback { _, _ -> null }

    options.isEnableBackpressureHandling = false
    options.openTelemetryMode = SentryOpenTelemetryMode.OFF
    options.isCaptureOpenTelemetryEvents = false
    options.isEnableScopePersistence = false
    options.isEnableSpotlight = false

    val cleanModel = deviceModel?.trim()?.takeIf { it.isNotEmpty() }
    val cleanOs = osVersion?.trim()?.takeIf { it.isNotEmpty() }
    val boundedTags = buildMap {
      cleanModel?.let { put("device.model", it) }
      cleanOs?.let { put("os.version", it) }
    }
    boundedTags.forEach { (key, value) -> options.setTag(key, value) }

    options.beforeSend =
        SentryOptions.BeforeSendCallback { event, hint ->
          hint.clearAttachments()
          event.breadcrumbs = null
          event.user = null
          event.request = null
          event.serverName = null
          event.dist = null
          event.extras = null
          event.debugMeta = null
          event.tags = if (boundedTags.isEmpty()) null else HashMap(boundedTags)
          if (event.threads != null) {
            event.threads = null
          }
          event.contexts.clear()
          if (cleanOs != null) {
            event.contexts.setOperatingSystem(
                OperatingSystem().apply {
                  name = "Android"
                  version = cleanOs
                })
          }
          if (cleanModel != null) {
            event.contexts.setDevice(Device().apply { model = cleanModel })
          }
          event
        }
  }
}
