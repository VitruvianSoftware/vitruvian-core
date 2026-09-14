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

import { WorkOS } from "@workos-inc/node";

import { getSecret } from "./secrets";

// Resolved lazily, NOT at module load. The previous top-level `throw` combined
// with Cloud Run `secretKeyRef` meant a revision could not even be created
// before the WorkOS creds existed, which blocks the first deploy into a fresh
// project. Importing this module is now inert; the credentials are fetched on
// first use and cached by lib/secrets.
let workosClient: WorkOS | undefined;

/** The WorkOS client. Throws only when actually used without credentials. */
export async function getWorkOS(): Promise<WorkOS> {
  if (!workosClient) {
    workosClient = new WorkOS(await getSecret("WORKOS_API_KEY"));
  }
  return workosClient;
}

/** The WorkOS client id. Throws only when actually used without credentials. */
export async function getWorkOSClientId(): Promise<string> {
  return getSecret("WORKOS_CLIENT_ID");
}

/** Test seam: drop the memoized client so a case can re-resolve credentials. */
export function __resetWorkOSForTests(): void {
  workosClient = undefined;
}
