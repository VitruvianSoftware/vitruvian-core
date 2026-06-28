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
 * safeFetch — the ONLY way this server makes user-influenced outbound calls.
 *
 * SSRF / open-relay hardening. This host's fleet lives on Tailscale CGNAT
 * (100.64.0.0/10), the k8s API is internal, and on Cloud Run the GCP metadata
 * server (169.254.169.254) hands out service-account tokens. A naive
 * `fetch(userControlledUrl)` would let a caller pivot into any of those. This
 * module closes that hole with two independent controls:
 *
 *   1. resolveAndPin() — resolve the hostname to *every* A/AAAA record and
 *      require ALL of them to be public unicast (net.BlockList classification).
 *      A single private/loopback/CGNAT/metadata address fails the whole host.
 *
 *   2. safeFetch() — connect to the *vetted IP literal* (no DNS at connect
 *      time, so a rebind between resolve and connect cannot re-point us), while
 *      passing `servername` so TLS still validates the cert against the real
 *      hostname. Redirects are never followed, and the body is size- and
 *      time-bounded.
 *
 * Node's `https` module is used deliberately instead of node-fetch: node-fetch
 * v2 re-resolves DNS at connect time and would defeat the IP pin (a classic
 * DNS-rebinding TOCTOU).
 */

import https from "https";
import dns from "dns";
import net from "net";
import { URL } from "url";

/**
 * Raised for every outbound failure that is influenced by a user-supplied host.
 *
 * Carries an internal `reason` for server-side logs (so operators can tell a
 * DNS rejection from a TLS failure) but exposes only a fixed, generic
 * `message` to clients — distinct reasons would otherwise be an SSRF recon
 * oracle (the attacker could map the internal network by failure type/timing).
 */
export class UpstreamError extends Error {
  /** Internal-only detail for server logs. Never returned to the client. */
  readonly reason: string;

  constructor(reason: string) {
    super("Upstream request failed");
    this.name = "UpstreamError";
    this.reason = reason;
    // Restore prototype chain (TS target ES2022 extends builtins fine, but be
    // explicit so `instanceof UpstreamError` holds across transpile targets).
    Object.setPrototypeOf(this, UpstreamError.prototype);
  }
}

/**
 * Non-globally-routable / special-purpose IP ranges we refuse to connect to,
 * built as a node `net.BlockList` (a builtin — no third-party dependency, so
 * this adds nothing to the lockfile). An address is allowed ONLY if it matches
 * none of these. Covers the SSRF-relevant set: loopback, RFC1918 private,
 * carrier-grade NAT (100.64/10 — Tailscale on this fleet), link-local incl. the
 * cloud metadata IP 169.254.169.254, IPv4-mapped IPv6, ULA, plus the IANA
 * special-purpose blocks.
 */
const DENY = new net.BlockList();
const DENY_V4: ReadonlyArray<[string, number]> = [
  ["0.0.0.0", 8], // "this host on this network"
  ["10.0.0.0", 8], // private
  ["100.64.0.0", 10], // carrier-grade NAT — Tailscale
  ["127.0.0.0", 8], // loopback
  ["169.254.0.0", 16], // link-local (incl. 169.254.169.254 metadata)
  ["172.16.0.0", 12], // private
  ["192.0.0.0", 24], // IETF protocol assignments
  ["192.0.2.0", 24], // TEST-NET-1 (documentation)
  ["192.88.99.0", 24], // 6to4 relay anycast (deprecated)
  ["192.168.0.0", 16], // private
  ["198.18.0.0", 15], // benchmarking
  ["198.51.100.0", 24], // TEST-NET-2
  ["203.0.113.0", 24], // TEST-NET-3
  ["224.0.0.0", 4], // multicast
  ["240.0.0.0", 4], // reserved (future use)
];
for (const [addr, prefix] of DENY_V4) DENY.addSubnet(addr, prefix, "ipv4");
DENY.addAddress("255.255.255.255", "ipv4"); // limited broadcast
// NB: do NOT add ::ffff:0:0/96 here — net.BlockList matches EVERY IPv4 against
// the mapped-v6 range, which would block all IPv4. IPv4-mapped IPv6 is instead
// unwrapped to its embedded IPv4 in vetAddress() and vetted as IPv4.
const DENY_V6: ReadonlyArray<[string, number]> = [
  ["64:ff9b::", 96], // NAT64
  ["100::", 64], // discard-only
  ["2001::", 32], // Teredo
  ["2001:db8::", 32], // documentation
  ["2002::", 16], // 6to4
  ["fc00::", 7], // unique-local (ULA)
  ["fe80::", 10], // link-local
  ["ff00::", 8], // multicast
];
for (const [addr, prefix] of DENY_V6) DENY.addSubnet(addr, prefix, "ipv6");
DENY.addAddress("::", "ipv6"); // unspecified
DENY.addAddress("::1", "ipv6"); // loopback

