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

//! Cache for the installed macOS voice list.
//!
//! Listing voices means running `say -v ?`, which takes seconds on a Mac with
//! many voices installed. `GET /v1/homespeaker` is polled by the Mac panel, the
//! menu and the phone, so running it per request piled up `say` children and
//! pegged the CPU. This cache keeps a good list for [`VOICE_TTL`], remembers a
//! failure for [`VOICE_FAILURE_TTL`] so a broken `say` is not retried per
//! request either, and lets only one refresh run at a time: callers that arrive
//! during a refresh wait for it and share its result.

use std::sync::{Arc, Condvar, Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

use crate::homespeaker::{HomeSpeakerVoice, ListVoicesFn};

/// How long a successful, non-empty voice list is served without re-listing.
pub const VOICE_TTL: Duration = Duration::from_secs(10 * 60);
/// How long a failed (or empty) listing suppresses another attempt.
pub const VOICE_FAILURE_TTL: Duration = Duration::from_secs(30);

pub type ClockFn = Arc<dyn Fn() -> Instant + Send + Sync>;

#[derive(Default)]
struct Slot {
    /// Last good list and when it was fetched.
    good: Option<(Vec<HomeSpeakerVoice>, Instant)>,
    /// Last failure and when it happened.
    failed: Option<(String, Instant)>,
    /// A refresh is running; others wait on the condvar instead of spawning.
    refreshing: bool,
}

pub struct VoiceCache {
    ttl: Duration,
    failure_ttl: Duration,
    clock: ClockFn,
    slot: Mutex<Slot>,
    done: Condvar,
}

/// Clears `refreshing` and wakes waiters even if the lister panics, so a
/// panic cannot leave every later caller blocked.
struct RefreshGuard<'a> {
    cache: &'a VoiceCache,
}

impl Drop for RefreshGuard<'_> {
    fn drop(&mut self) {
        self.cache.lock().refreshing = false;
        self.cache.done.notify_all();
    }
}

impl VoiceCache {
    pub fn new(ttl: Duration, failure_ttl: Duration, clock: ClockFn) -> Self {
        Self {
            ttl,
            failure_ttl,
            clock,
            slot: Mutex::new(Slot::default()),
            done: Condvar::new(),
        }
    }

    fn lock(&self) -> MutexGuard<'_, Slot> {
        self.slot.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// The voice list, running `lister` only when nothing usable is cached.
    ///
    /// Within a recent failure window it returns the last good list if there
    /// is one (stale but real), otherwise the failure. A failure or an empty
    /// list is never stored as the good list.
    pub fn get(&self, lister: &ListVoicesFn) -> Result<Vec<HomeSpeakerVoice>, String> {
        let mut slot = self.lock();
        loop {
            let now = (self.clock)();
            if let Some((ref v, at)) = slot.good {
                if now.saturating_duration_since(at) < self.ttl {
                    return Ok(v.clone());
                }
            }
            if let Some((ref e, at)) = slot.failed {
                if now.saturating_duration_since(at) < self.failure_ttl {
                    return match slot.good {
                        Some((ref v, _)) => Ok(v.clone()),
                        None => Err(e.clone()),
                    };
                }
            }
            if !slot.refreshing {
                break;
            }
            slot = self.done.wait(slot).unwrap_or_else(|p| p.into_inner());
        }
        slot.refreshing = true;
        drop(slot);

        let guard = RefreshGuard { cache: self };
        let result = match lister() {
            Ok(v) if !v.is_empty() => Ok(v),
            Ok(_) => Err("no voices listed".to_string()),
            Err(e) => Err(e),
        };
        let now = (self.clock)();
        let mut slot = self.lock();
        let out = match result {
            Ok(v) => {
                slot.good = Some((v.clone(), now));
                slot.failed = None;
                Ok(v)
            }
            Err(e) => {
                slot.failed = Some((e.clone(), now));
                match slot.good {
                    Some((ref v, _)) => Ok(v.clone()),
                    None => Err(e),
                }
            }
        };
        drop(slot);
        drop(guard);
        out
    }
}

