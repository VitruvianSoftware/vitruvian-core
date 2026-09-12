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

import { Request, Response, NextFunction } from "express";

/**
 * Hand-written, dependency-free fixed-window rate limiter.
 *
 * Why hand-rolled (no express-rate-limit): the P1 hardening must not touch the
 * lockfile / add npm deps. This is a deliberately small in-memory limiter — a
 * Map keyed by `${bucket}:${clientIp}` holding a fixed-window count + reset
 * timestamp. It is per-instance (Cloud Run may run >1 instance), so it is a
 * coarse abuse/DoS dampener, NOT a precise global quota. A periodic sweep
 * evicts expired entries so the Map can't grow unbounded under IP churn.
 */

export interface RateLimitTier {
  /** Logical bucket name; keeps independent tiers from sharing counters. */
  bucket: string;
  /** Max requests per window, per client IP. */
  limit: number;
  /** Window length in milliseconds. */
  windowMs: number;
}

interface Counter {
  count: number;
  /** Epoch ms at which this window resets. */
  resetAt: number;
}

/**
 * Read the real client IP. Behind Cloudflare Tunnel + Cloud Run the socket peer
 * is an internal proxy, so we trust `CF-Connecting-IP` (set by Cloudflare on
 * every proxied request) and fall back to Express's `req.ip` (which honors
 * `trust proxy`). NOTE: CF-Connecting-IP is only *authoritative* once Cloud Run
 * ingress is locked to the tunnel (a separate infra change); until then a direct
 * caller could spoof it, so this header is advisory and the limiter is
 * best-effort defense-in-depth.
 */
export function clientIp(req: Request): string {
  const cf = req.headers["cf-connecting-ip"];
  if (typeof cf === "string" && cf.length > 0) {
    return cf;
  }
  if (Array.isArray(cf) && cf.length > 0) {
    return cf[0];
  }
  return req.ip || req.socket?.remoteAddress || "unknown";
}

/**
 * A single fixed-window limiter for one tier. Holds its own Map + sweep timer.
 * The sweep timer is `unref()`'d so it never keeps the process alive (important
 * for clean Jest exits and graceful shutdown).
 */
export class RateLimiter {
  private readonly buckets = new Map<string, Counter>();
  private readonly sweepTimer: NodeJS.Timeout | undefined;

  constructor(
    private readonly tier: RateLimitTier,
    /** How often to evict expired entries; defaults to the window length. */
    sweepIntervalMs: number = tier.windowMs,
    /** Test seam: skip the background sweep timer entirely. */
    enableSweep = true,
  ) {
    if (enableSweep) {
      this.sweepTimer = setInterval(() => this.sweep(), sweepIntervalMs);
      // Do not keep the event loop alive on account of the limiter.
      this.sweepTimer.unref?.();
    }
  }

  /**
   * Account one hit for `key`. Returns whether it is allowed plus the seconds
   * until the window resets (for the Retry-After header on rejection).
   */
  hit(
    key: string,
    now: number = Date.now(),
  ): {
    allowed: boolean;
    retryAfterSec: number;
  } {
    const mapKey = `${this.tier.bucket}:${key}`;
    const existing = this.buckets.get(mapKey);

    if (!existing || now >= existing.resetAt) {
      // Start a fresh window.
      this.buckets.set(mapKey, { count: 1, resetAt: now + this.tier.windowMs });
      return { allowed: true, retryAfterSec: 0 };
    }

    existing.count += 1;
    if (existing.count > this.tier.limit) {
      return {
        allowed: false,
        retryAfterSec: Math.max(1, Math.ceil((existing.resetAt - now) / 1000)),
      };
    }
    return { allowed: true, retryAfterSec: 0 };
  }

  /** Evict windows that have already reset so the Map can't grow unbounded. */
  private sweep(now: number = Date.now()): void {
    for (const [k, v] of this.buckets) {
      if (now >= v.resetAt) {
        this.buckets.delete(k);
      }
    }
  }

  /** Stop the sweep timer (used by tests / shutdown). */
  stop(): void {
    if (this.sweepTimer) {
      clearInterval(this.sweepTimer);
    }
  }

  /** Test helper: current number of tracked keys. */
  size(): number {
    return this.buckets.size;
  }
}

/**
 * Build an Express middleware that enforces `tier` keyed on the real client IP.
 * The optional `limiter` lets tests inject a non-sweeping / low-limit instance.
 */
export function rateLimitMiddleware(
  tier: RateLimitTier,
  // Under Jest, construct the default limiter WITHOUT the background sweep
  // interval: the app singleton is imported by handler suites that don't want
  // stray timers churning across parallel workers, and the window is short-lived
  // per test anyway. Production keeps the sweep so the Map can't grow unbounded.
  limiter: RateLimiter = new RateLimiter(
    tier,
    tier.windowMs,
    /* enableSweep */ !process.env.JEST_WORKER_ID,
  ),
) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const { allowed, retryAfterSec } = limiter.hit(clientIp(req));
    if (allowed) {
      next();
      return;
    }
    res.setHeader("Retry-After", String(retryAfterSec));
    res.status(429).json({
      error: "Too many requests. Please slow down and try again shortly.",
      requestId: (req as Request & { id?: string }).id,
    });
  };
}