export interface ResolvedPin {
  /** Original hostname (used as TLS SNI/servername + Host header). */
  host: string;
  /** Numeric port (defaults to 443 for https). */
  port: number;
  /** Path + query string to request on the upstream. */
  pathSearch: string;
  /** The vetted public IP we will actually connect to (no further DNS). */
  pinnedIp: string;
  /** IP family of the pinned address (4 or 6). */
  family: 4 | 6;
}

/**
 * Vet a single resolved numeric IP. Returns the literal + family, or throws
 * UpstreamError if it is not a public address. `net.isIP` rejects non-numeric
 * input; the DENY BlockList rejects every special-purpose range. IPv4-mapped
 * IPv6 (::ffff:1.2.3.4) is unwrapped and its embedded IPv4 vetted explicitly, so
 * a private/metadata address tunneled through a v6 literal is always caught
 * regardless of how net.BlockList treats the mapped form.
 */
function vetAddress(rawIp: string): { ip: string; family: 4 | 6 } {
  const fam = net.isIP(rawIp);
  if (fam === 0) {
    throw new UpstreamError(`unparseable resolved address: ${rawIp}`);
  }

  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(rawIp);
  if (mapped && net.isIP(mapped[1]) === 4) {
    if (DENY.check(mapped[1], "ipv4")) {
      throw new UpstreamError(`non-public ipv4-mapped address (${rawIp})`);
    }
    return { ip: rawIp, family: 6 };
  }

  const type: "ipv4" | "ipv6" = fam === 4 ? "ipv4" : "ipv6";
  if (DENY.check(rawIp, type)) {
    throw new UpstreamError(`non-public ${type} address (${rawIp})`);
  }
  return { ip: rawIp, family: fam as 4 | 6 };
}

/**
 * Parse `rawUrl`, require https, resolve EVERY A/AAAA record, and require ALL
 * resolved addresses to be public unicast. Returns the connection pin (host,
 * port, path, first vetted IP). Throws UpstreamError on any rejection.
 */
export async function resolveAndPin(rawUrl: string): Promise<ResolvedPin> {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new UpstreamError(`unparseable URL: ${String(rawUrl)}`);
  }

  if (url.protocol !== "https:") {
    throw new UpstreamError(`non-https protocol: ${url.protocol}`);
  }

  const hostname = url.hostname;
  if (!hostname) {
    throw new UpstreamError("missing hostname");
  }

  // Resolve the hostname to all of its A/AAAA records. dns.lookup honours the
  // OS resolver/hosts file, which is what we want — the connect step will use
  // the *same* answer (pinned IP), so there is no second lookup to diverge.
  let addresses: dns.LookupAddress[];
  try {
    addresses = await dns.promises.lookup(hostname, { all: true });
  } catch (err) {
    throw new UpstreamError(
      `DNS lookup failed for ${hostname}: ${(err as Error).message}`,
    );
  }

  if (!addresses || addresses.length === 0) {
    throw new UpstreamError(`no DNS records for ${hostname}`);
  }

  // EVERY resolved address must vet clean — a single bad one fails the host
  // (a hostname that returns one public and one private A record is a classic
  // DNS-rebinding / split-horizon SSRF vector).
  const vetted = addresses.map((a) => vetAddress(a.address));

  const pinned = vetted[0];
  const port = url.port ? parseInt(url.port, 10) : 443;
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new UpstreamError(`invalid port: ${url.port}`);
  }

  return {
    host: hostname,
    port,
    pathSearch: `${url.pathname}${url.search}`,
    pinnedIp: pinned.ip,
    family: pinned.family,
  };
}

export interface SafeFetchOptions {
  method?: string;
  headers?: Record<string, string>;
  body?: string;
  timeoutMs?: number;
  maxBytes?: number;
}

