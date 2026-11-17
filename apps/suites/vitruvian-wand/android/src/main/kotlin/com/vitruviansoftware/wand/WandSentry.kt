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
import dev.vitruvian.crashprivacy.DeviceField
import dev.vitruvian.crashprivacy.configurePrivateSentry
import io.sentry.android.core.SentryAndroid
import io.sentry.android.core.SentryAndroidOptions
import java.util.EnumSet

object WandSentry {
  /** The release name crash reports carry, e.g. `vitruvian-wand@0.1.0`. */
  const val RELEASE: String = "vitruvian-wand@${WandVersion.NAME}"

  const val DEFAULT_DSN: String =
      "https://9cf2abc1bfe2c6145e8b5334b2c9ff4c@sentry-ingest.ipv1337.dev/9"

  /** Match origin/main Java SDK behavior: release, environment, and DSN only. */
  val KEPT_DEVICE_FIELDS: Set<DeviceField> = EnumSet.of(DeviceField.APP_VERSION)

  fun init(
      context: Context,
      dsn: String = System.getenv("SENTRY_DSN") ?: DEFAULT_DSN,
      release: String = RELEASE,
  ) {
    SentryAndroid.init(context) { options ->
      configureOptions(
          options = options,
          dsn = dsn,
          release = release,
      )
    }
  }

  fun configureOptions(
      options: SentryAndroidOptions,
      dsn: String = DEFAULT_DSN,
      release: String = RELEASE,
  ) {
    configurePrivateSentry(
        options = options,
        dsn = dsn,
        keepDeviceFields = KEPT_DEVICE_FIELDS,
        release = release,
        environment = "production",
    )
  }
}
