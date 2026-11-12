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

import type { NextConfig } from "next";

// Security headers (CSP included) are NOT set here. `headers()` is evaluated
// by `next build` and frozen into routes-manifest.json, which made the old
// CSP's connect-src a build-time constant — exactly the class of bug that
// broke prod login (a single built image, promoted unchanged across
// dev/nonprod/prod, can only ever bake in ONE environment's API host). They
// now live in proxy.ts (lib/security-headers.ts), which runs as real
// per-request server code and reads the per-environment API_URL Cloud Run env
// var fresh on every request. See lib/runtime-config.ts for the full story.
const nextConfig: NextConfig = {
  output: "standalone",
  // geist ships ESM-only; transpile it for both next build and next/jest
  // (next/jest derives its jest transformIgnorePatterns from this list).
  transpilePackages: ["geist"],
};

export default nextConfig;
