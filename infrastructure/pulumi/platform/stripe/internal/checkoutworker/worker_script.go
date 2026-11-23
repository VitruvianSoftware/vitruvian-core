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

package checkoutworker

// WorkerScript holds the Cloudflare Worker ES Module source. Kept as a Go raw
// string constant instead of //go:embed so Bazel's symlinked runfiles tree
// never fails with "cannot embed irregular file".
const WorkerScript = `// Copyright (c) 2026 VitruvianSoftware
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

const EXPECTED_ACTION = "donate";
const MAX_BODY_BYTES = 8192;
const TURNSTILE_VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify";
const STRIPE_SESSIONS_URL = "https://api.stripe.com/v1/checkout/sessions";

function corsHeaders(allowedOrigin) {
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function jsonResponse(status, body, extraHeaders) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...(extraHeaders || {}),
    },
  });
}

function sanitizeSource(raw, app) {
  const cleaned = String(raw || "")
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 200);
  if (cleaned) {
    return cleaned;
  }
  return ("direct-" + String(app || "")).toLowerCase().slice(0, 200);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return jsonResponse(200, { ok: true });
    }

    if (url.pathname !== "/checkout") {
      return jsonResponse(404, { error: "not found" });
    }

    const allowedOrigin = String(env.ALLOWED_ORIGIN || "");
    const origin = request.headers.get("Origin");
    if (!allowedOrigin || origin !== allowedOrigin) {
      return jsonResponse(403, { error: "forbidden origin" });
    }

    const cors = corsHeaders(allowedOrigin);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    if (request.method !== "POST") {
      return jsonResponse(405, { error: "method not allowed" }, cors);
    }

    let bodyText;
    try {
      bodyText = await request.text();
    } catch (err) {
      return jsonResponse(400, { error: "invalid body" }, cors);
    }
    if (bodyText.length > MAX_BODY_BYTES) {
      return jsonResponse(413, { error: "payload too large" }, cors);
    }

    let payload;
    try {
      payload = JSON.parse(bodyText);
    } catch (err) {
      return jsonResponse(400, { error: "invalid json" }, cors);
    }
    if (!payload || typeof payload !== "object") {
      return jsonResponse(400, { error: "invalid payload" }, cors);
    }

    let allowedApps;
    try {
      allowedApps = new Set(JSON.parse(env.ALLOWED_APPS_JSON || "[]"));
    } catch (err) {
      return jsonResponse(500, { error: "misconfigured apps" }, cors);
    }

    const app = payload.app;
    if (typeof app !== "string" || !allowedApps.has(app)) {
      return jsonResponse(400, { error: "unknown app" }, cors);
    }

    const token = payload.token;
    if (typeof token !== "string" || token.length === 0 || token.length > 2048) {
      return jsonResponse(403, { error: "forbidden" }, cors);
    }

    const expectedHostnames = new Set(
      String(env.TURNSTILE_HOSTNAMES || "")
        .split(",")
        .map((h) => h.trim())
        .filter(Boolean)
    );
    if (expectedHostnames.size === 0 || !env.TURNSTILE_SECRET) {
      return jsonResponse(403, { error: "forbidden" }, cors);
    }

    const verifyParams = new URLSearchParams({
      secret: env.TURNSTILE_SECRET,
      response: token,
    });
    const cfIp = request.headers.get("CF-Connecting-IP");
    if (cfIp) {
      verifyParams.set("remoteip", cfIp);
    }

    let verifyResult;
    try {
      const verifyResp = await fetch(TURNSTILE_VERIFY_URL, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        signal: AbortSignal.timeout(10_000),
        body: verifyParams,
      });
      if (!verifyResp.ok) {
        return jsonResponse(403, { error: "forbidden" }, cors);
      }
      verifyResult = await verifyResp.json();
    } catch (err) {
      return jsonResponse(403, { error: "forbidden" }, cors);
    }

    if (
      !verifyResult ||
      !verifyResult.success ||
      verifyResult.action !== EXPECTED_ACTION ||
      !expectedHostnames.has(verifyResult.hostname)
    ) {
      return jsonResponse(403, { error: "forbidden" }, cors);
    }

    if (!env.STRIPE_API_KEY || !env.DONATIONS_PRICE_ID || !env.SITE_BASE_URL) {
      return jsonResponse(500, { error: "misconfigured checkout" }, cors);
    }

    const cleanSource = sanitizeSource(payload.source, app);
    const siteBase = String(env.SITE_BASE_URL).replace(/\/+$/, "");
    const successUrl = siteBase + "/donate/thanks/?app=" + encodeURIComponent(app);
    const cancelUrl =
      app === "development"
        ? siteBase + "/donate/"
        : siteBase + "/donate/" + encodeURIComponent(app) + "/";

    const stripeParams = new URLSearchParams({
      mode: "payment",
      submit_type: "donate",
      "line_items[0][price]": env.DONATIONS_PRICE_ID,
      "line_items[0][quantity]": "1",
      client_reference_id: cleanSource,
      "metadata[app]": app,
      "metadata[product-line]": "donations",
      "metadata[source]": cleanSource,
      "payment_intent_data[metadata][app]": app,
      "payment_intent_data[metadata][product-line]": "donations",
      "payment_intent_data[metadata][source]": cleanSource,
      "custom_text[submit][message]": String(env.SUBMIT_MESSAGE || ""),
      success_url: successUrl,
      cancel_url: cancelUrl,
    });

    let session;
    try {
      const stripeResp = await fetch(STRIPE_SESSIONS_URL, {
        method: "POST",
        headers: {
          Authorization: "Bearer " + env.STRIPE_API_KEY,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        signal: AbortSignal.timeout(15_000),
        body: stripeParams,
      });
      if (!stripeResp.ok) {
        return jsonResponse(502, { error: "checkout creation failed" }, cors);
      }
      session = await stripeResp.json();
    } catch (err) {
      return jsonResponse(502, { error: "checkout creation failed" }, cors);
    }

    if (!session || typeof session.url !== "string" || !session.url.startsWith("https://checkout.stripe.com/")) {
      return jsonResponse(502, { error: "invalid checkout url" }, cors);
    }

    return jsonResponse(200, { url: session.url }, cors);
  },
};
`
