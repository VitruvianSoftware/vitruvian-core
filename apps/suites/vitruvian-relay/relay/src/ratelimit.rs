// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! One person's calls per minute: a token bucket, kept in memory.
//!
//! A bucket holds up to [`RATE_BURST`] calls and gains
//! [`CALLS_PER_MINUTE_PER_USER`] a minute, a little at a time. A person who
//! has been quiet can make a burst of 20 at once, then about one a second.
//! The point is only to stop a runaway AI app (or a loop) from flooding one
//! person's computer, so it is per person, not per computer or per app: a
//! second AI app does not get a second allowance.
//!
//! The relay is one process, so memory is enough. A restart gives everyone a
//! full bucket, which is harmless.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Calls a person may make in a minute, once a burst is used up.
pub const CALLS_PER_MINUTE_PER_USER: u32 = 60;
/// Calls a person may make at once after being quiet.
pub const RATE_BURST: u32 = 20;

/// What a person is told when a call is refused. Plain words, and what to do.
pub const RATE_LIMITED_MESSAGE: &str =
    "Too many requests from your account; wait a minute and try again.";
/// The outcome recorded for such a call.
pub const RATE_LIMITED_OUTCOME: &str = "rate_limited";

/// Most people tracked before the idle ones are dropped.
const PRUNE_ABOVE: usize = 1024;

/// A refused call: how long until the next one would be let through.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Retry {
    pub after: Duration,
}

struct Bucket {
    /// Whole and fractional calls left, never above the burst.
    tokens: f64,
    at: Instant,
}

type Clock = Arc<dyn Fn() -> Instant + Send + Sync>;

pub struct RateLimit {
    per_minute: u32,
    burst: u32,
    clock: Clock,
    buckets: Mutex<HashMap<String, Bucket>>,
}

impl RateLimit {
    /// `per_minute` calls a minute with a burst of `burst` (at least 1 each).
    pub fn new(per_minute: u32, burst: u32) -> Self {
        Self::with_clock(per_minute, burst, Arc::new(Instant::now))
    }

    /// As [`RateLimit::new`], reading the time from `clock`: for tests.
    pub fn with_clock(per_minute: u32, burst: u32, clock: Clock) -> Self {
        RateLimit {
            per_minute: per_minute.max(1),
            burst: burst.max(1),
            clock,
            buckets: Mutex::new(HashMap::new()),
        }
    }

    /// Lets `subject`'s call through and spends a place, or says how long
    /// to wait. A refused call spends nothing.
    pub fn check(&self, subject: &str) -> Result<(), Retry> {
        let now = (self.clock)();
        let per_second = f64::from(self.per_minute) / 60.0;
        let burst = f64::from(self.burst);
        let mut buckets = self.buckets.lock().unwrap();
        if buckets.len() >= PRUNE_ABOVE {
            // A bucket that has refilled to the top is the same as no bucket
            // at all, so dropping it loses nothing.
            buckets.retain(|_, b| {
                b.tokens + now.saturating_duration_since(b.at).as_secs_f64() * per_second < burst
            });
        }
        let b = buckets.entry(subject.to_string()).or_insert(Bucket {
            tokens: burst,
            at: now,
        });
        let gained = now.saturating_duration_since(b.at).as_secs_f64() * per_second;
        b.tokens = (b.tokens + gained).min(burst);
        b.at = now;
        if b.tokens >= 1.0 {
            b.tokens -= 1.0;
            Ok(())
        } else {
            Err(Retry {
                after: Duration::from_secs_f64((1.0 - b.tokens) / per_second),
            })
        }
    }

    /// People with a bucket right now (tests).
    #[cfg(test)]
    fn tracked(&self) -> usize {
        self.buckets.lock().unwrap().len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A clock the test moves by hand.
    fn manual() -> (Clock, Arc<Mutex<Instant>>) {
        let now = Arc::new(Mutex::new(Instant::now()));
        let n = now.clone();
        (Arc::new(move || *n.lock().unwrap()), now)
    }

    fn advance(now: &Mutex<Instant>, by: Duration) {
        *now.lock().unwrap() += by;
    }

    #[test]
    fn the_constants_are_the_spec_values() {
        assert_eq!(CALLS_PER_MINUTE_PER_USER, 60);
        assert_eq!(RATE_BURST, 20);
        assert_eq!(
            RATE_LIMITED_MESSAGE,
            "Too many requests from your account; wait a minute and try again."
        );
    }

    #[test]
    fn a_burst_of_twenty_then_the_twenty_first_is_refused() {
        let (clock, _) = manual();
        let rl = RateLimit::with_clock(CALLS_PER_MINUTE_PER_USER, RATE_BURST, clock);
        for i in 1..=20 {
            assert!(rl.check("alice").is_ok(), "call {i}");
        }
        let refused = rl.check("alice").unwrap_err();
        // One call a second: the next place is a second away.
        assert_eq!(refused.after, Duration::from_secs(1));
        // Refusing spent nothing and gained nothing: still refused.
        assert!(rl.check("alice").is_err());
    }

    #[test]
    fn it_refills_a_call_a_second_and_never_above_the_burst() {
        let (clock, now) = manual();
        let rl = RateLimit::with_clock(60, 20, clock);
        for _ in 0..20 {
            rl.check("alice").unwrap();
        }
        assert!(rl.check("alice").is_err());
        advance(&now, Duration::from_millis(1500));
        assert!(rl.check("alice").is_ok(), "one place came back");
        assert!(rl.check("alice").is_err(), "only one");
        advance(&now, Duration::from_secs(3600));
        for i in 1..=20 {
            assert!(rl.check("alice").is_ok(), "full again, call {i}");
        }
        assert!(rl.check("alice").is_err(), "an hour away is not 3600 calls");
    }

    #[test]
    fn each_person_has_their_own_bucket() {
        let (clock, _) = manual();
        let rl = RateLimit::with_clock(60, 20, clock);
        for _ in 0..20 {
            rl.check("alice").unwrap();
        }
        assert!(rl.check("alice").is_err());
        assert!(rl.check("bob").is_ok(), "bob is not held up by alice");
    }

    #[test]
    fn idle_people_do_not_pile_up_in_memory_but_a_busy_one_is_kept() {
        let (clock, now) = manual();
        let rl = RateLimit::with_clock(60, 20, clock);
        for _ in 0..20 {
            rl.check("busy").unwrap();
        }
        for i in 0..PRUNE_ABOVE {
            rl.check(&format!("p{i}")).unwrap();
        }
        assert_eq!(rl.tracked(), PRUNE_ABOVE + 1);
        // Five seconds on, everyone else is back to a full bucket (the same
        // as not being tracked); "busy" has only 5 places back.
        advance(&now, Duration::from_secs(5));
        rl.check("newcomer").unwrap();
        assert_eq!(rl.tracked(), 2, "busy and the newcomer");
        for i in 1..=5 {
            assert!(
                rl.check("busy").is_ok(),
                "place {i} of the 5 that came back"
            );
        }
        assert!(
            rl.check("busy").is_err(),
            "pruning did not hand busy a full bucket"
        );
    }
}
