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

import type { Metadata } from "next";
// Geist comes from the npm package rather than next/font/google: the Google
// Fonts route downloads the font at build time, which breaks hermetic builds.
import { GeistSans } from "geist/font/sans";
import "./globals.css";
import { RUNTIME_CONFIG_ELEMENT_ID } from "@/lib/runtime-config";
import { escapeJsonForScript } from "@/lib/json-script";

const geistSans = GeistSans;

export const metadata: Metadata = {
  title: "Tabula Dashboard",
  description: "Web dashboard for Tabula workspace management",
};

// Forces this layout (and everything under it) to render per-request rather
// than be statically optimized at `next build` time. Required for the
// runtime-config script tag below to carry THIS container's own API_URL —
// without it, Next may prerender the HTML once at build and freeze whatever
// value was present then, reintroducing the exact bug this file exists to
// fix (see lib/runtime-config.ts).
export const dynamic = "force-dynamic";

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" data-theme="light" suppressHydrationWarning>
      <head>
        {/* Read by lib/runtime-config.ts. Populated fresh per request from
            the plain (non-NEXT_PUBLIC_) API_URL Cloud Run env var, so the
            SAME built image promoted unchanged across dev/nonprod/prod
            (tabula-deploy.yaml) still resolves each environment's own API
            host client-side. */}
        <script
          id={RUNTIME_CONFIG_ELEMENT_ID}
          type="application/json"
          dangerouslySetInnerHTML={{
            __html: escapeJsonForScript({ apiUrl: process.env.API_URL || null }),
          }}
        />
      </head>
      <body
        className={`${geistSans.variable} antialiased`}
        suppressHydrationWarning
      >
        {children}
      </body>
    </html>
  );
}
