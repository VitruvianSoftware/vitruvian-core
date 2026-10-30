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

use crate::store::RedisStore;
use serde_json::{json, Value};

#[derive(Debug, Clone)]
pub struct SyncEventInput<'a> {
    pub entity_type: &'a str,
    pub action: &'a str,
    pub entity_id: &'a str,
    pub version: Option<u64>,
    pub updated_at: String,
    pub from_device: &'a str,
}

/// Publish a change notification on `sync:updates:<userId>` (`src/lib/syncEvents.ts`).
/// Fire-and-forget: never fails a write when Redis is unavailable.
pub fn publish_sync_event(redis: &dyn RedisStore, user_id: &str, event: SyncEventInput<'_>) {
    let channel = format!("sync:updates:{user_id}");
    let mut payload = json!({
        "type": event.entity_type,
        "action": event.action,
        "entityId": event.entity_id,
        "updatedAt": event.updated_at,
        "fromDevice": event.from_device,
    });
    if let Some(obj) = payload.as_object_mut() {
        if let Some(v) = event.version {
            obj.insert("version".to_string(), Value::from(v));
        }
    }
    let _ = redis.publish(&channel, &payload.to_string());
}
