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
 * SSRF hardening tests for resolveAndPin / safeFetch and the /api/explore
 * fail-closed contract.
 *
 * These tests are OFFLINE: dns.promises.lookup is mocked to return canned IPs so
 * we never touch the network. The point is to prove that resolveAndPin REJECTS
 * every internal/loopback/CGNAT/metadata address class (the SSRF reach this
 * host's Tailscale + Cloud Run posture exposes) and ACCEPTS only public unicast.
 */

import dns from "dns";

import { resolveAndPin, UpstreamError } from "../safeFetch.js";

type LookupAddress = { address: string; family: number };

// Helper: stub dns.promises.lookup to answer with the given address(es).
function mockLookup(addresses: LookupAddress[] | Error): void {
  const spy = jest.spyOn(dns.promises, "lookup") as unknown as jest.Mock;
  if (addresses instanceof Error) {
    spy.mockRejectedValue(addresses);
  } else {
    spy.mockResolvedValue(addresses as any);
  }
}

afterEach(() => {
  jest.restoreAllMocks();
});

describe("resolveAndPin SSRF rejection vectors", () => {
  // Each entry: a human label, the URL to resolve, and the canned IP(s) the
  // hostname "resolves" to. All MUST be rejected with UpstreamError.
  const REJECT_VECTORS: Array<{
    name: string;
    url: string;
    addrs: LookupAddress[];
  }> = [
    {
      name: "GCP/AWS metadata 169.254.169.254",
      url: "https://metadata.example.com/",
      addrs: [{ address: "169.254.169.254", family: 4 }],
    },
    {
      name: "localhost / 127.0.0.1 (loopback)",
      url: "https://localhost/",
      addrs: [{ address: "127.0.0.1", family: 4 }],
    },
    {
      name: "private 10.0.0.1",
      url: "https://internal.example.com/",
      addrs: [{ address: "10.0.0.1", family: 4 }],
    },
    {
      name: "private 192.168.1.1",
      url: "https://router.example.com/",
      addrs: [{ address: "192.168.1.1", family: 4 }],
    },
    {
      name: "CGNAT 100.64.0.1 (Tailscale)",
      url: "https://tailnet.example.com/",
      addrs: [{ address: "100.64.0.1", family: 4 }],
    },
    {
      // nip.io-style host that resolves to the metadata link-local IP.
      name: "169.254.169.254.nip.io (resolves private)",
      url: "https://169.254.169.254.nip.io/",
      addrs: [{ address: "169.254.169.254", family: 4 }],
    },
    {
      // sslip.io-style host that resolves to a link-local 169.254 address.
      name: "a9fe-a9fe.sslip.io (resolves private)",
      url: "https://a9fe-a9fe.sslip.io/",
      addrs: [{ address: "169.254.169.254", family: 4 }],
    },
    {
      name: "metadata.google.internal (resolves metadata IP)",
      url: "https://metadata.google.internal/",
      addrs: [{ address: "169.254.169.254", family: 4 }],
    },
    {
      name: "IPv4-mapped IPv6 ::ffff:169.254.169.254",
      url: "https://mapped.example.com/",
      addrs: [{ address: "::ffff:169.254.169.254", family: 6 }],
    },
    {
      name: "unspecified 0.0.0.0",
      url: "https://zero.example.com/",
      addrs: [{ address: "0.0.0.0", family: 4 }],
    },
    {
      name: "IPv6 loopback ::1",
      url: "https://v6loop.example.com/",
      addrs: [{ address: "::1", family: 6 }],
    },
    {
      name: "IPv6 unique-local fd00::1",
      url: "https://v6ula.example.com/",
      addrs: [{ address: "fd00::1", family: 6 }],
    },
    {
      name: "IPv6 link-local fe80::1",
      url: "https://v6ll.example.com/",
      addrs: [{ address: "fe80::1", family: 6 }],
    },
    {
      // A host that returns BOTH a public and a private record must fail
      // (split-horizon / DNS-rebinding defense: ALL records must be public).
      name: "mixed public + private records",
      url: "https://mixed.example.com/",
      addrs: [
        { address: "93.184.216.34", family: 4 },
        { address: "10.1.2.3", family: 4 },
      ],
    },
  ];

  for (const v of REJECT_VECTORS) {
    it(`rejects ${v.name}`, async () => {
      mockLookup(v.addrs);
      await expect(resolveAndPin(v.url)).rejects.toBeInstanceOf(UpstreamError);
    });
  }

  it("rejects a plain http:// URL before any DNS lookup", async () => {
    const spy = jest.spyOn(dns.promises, "lookup");
    await expect(resolveAndPin("http://example.com/")).rejects.toBeInstanceOf(
      UpstreamError,
    );
    expect(spy).not.toHaveBeenCalled();
  });

  it("rejects a host with no DNS records", async () => {
    mockLookup([]);
    await expect(
      resolveAndPin("https://empty.example.com/"),
    ).rejects.toBeInstanceOf(UpstreamError);
  });

  it("rejects an unparseable URL", async () => {
    await expect(resolveAndPin("not a url")).rejects.toBeInstanceOf(
      UpstreamError,
    );
  });
});

describe("resolveAndPin accepts public unicast", () => {
  it("accepts a host resolving to a public IPv4 (93.184.216.34)", async () => {
    mockLookup([{ address: "93.184.216.34", family: 4 }]);
    const pin = await resolveAndPin("https://example.com/userinfo?x=1");
    expect(pin.host).toBe("example.com");
    expect(pin.port).toBe(443);
    expect(pin.pinnedIp).toBe("93.184.216.34");
    expect(pin.family).toBe(4);
    expect(pin.pathSearch).toBe("/userinfo?x=1");
  });

  it("accepts a host resolving to a public IPv6 (2606:2800:220:1::)", async () => {
    mockLookup([{ address: "2606:2800:220:1:248:1893:25c8:1946", family: 6 }]);
    const pin = await resolveAndPin("https://v6.example.com/");
    expect(pin.family).toBe(6);
    expect(pin.host).toBe("v6.example.com");
  });

  it("honors a non-default https port", async () => {
    mockLookup([{ address: "93.184.216.34", family: 4 }]);
    const pin = await resolveAndPin("https://example.com:8443/path");
    expect(pin.port).toBe(8443);
  });
});

/**
 * /api/explore fail-closed: an unknown endpoint id must 400 and make NO
 * outbound call. We mock ../safeFetch so any outbound attempt is observable,
 * and the secret-manager / winston deps so the app imports cleanly offline.
 */
describe("/api/explore fail-closed (no outbound on unknown endpoint)", () => {
  const safeFetchSpy = jest.fn();

  beforeAll(() => {
    jest.resetModules();

    jest.doMock("../safeFetch", () => {
      const actual = jest.requireActual("../safeFetch");
      return {
        __esModule: true,
        UpstreamError: actual.UpstreamError,
        resolveAndPin: jest.fn(async () => ({
          host: "example.com",
          port: 443,
          pathSearch: "/",
          pinnedIp: "93.184.216.34",
          family: 4 as const,
        })),
        safeFetch: safeFetchSpy,
      };
    });

    jest.doMock("@google-cloud/secret-manager", () => ({
      SecretManagerServiceClient: jest.fn().mockImplementation(() => ({
        accessSecretVersion: jest
          .fn()
          .mockResolvedValue([{ payload: { data: "" } }]),
      })),
    }));

    jest.doMock("@google-cloud/logging-winston", () => ({
      LoggingWinston: jest
        .fn()
        .mockImplementation(() => ({ log: () => {}, write: () => {} })),
    }));

    jest.doMock("winston", () => {
      const fakeLogger = {
        info: () => {},
        error: () => {},
        warn: () => {},
        child: () => fakeLogger,
      };
      const format = {
        combine: () => {},
        timestamp: () => {},
        errors: () => {},
        json: () => {},
        colorize: () => {},
        printf: () => {},
      };
      return {
        __esModule: true,
        default: {
          createLogger: () => fakeLogger,
          format,
          transports: { Console: function () {} },
        },
        createLogger: () => fakeLogger,
        format,
        transports: { Console: function () {} },
      };
    });
  });

  afterAll(() => {
    jest.dontMock("../safeFetch");
    jest.dontMock("@google-cloud/secret-manager");
    jest.dontMock("@google-cloud/logging-winston");
    jest.dontMock("winston");
  });

  it("returns 400 'unknown endpoint' and never calls safeFetch", async () => {
    process.env.GOOGLE_CLOUD_PROJECT =
      process.env.GOOGLE_CLOUD_PROJECT || "test-project";

    // Require AFTER doMock so the mocks are wired into the freshly-loaded app.
    const request = require("supertest");
    const app = require("../server.js").default;

    const response = await request(app)
      .post("/api/explore")
      .send({
        provider: "github",
        accessToken: "test_token",
        endpoint: {
          id: "not-a-real-endpoint",
          method: "GET",
          url: "https://api.github.com/user",
        },
      });

    expect(response.status).toBe(400);
    expect(response.body).toHaveProperty("error", "unknown endpoint");
    expect(safeFetchSpy).not.toHaveBeenCalled();
  });
});
