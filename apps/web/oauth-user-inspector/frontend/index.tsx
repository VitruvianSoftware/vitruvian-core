/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import React from "react";
import ReactDOM from "react-dom/client";
import * as Sentry from "@sentry/react";
import App from "./App";

const sentryDsn =
  import.meta.env.VITE_SENTRY_DSN ||
  (import.meta.env.PROD
    ? "https://b5f2531a96fc15a51fd199825daf0be4@sentry-ingest.ipv1337.dev/7"
    : undefined);

if (sentryDsn) {
  Sentry.init({
    dsn: sentryDsn,
    environment:
      import.meta.env.MODE ||
      (import.meta.env.PROD ? "production" : "development"),
    tracesSampleRate: 0.0,
  });
}

const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Could not find root element to mount to");
}

const root = ReactDOM.createRoot(rootElement);
root.render(
  <React.StrictMode>
    <Sentry.ErrorBoundary
      fallback={
        <div className="p-4 text-red-500">An unexpected error occurred.</div>
      }
    >
      <App />
    </Sentry.ErrorBoundary>
  </React.StrictMode>,
);
