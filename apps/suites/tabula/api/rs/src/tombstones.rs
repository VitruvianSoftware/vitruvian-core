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

use crate::crypto::now_iso8601;
use crate::store::RedisStore;

/// 30 days in seconds — matches `TOMBSTONE_TTL_SECONDS` in `src/lib/tombstones.ts`.
pub const TOMBSTONE_TTL_SECONDS: u64 = 60 * 60 * 24 * 30;

pub fn tombstone_key(user_id: &str, entity_type: &str, entity_id: &str) -> String {
    format!("tombstone:{user_id}:{entity_type}:{entity_id}")
}

/// Record a deletion tombstone for `(user_id, entity_type, entity_id)` in Redis.
/// Best-effort (swallows Redis errors so deletes are not blocked).
pub fn set_tombstone(redis: &dyn RedisStore, user_id: &str, entity_type: &str, entity_id: &str) {
    let key = tombstone_key(user_id, entity_type, entity_id);
    let _ = redis.set_ex(&key, &now_iso8601(), TOMBSTONE_TTL_SECONDS);
}

/// Check whether `(user_id, entity_type, entity_id)` has been deleted within the tombstone window.
/// Fails open (returns `false`) if Redis errors.
pub fn is_tombstoned(
    redis: &dyn RedisStore,
    user_id: &str,
    entity_type: &str,
    entity_id: &str,
) -> bool {
    let key = tombstone_key(user_id, entity_type, entity_id);
    match redis.get(&key) {
        Ok(Some(_)) => true,
        Ok(None) | Err(_) => false,
    }
}

/// Drop cached sync version & state keys for a deleted entity.
/// Best-effort (swallows Redis errors).
pub fn clear_sync_keys(redis: &dyn RedisStore, user_id: &str, entity_type: &str, entity_id: &str) {
    let v_key = format!("sync:version:{user_id}:{entity_type}:{entity_id}");
    let s_key = format!("sync:state:{user_id}:{entity_type}:{entity_id}");
    let _ = redis.del(&[&v_key, &s_key]);
}

/// Mark an entity as deleted for sync convergence: write the tombstone and clear sync keys.
pub fn mark_entity_deleted(
    redis: &dyn RedisStore,
    user_id: &str,
    entity_type: &str,
    entity_id: &str,
) {
    set_tombstone(redis, user_id, entity_type, entity_id);
    clear_sync_keys(redis, user_id, entity_type, entity_id);
}
