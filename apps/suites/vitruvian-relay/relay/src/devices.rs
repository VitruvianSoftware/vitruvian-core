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

//! Device records: what the relay knows about each registered Mac. Where they
//! are kept is [`crate::store`].

use std::time::SystemTime;

/// A registered, not revoked, device.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceRecord {
    pub device_id: String,
    pub owner_sub: String,
    /// What the person calls it (shown in the device list).
    pub name: String,
    pub public_key_ed25519: [u8; 32],
    pub created_at: SystemTime,
    /// The last time the device connected (or was connected); `None` if never.
    pub last_seen: Option<SystemTime>,
    /// A revoked device is never returned by `Store::device` or
    /// `Store::devices_of`, so this is `false` on every record they return.
    pub revoked: bool,
}

/// A device about to be stored. The store sets `created_at`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewDevice {
    pub device_id: String,
    pub owner_sub: String,
    pub name: String,
    pub public_key_ed25519: [u8; 32],
}

/// What a device is called until its owner renames it.
pub const DEFAULT_DEVICE_NAME: &str = "My Mac";
