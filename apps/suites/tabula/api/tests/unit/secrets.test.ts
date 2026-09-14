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

// Secret resolution for the foundation migration. Tabula historically read bare
// env names injected by Cloud Run `secretKeyRef`, which (a) collides with
// co-tenant apps in a shared project and (b) makes the REVISION itself
// un-creatable when a secret is absent — so the service cannot roll out before
// its creds land, which is exactly the ordering a cold deploy needs.
//
// The replacement resolves env-first (local dev, tests, and the transition
// period keep working unchanged) and otherwise reads
// `${SECRET_PREFIX}${name}` from Secret Manager, lazily and cached.

const accessSecretVersion = jest.fn();

jest.mock("@google-cloud/secret-manager", () => ({
  SecretManagerServiceClient: jest.fn().mockImplementation(() => ({
    accessSecretVersion,
  })),
}));

import { getSecret, __resetSecretCacheForTests } from "../../src/lib/secrets";

const ORIGINAL_ENV = process.env;

beforeEach(() => {
  jest.clearAllMocks();
  __resetSecretCacheForTests();
  process.env = { ...ORIGINAL_ENV };
  // tests/setup.ts seeds these for the rest of the suite; clear them here so
  // the Secret Manager path is exercised rather than short-circuited by
  // env-first resolution (which is itself asserted by the first case).
  delete process.env.SECRET_PREFIX;
  delete process.env.DATABASE_URL;
  delete process.env.JWT_SECRET;
  delete process.env.MISSING_ONE;
  process.env.GOOGLE_CLOUD_PROJECT = "prj-d-bu2-oss-floating-test";
});

afterAll(() => {
  process.env = ORIGINAL_ENV;
});

function mockSecretPayload(value: string) {
  accessSecretVersion.mockResolvedValue([
    { payload: { data: Buffer.from(value) } },
  ]);
}

describe("getSecret", () => {
  it("prefers an env var when set, without calling Secret Manager", async () => {
    process.env.DATABASE_URL = "postgres://from-env/db";

    await expect(getSecret("DATABASE_URL")).resolves.toBe(
      "postgres://from-env/db",
    );
    expect(accessSecretVersion).not.toHaveBeenCalled();
  });

  it("falls back to Secret Manager, applying SECRET_PREFIX", async () => {
    process.env.SECRET_PREFIX = "TABULA_";
    mockSecretPayload("postgres://from-sm/db");

    await expect(getSecret("DATABASE_URL")).resolves.toBe(
      "postgres://from-sm/db",
    );
    expect(accessSecretVersion).toHaveBeenCalledWith(
      {
        name: "projects/prj-d-bu2-oss-floating-test/secrets/TABULA_DATABASE_URL/versions/latest",
      },
      { timeout: 5000 },
    );
  });

  it("reads the bare name when no prefix is configured", async () => {
    mockSecretPayload("v");

    await getSecret("JWT_SECRET");

    expect(accessSecretVersion).toHaveBeenCalledWith(
      {
        name: "projects/prj-d-bu2-oss-floating-test/secrets/JWT_SECRET/versions/latest",
      },
      { timeout: 5000 },
    );
  });

  it("caches by prefixed id, so repeat reads hit Secret Manager once", async () => {
    process.env.SECRET_PREFIX = "TABULA_";
    mockSecretPayload("cached");

    await getSecret("JWT_SECRET");
    await getSecret("JWT_SECRET");

    expect(accessSecretVersion).toHaveBeenCalledTimes(1);
  });

  it("does not cache across different prefixes", async () => {
    mockSecretPayload("a");
    await getSecret("JWT_SECRET");

    process.env.SECRET_PREFIX = "TABULA_";
    mockSecretPayload("b");
    await expect(getSecret("JWT_SECRET")).resolves.toBe("b");

    expect(accessSecretVersion).toHaveBeenCalledTimes(2);
  });

  it("throws a named error when the secret is absent", async () => {
    accessSecretVersion.mockRejectedValue(new Error("NOT_FOUND"));

    await expect(getSecret("MISSING_ONE")).rejects.toThrow(/MISSING_ONE/);
  });

  it("throws when no project id is configured and no env var is present", async () => {
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.GCP_PROJECT;

    await expect(getSecret("JWT_SECRET")).rejects.toThrow(
      /GOOGLE_CLOUD_PROJECT/,
    );
  });
});

describe("module import safety (the cold-deploy blocker)", () => {
  it("importing the WorkOS module does not throw when creds are absent", () => {
    delete process.env.WORKOS_API_KEY;
    delete process.env.WORKOS_CLIENT_ID;

    // Previously `lib/workos.ts` threw at module load, which made the Cloud Run
    // revision un-creatable before secrets existed. Evaluating the module body
    // must now be inert — the credentials are resolved on first use instead.
    // requireActual bypasses the module registry so the body really runs.
    expect(() => {
      const mod = jest.requireActual("../../src/lib/workos");
      expect(mod.getWorkOS).toBeInstanceOf(Function);
    }).not.toThrow();
  });
});
