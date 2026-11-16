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

import android.content.Context
import dev.vitruvian.crashprivacy.DeviceField
import dev.vitruvian.crashprivacy.configurePrivateSentry
import io.sentry.android.core.SentryAndroid
import io.sentry.android.core.SentryAndroidOptions
import java.util.EnumSet

public object WatchSentry {
  public const val DEFAULT_DSN: String =
      "https://d273aa0e507187dad4c8cbad5567fcfc@sentry-ingest.ipv1337.dev/3"

  /** Match origin/main Java SDK behavior: release, environment, and DSN only. */
  public val KEPT_DEVICE_FIELDS: Set<DeviceField> = EnumSet.of(DeviceField.APP_VERSION)

  public fun init(
      context: Context,
      appName: String = "vitruvian-watch",
      dsn: String = System.getenv("SENTRY_DSN") ?: DEFAULT_DSN,
  ) {
    SentryAndroid.init(context) { options ->
      configureOptions(
          options = options,
          appName = appName,
          dsn = dsn,
      )
    }
  }

  public fun configureOptions(
      options: SentryAndroidOptions,
      appName: String = "vitruvian-watch",
      dsn: String = DEFAULT_DSN,
  ) {
    configurePrivateSentry(
        options = options,
        dsn = dsn,
        keepDeviceFields = KEPT_DEVICE_FIELDS,
        release = "$appName@1.0",
        environment = "production",
    )
  }
}