export interface SafeFetchResult {
  status: number;
  headers: Record<string, string | string[] | undefined>;
  body: string;
}

/**
 * Default User-Agent for ALL server-side egress.
 *
 * GitHub's REST API (`api.github.com`) REJECTS requests that carry no
 * User-Agent with HTTP 403 ("Request forbidden by administrative rules ... make
 * sure your request has a User-Agent header"). Because safeFetch sent none,
 * the server-side token **revoke** (`DELETE /applications/{id}/token`) and the
 * GitHub API Explorer silently failed with a 403 — while login still worked,
 * since the token exchange hits the more lenient `github.com` host and the
 * profile fetch happens browser-side (the browser supplies a UA). safeFetch is
 * the single outbound chokepoint, so we default a UA here for every request.
 */
export const SAFE_FETCH_USER_AGENT = "oauth-user-inspector";

/**
 * Return `headers` with a default `User-Agent` added iff the caller did not
 * already set one (case-insensitive). Pure + exported so the behavior is
 * unit-testable without a live socket.
 */
export function withDefaultUserAgent(
  headers: Record<string, string>,
): Record<string, string> {
  const hasUserAgent = Object.keys(headers).some(
    (k) => k.toLowerCase() === "user-agent",
  );
  return hasUserAgent
    ? headers
    : { ...headers, "User-Agent": SAFE_FETCH_USER_AGENT };
}

/**
 * Make a single user-influenced outbound HTTPS request, safely.
 *
 * - Resolves + pins the host (resolveAndPin) so we only ever connect to a
 *   vetted public IP literal — no DNS at connect time (defeats rebinding).
 * - Validates TLS against the REAL hostname via `servername` + the Host header.
 * - Never follows redirects: a 3xx is returned verbatim so the server never
 *   makes a second, unvetted connection to the Location.
 * - Enforces a byte cap and a timeout.
 */
export async function safeFetch(
  rawUrl: string,
  options: SafeFetchOptions = {},
): Promise<SafeFetchResult> {
  const {
    method = "GET",
    headers = {},
    body,
    timeoutMs = 5000,
    maxBytes = 2_000_000,
  } = options;

  const pin = await resolveAndPin(rawUrl);

  return new Promise<SafeFetchResult>((resolve, reject) => {
    // Connect to the vetted IP literal. `servername` drives SNI + cert
    // validation against the real host; the explicit Host header keeps HTTP
    // routing correct on the upstream. rejectUnauthorized stays true.
    const requestOptions: https.RequestOptions = {
      host: pin.pinnedIp,
      servername: pin.host,
      port: pin.port,
      path: pin.pathSearch,
      method,
      headers: withDefaultUserAgent({ ...headers, host: pin.host }),
      timeout: timeoutMs,
      rejectUnauthorized: true,
      // Pin the connect-time address family to the one we vetted.
      family: pin.family,
    };

    const req = https.request(requestOptions, (res) => {
      const chunks: Buffer[] = [];
      let received = 0;
      let aborted = false;

      res.on("data", (chunk: Buffer) => {
        if (aborted) {
          return;
        }
        received += chunk.length;
        if (received > maxBytes) {
          aborted = true;
          req.destroy();
          reject(
            new UpstreamError(
              `response exceeded maxBytes (${maxBytes}) for ${pin.host}`,
            ),
          );
          return;
        }
        chunks.push(chunk);
      });

      res.on("end", () => {
        if (aborted) {
          return;
        }
        resolve({
          status: res.statusCode ?? 0,
          headers: res.headers,
          body: Buffer.concat(chunks).toString("utf8"),
        });
      });

      res.on("error", (err) => {
        if (aborted) {
          return;
        }
        aborted = true;
        reject(new UpstreamError(`response stream error: ${err.message}`));
      });
    });

    req.on("timeout", () => {
      req.destroy();
      reject(new UpstreamError(`timeout after ${timeoutMs}ms for ${pin.host}`));
    });

    req.on("error", (err) => {
      // Surface a generic UpstreamError; the underlying message is internal-only.
      reject(
        new UpstreamError(`request error for ${pin.host}: ${err.message}`),
      );
    });

    if (body !== undefined) {
      req.write(body);
    }
    req.end();
  });
}
