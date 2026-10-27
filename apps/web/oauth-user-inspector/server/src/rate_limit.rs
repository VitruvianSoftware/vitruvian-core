// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

use crate::logger::now_epoch_ms;

/// Per-instance sliding-window rate limiter keyed by client IP.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RateLimitTier {
    /// Human-readable tier name used in 429 logs.
    pub name: String,
    /// Maximum requests allowed per `window_ms` per IP.
    pub max: usize,
    /// Sliding window length in milliseconds.
    pub window_ms: u64,
}

impl RateLimitTier {
    pub fn new(name: impl Into<String>, max: usize, window_ms: u64) -> Self {
        Self {
            name: name.into(),
            max,
            window_ms,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HitResult {
    pub allowed: bool,
    pub retry_after_sec: u64,
}

#[derive(Debug, Clone)]
pub struct RateLimiter {
    pub tier: RateLimitTier,
    buckets: Vec<(String, Vec<u64>)>,
    max_keys: usize,
}

impl RateLimiter {
    pub fn new(tier: RateLimitTier) -> Self {
        Self::with_max_keys(tier, 10_000)
    }

    pub fn with_max_keys(tier: RateLimitTier, max_keys: usize) -> Self {
        Self {
            tier,
            buckets: Vec::new(),
            max_keys,
        }
    }

    pub fn hit(&mut self, key: &str) -> HitResult {
        self.hit_at(key, now_epoch_ms())
    }

    pub fn hit_at(&mut self, key: &str, now_ms: u64) -> HitResult {
        let cutoff = now_ms.saturating_sub(self.tier.window_ms);

        let existing_idx = self.buckets.iter().position(|(k, _)| k == key);
        if existing_idx.is_none() && self.buckets.len() >= self.max_keys {
            self.sweep_at(now_ms);
            if self.buckets.len() >= self.max_keys && !self.buckets.is_empty() {
                self.buckets.remove(0);
            }
        }

        let idx = match self.buckets.iter().position(|(k, _)| k == key) {
            Some(i) => i,
            None => {
                self.buckets.push((key.to_string(), Vec::new()));
                self.buckets.len() - 1
            }
        };

        let hits = &mut self.buckets[idx].1;
        hits.retain(|&t| t > cutoff);

        if hits.len() >= self.tier.max {
            let oldest = hits[0];
            let retry_after_ms = (oldest + self.tier.window_ms)
                .saturating_sub(now_ms)
                .max(1000);
            let retry_after_sec = retry_after_ms.div_ceil(1000);
            return HitResult {
                allowed: false,
                retry_after_sec,
            };
        }

        hits.push(now_ms);
        HitResult {
            allowed: true,
            retry_after_sec: 0,
        }
    }

    pub fn sweep(&mut self) {
        self.sweep_at(now_epoch_ms());
    }

    pub fn sweep_at(&mut self, now_ms: u64) {
        let cutoff = now_ms.saturating_sub(self.tier.window_ms);
        for (_, hits) in &mut self.buckets {
            hits.retain(|&t| t > cutoff);
        }
        self.buckets.retain(|(_, hits)| !hits.is_empty());
    }

    pub fn size(&self) -> usize {
        self.buckets.len()
    }
}

/// Extract the best-effort client IP. Behind Cloudflare + Cloud Run:
/// - `CF-Connecting-IP` is set by Cloudflare to the single eyeball IP and
///   overwrites any client-supplied header of the same name.
/// - `req_ip` is the fallback (e.g. `X-Forwarded-For` when `trust proxy` is enabled).
pub fn client_ip(cf_connecting_ip: Option<&str>, req_ip: Option<&str>) -> String {
    if let Some(cf) = cf_connecting_ip {
        let trimmed = cf.trim();
        if !trimmed.is_empty() {
            return trimmed.split(',').next().unwrap_or("").trim().to_string();
        }
    }
    req_ip
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or("unknown")
        .to_string()
}
