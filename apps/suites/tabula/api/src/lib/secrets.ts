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

/**
 * Lazy, cached secret resolution.
 *
 * Tabula historically received its secrets as bare-named env vars injected by
 * Cloud Run `secretKeyRef`. That has two problems on the org foundation:
 *
 *  1. **Bare names collide.** Several apps co-tenanting one project would all
 *     want a secret called `DATABASE_URL`. `SECRET_PREFIX` (e.g. `TABULA_`)
 *     partitions the namespace, and the runtime SA's `secretAccessor` grant is
 *     conditioned on that same prefix so one app cannot read another's secrets.
 *
 *  2. **`secretKeyRef` makes the REVISION un-creatable when a secret is
 *     absent.** The Cloud Run control plane resolves those references at
 *     revision-create time, so the service cannot roll out before its creds
 *     land — the exact ordering a cold deploy into a fresh project needs.
 *     Reading lazily through the Secret Manager API decouples the two.
 *
 * Resolution order is **env first, Secret Manager second**: local development,
 * the test suite, and the pre-cutover deployment keep working with plain env
 * vars, while the new projects resolve from Secret Manager.
 */

import { SecretManagerServiceClient } from "@google-cloud/secret-manager";

const SECRET_CACHE_TTL_MS = 5 * 60 * 1000;

type CacheEntry = { value: string; expires: number };

// Keyed on the PREFIXED id so a prefix change is never served a stale value
// from the previous namespace.
const secretCache = new Map<string, CacheEntry>();

let client: SecretManagerServiceClient | undefined;

function getClient(): SecretManagerServiceClient {
  if (!client) {
    client = new SecretManagerServiceClient();
  }
  return client;
}

/** Test seam: drop cached values (and the memoized client) between cases. */
export function __resetSecretCacheForTests(): void {
  secretCache.clear();
  client = undefined;
}

/**
 * Resolve a secret by its logical (unprefixed) name.
 *
 * @throws if the secret is absent from both the environment and Secret Manager.
 */
export async function getSecret(secretName: string): Promise<string> {
  const fromEnv = process.env[secretName];
  if (fromEnv) {
    return fromEnv;
  }

  const prefix = process.env.SECRET_PREFIX ?? "";
  const fullName = `${prefix}${secretName}`;

  const cached = secretCache.get(fullName);
  if (cached && Date.now() < cached.expires) {
    return cached.value;
  }

  const projectId = process.env.GOOGLE_CLOUD_PROJECT || process.env.GCP_PROJECT;
  if (!projectId) {
    throw new Error(
      `Cannot resolve secret ${secretName}: neither the environment nor ` +
        `GOOGLE_CLOUD_PROJECT/GCP_PROJECT is set`,
    );
  }

  const name = `projects/${projectId}/secrets/${fullName}/versions/latest`;

  try {
    const [version] = await getClient().accessSecretVersion(
      { name },
      { timeout: 5000 },
    );
    const data = version?.payload?.data;
    if (!data) {
      throw new Error("secret version has no payload");
    }
    const value = data.toString();
    secretCache.set(fullName, {
      value,
      expires: Date.now() + SECRET_CACHE_TTL_MS,
    });
    return value;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Failed to resolve secret ${secretName}: ${message}`);
  }
}

/**
 * Resolve a secret, returning undefined instead of throwing when it is absent.
 * For genuinely optional configuration (e.g. Redis, which falls back to a local
 * instance) — never for credentials whose absence should fail loudly.
 */
export async function tryGetSecret(
  secretName: string,
): Promise<string | undefined> {
  try {
    return await getSecret(secretName);
  } catch {
    return undefined;
  }
}

/**
 * Secrets the API needs resolved before the synchronous consumers
 * (`lib/prisma`, `lib/redis`, `lib/auth`) read them off `process.env`.
 *
 * `optional: true` means a miss is logged and tolerated — Redis degrades to a
 * local fallback, so an absent value must not stop the service from booting and
 * serving `/health`. Required ones still fail loudly, but at BOOT rather than at
 * revision-create, which is what makes a cold deploy into a fresh project
 * possible at all.
 */
const BOOT_SECRETS: ReadonlyArray<{ name: string; optional?: boolean }> = [
  { name: "DATABASE_URL" },
  { name: "JWT_SECRET" },
  { name: "WORKOS_API_KEY", optional: true },
  { name: "WORKOS_CLIENT_ID", optional: true },
  { name: "UPSTASH_REDIS_URL", optional: true },
];

/**
 * Resolve the declared secrets into `process.env` once, at startup.
 *
 * Values already present in the environment are left untouched, so local
 * development and the pre-cutover deployment are unaffected. Returns the names
 * that could not be resolved, so the caller can log them.
 */
export async function bootstrapSecrets(): Promise<string[]> {
  const missing: string[] = [];

  for (const { name, optional } of BOOT_SECRETS) {
    if (process.env[name]) continue;
    try {
      process.env[name] = await getSecret(name);
    } catch (error) {
      if (!optional) throw error;
      missing.push(name);
    }
  }

  return missing;
}
