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

// Backstage is internet-facing, so every scorecards route must demand a
// signed-in user or a service token. The plugin used to mark /entities and
// /evaluate as "unauthenticated", which let anyone on the internet call
// /evaluate with a made-up entity whose links point at internal URLs and have
// the server fetch them (server-side request forgery).
//
// These tests run the plugin's real setup and feed its auth policies into
// Backstage's real credentials barrier (the same middleware the production
// httpRouter installs in front of every plugin), then send requests through it.

import { createCredentialsBarrier } from "@backstage/backend-defaults/httpRouter";
import { scorecardsPlugin } from "./plugin";

type FakeRequest = {
  method?: string;
  path?: string;
  headers: Record<string, string | undefined>;
};

class AuthenticationError extends Error {
  name = "AuthenticationError";
}

// Stands in for Backstage's HttpAuthService: a request with a bearer token is
// a caller, one without is rejected, exactly as the real service does for a
// missing token.
const httpAuth = {
  credentials: async (req: FakeRequest) => {
    if (!req.headers.authorization) {
      throw new AuthenticationError("Missing credentials");
    }
    return { principal: { type: "user", userEntityRef: "user:default/test" } };
  },
};

const config = {
  has: () => false,
  getOptionalBoolean: () => undefined,
  getOptionalConfigArray: () => undefined,
};

async function startBarrier() {
  const barrier = createCredentialsBarrier({
    httpAuth: httpAuth as never,
    config: config as never,
  });

  // createBackendPlugin's feature exposes its registrations; run its init with
  // stub services, routing addAuthPolicy into the real barrier.
  const [registration] = (
    scorecardsPlugin as unknown as {
      getRegistrations(): Array<{
        init: { func: (deps: Record<string, unknown>) => Promise<void> };
      }>;
    }
  ).getRegistrations();

  await registration.init.func({
    http: {
      use: () => undefined,
      addAuthPolicy: barrier.addAuthPolicy,
    },
    logger: { info() {}, warn() {}, error() {}, debug() {}, child() {} },
    config,
    discovery: {
      getBaseUrl: async () => "http://localhost/api/catalog",
      getExternalBaseUrl: async () => "http://localhost/api/catalog",
    },
    auth: {},
  });

  return (req: Partial<FakeRequest>) =>
    new Promise<unknown>((resolve) => {
      barrier.middleware(
        { headers: {}, ...req } as never,
        {} as never,
        (err?: unknown) => resolve(err),
      );
    });
}

describe("scorecards plugin auth policy", () => {
  it.each([
    ["GET", "/entities/component/default/backstage"],
    ["POST", "/evaluate"],
  ])("rejects an unauthenticated %s %s", async (method, path) => {
    const send = await startBarrier();
    const err = await send({ method, path });
    expect(err).toBeInstanceOf(AuthenticationError);
  });

  it.each([
    ["GET", "/entities/component/default/backstage"],
    ["POST", "/evaluate"],
  ])("lets a signed-in caller through to %s %s", async (method, path) => {
    const send = await startBarrier();
    const err = await send({
      method,
      path,
      headers: { authorization: "Bearer user-token" },
    });
    expect(err).toBeUndefined();
  });
});