/// The one cache the running agent shares across every request.
pub fn shared_voice_cache() -> Arc<VoiceCache> {
    static CACHE: OnceLock<Arc<VoiceCache>> = OnceLock::new();
    CACHE
        .get_or_init(|| {
            Arc::new(VoiceCache::new(
                VOICE_TTL,
                VOICE_FAILURE_TTL,
                Arc::new(Instant::now),
            ))
        })
        .clone()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
    use std::sync::Barrier;

    /// A clock the test moves by hand.
    #[derive(Clone)]
    struct FakeClock {
        base: Instant,
        offset_ms: Arc<AtomicU64>,
    }

    impl FakeClock {
        fn new() -> Self {
            Self {
                base: Instant::now(),
                offset_ms: Arc::new(AtomicU64::new(0)),
            }
        }
        fn advance(&self, d: Duration) {
            self.offset_ms
                .fetch_add(d.as_millis() as u64, Ordering::SeqCst);
        }
        fn clock(&self) -> ClockFn {
            let c = self.clone();
            Arc::new(move || c.base + Duration::from_millis(c.offset_ms.load(Ordering::SeqCst)))
        }
    }

    fn voice(name: &str) -> HomeSpeakerVoice {
        HomeSpeakerVoice {
            id: name.to_string(),
            name: name.to_string(),
            lang: "en_US".to_string(),
        }
    }

    fn counting(
        calls: &Arc<AtomicUsize>,
        result: Result<Vec<HomeSpeakerVoice>, String>,
    ) -> ListVoicesFn {
        let calls = calls.clone();
        Arc::new(move || {
            calls.fetch_add(1, Ordering::SeqCst);
            result.clone()
        })
    }

    #[test]
    fn test_repeat_calls_within_ttl_list_once() {
        let clock = FakeClock::new();
        let cache = VoiceCache::new(VOICE_TTL, VOICE_FAILURE_TTL, clock.clock());
        let calls = Arc::new(AtomicUsize::new(0));
        let lister = counting(&calls, Ok(vec![voice("Alex")]));
        for _ in 0..20 {
            assert_eq!(cache.get(&lister).unwrap(), vec![voice("Alex")]);
            clock.advance(Duration::from_secs(20));
        }
        // 20 calls over 380 s, all inside the 10-minute TTL.
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn test_refreshes_after_ttl() {
        let clock = FakeClock::new();
        let cache = VoiceCache::new(VOICE_TTL, VOICE_FAILURE_TTL, clock.clock());
        let calls = Arc::new(AtomicUsize::new(0));
        let lister = counting(&calls, Ok(vec![voice("Alex")]));
        cache.get(&lister).unwrap();
        clock.advance(VOICE_TTL - Duration::from_secs(1));
        cache.get(&lister).unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        clock.advance(Duration::from_secs(2));
        cache.get(&lister).unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn test_failure_is_not_cached_as_success_and_is_retried_after_window() {
        let clock = FakeClock::new();
        let cache = VoiceCache::new(VOICE_TTL, VOICE_FAILURE_TTL, clock.clock());
        let calls = Arc::new(AtomicUsize::new(0));
        let failing = counting(&calls, Err("say -v ? failed".to_string()));
        assert!(cache.get(&failing).is_err());
        // Inside the failure window: no new spawn, still an error.
        for _ in 0..10 {
            assert!(cache.get(&failing).is_err());
        }
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        // After the short window it tries again, well before the 10-minute TTL.
        clock.advance(VOICE_FAILURE_TTL + Duration::from_secs(1));
        let ok_calls = Arc::new(AtomicUsize::new(0));
        let ok = counting(&ok_calls, Ok(vec![voice("Samantha")]));
        assert_eq!(cache.get(&ok).unwrap(), vec![voice("Samantha")]);
        assert_eq!(ok_calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn test_empty_list_counts_as_failure() {
        let clock = FakeClock::new();
        let cache = VoiceCache::new(VOICE_TTL, VOICE_FAILURE_TTL, clock.clock());
        let calls = Arc::new(AtomicUsize::new(0));
        let empty = counting(&calls, Ok(Vec::new()));
        assert!(cache.get(&empty).is_err());
        clock.advance(VOICE_FAILURE_TTL + Duration::from_secs(1));
        assert!(cache.get(&empty).is_err());
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn test_failed_refresh_keeps_serving_last_good_list() {
        let clock = FakeClock::new();
        let cache = VoiceCache::new(VOICE_TTL, VOICE_FAILURE_TTL, clock.clock());
        let calls = Arc::new(AtomicUsize::new(0));
        cache
            .get(&counting(&calls, Ok(vec![voice("Alex")])))
            .unwrap();
        clock.advance(VOICE_TTL + Duration::from_secs(1));
        let failing = counting(&calls, Err("boom".to_string()));
        assert_eq!(cache.get(&failing).unwrap(), vec![voice("Alex")]);
        assert_eq!(cache.get(&failing).unwrap(), vec![voice("Alex")]);
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn test_concurrent_callers_share_one_listing() {
        let cache = Arc::new(VoiceCache::new(
            VOICE_TTL,
            VOICE_FAILURE_TTL,
            Arc::new(Instant::now),
        ));
        let calls = Arc::new(AtomicUsize::new(0));
        let calls_l = calls.clone();
        // Slow, like `say -v ?` with many voices, so every thread arrives mid-refresh.
        let lister: ListVoicesFn = Arc::new(move || {
            calls_l.fetch_add(1, Ordering::SeqCst);
            std::thread::sleep(Duration::from_millis(300));
            Ok(vec![voice("Alex")])
        });
        let n = 8;
        let barrier = Arc::new(Barrier::new(n));
        let handles: Vec<_> = (0..n)
            .map(|_| {
                let cache = cache.clone();
                let lister = lister.clone();
                let barrier = barrier.clone();
                std::thread::spawn(move || {
                    barrier.wait();
                    cache.get(&lister).unwrap()
                })
            })
            .collect();
        for h in handles {
            assert_eq!(h.join().unwrap(), vec![voice("Alex")]);
        }
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn test_panicking_lister_does_not_wedge_the_cache() {
        let clock = FakeClock::new();
        let cache = Arc::new(VoiceCache::new(VOICE_TTL, VOICE_FAILURE_TTL, clock.clock()));
        let c2 = cache.clone();
        let panicking: ListVoicesFn = Arc::new(|| panic!("lister blew up"));
        let joined = std::thread::spawn(move || c2.get(&panicking)).join();
        assert!(joined.is_err());
        let calls = Arc::new(AtomicUsize::new(0));
        let ok = counting(&calls, Ok(vec![voice("Alex")]));
        assert_eq!(cache.get(&ok).unwrap(), vec![voice("Alex")]);
    }
}
