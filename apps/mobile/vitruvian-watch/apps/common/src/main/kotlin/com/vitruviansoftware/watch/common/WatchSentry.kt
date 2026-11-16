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

import io.sentry.OptionsContainer
import io.sentry.Sentry
import io.sentry.SentryOptions
import io.sentry.android.core.SentryAndroidOptions

public object WatchSentry {
  public const val DEFAULT_DSN: String =
      "https://d273aa0e507187dad4c8cbad5567fcfc@sentry-ingest.ipv1337.dev/3"

  private object PlainJavaOptionsContainer : OptionsContainer<SentryOptions>() {
    override fun createInstance(): SentryOptions = SentryAndroidOptions()
  }

  public fun init(
      appName: String = "vitruvian-watch",
      dsn: String = System.getenv("SENTRY_DSN") ?: DEFAULT_DSN,
  ) {
    Sentry.init(
        PlainJavaOptionsContainer,
        { options ->
          options.dsn = dsn
          options.release = "$appName@1.0"
          options.environment = "production"
        },
        /* globalHubMode = */ true,
    )
  }
}
