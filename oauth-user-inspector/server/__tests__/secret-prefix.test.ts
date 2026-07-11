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

// Shared spy for SecretManagerServiceClient.accessSecretVersion. The server
// instantiates the client at module load, so the mock factory closes over a
// single jest.fn we assert against. Every access returns a distinct, uncached
// payload so a call always reaches the mock (the server's TTL cache is keyed on
// the *prefixed* id, so the two cases below can never share a cache entry).
const accessSecretVersion = jest.fn(async (_req: { name: string }) => [
  { payload: { data: Buffer.from("secret-value") } },
]);

jest.mock("@google-cloud/secret-manager", () => ({
  __esModule: true,
  SecretManagerServiceClient: jest.fn().mockImplementation(() => ({
    accessSecretVersion,
  })),
}));

// Mock logging-winston to prevent cloud logging attempts in tests (matches
// server.test.ts; also severs the google-auth-library import chain).
jest.mock("@google-cloud/logging-winston", () => ({
  LoggingWinston: jest.fn().mockImplementation(() => ({
    log: () => {},
    write: () => {},
  })),
}));

// Mock winston to provide a minimal logger implementation (matches
// server.test.ts).
jest.mock("winston", () => {
  const fakeLogger = {
    info: () => {},
    error: () => {},
    warn: () => {},
    child: () => fakeLogger,
  };
  return {
    __esModule: true,
    default: {
      createLogger: () => fakeLogger,
      format: {
        combine: () => {},
        timestamp: () => {},
        errors: () => {},
        json: () => {},
        colorize: () => {},
        printf: () => {},
      },
      transports: { Console: function () {} },
    },
    createLogger: () => fakeLogger,
    format: {
      combine: () => {},
      timestamp: () => {},
      errors: () => {},
      json: () => {},
      colorize: () => {},
      printf: () => {},
    },
    transports: { Console: function () {} },
  };
});

// Import after the mocks are registered (jest hoists jest.mock above imports).
import { getSecret } from "../server.js";

describe("getSecret SECRET_PREFIX", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    accessSecretVersion.mockClear();
    // Reset env per case so the previous case's SECRET_PREFIX can't leak in.
    process.env = { ...ORIGINAL_ENV };
    process.env.GOOGLE_CLOUD_PROJECT = "test-proj";
    delete process.env.GCP_PROJECT;
    delete process.env.SECRET_PREFIX;
  });

  afterAll(() => {
    process.env = ORIGINAL_ENV;
  });

  it("prefixes the secret id with SECRET_PREFIX when set", async () => {
    process.env.SECRET_PREFIX = "OAUTH_USER_INSPECTOR_";

    await getSecret("GITHUB_APP_OAUTH_CLIENT_ID");

    expect(accessSecretVersion).toHaveBeenCalledWith({
      name: "projects/test-proj/secrets/OAUTH_USER_INSPECTOR_GITHUB_APP_OAUTH_CLIENT_ID/versions/latest",
    });
  });

  it("uses the bare secret id when SECRET_PREFIX is unset (backward compatible)", async () => {
    await getSecret("GITHUB_APP_OAUTH_CLIENT_ID");

    expect(accessSecretVersion).toHaveBeenCalledWith({
      name: "projects/test-proj/secrets/GITHUB_APP_OAUTH_CLIENT_ID/versions/latest",
    });
  });
});
