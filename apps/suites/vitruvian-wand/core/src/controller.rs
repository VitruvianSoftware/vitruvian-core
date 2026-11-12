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

//! BLE controller metadata and packet decoding abstraction.

use crate::protocol::daydream::{self, Sample};

/// Standard BLE Battery Service 16-bit UUID (`0x180F`).
pub const BATTERY_SERVICE_ID: u16 = 0x180F;

/// Standard BLE Battery Level characteristic 16-bit UUID (`0x2A19`).
pub const BATTERY_CHAR_ID: u16 = 0x2A19;

/// Standard BLE Battery Service 128-bit UUID string.
pub const BATTERY_SERVICE_UUID: &str = "0000180f-0000-1000-8000-00805f9b34fb";

/// Standard BLE Battery Level characteristic 128-bit UUID string.
pub const BATTERY_CHAR_UUID: &str = "00002a19-0000-1000-8000-00805f9b34fb";

/// Trait implemented by 3DoF/6DoF BLE air-mouse controllers.
pub trait Controller {
    /// Advertised BLE peripheral name.
    fn name(&self) -> &'static str;

    /// Primary GATT service UUID string.
    fn service_uuid(&self) -> &'static str;

    /// Notification characteristic UUID string carrying sensor packets.
    fn notify_uuid(&self) -> &'static str;

    /// Decodes a 20-byte sensor notification packet into a normalized [`Sample`].
    fn decode(&self, packet: &[u8; 20]) -> Sample;
}

/// Google Daydream controller descriptor and decoder.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Daydream;

impl Daydream {
    /// Advertised BLE device name for the Google Daydream controller.
    pub const NAME: &'static str = "Daydream controller";

    /// Daydream primary GATT service 16-bit short ID (`0xFE55`).
    pub const SERVICE_ID: u16 = 0xFE55;

    /// Daydream primary GATT service 128-bit UUID.
    pub const SERVICE_UUID: &'static str = "0000fe55-0000-1000-8000-00805f9b34fb";

    /// Daydream sensor notification characteristic 128-bit UUID.
    pub const NOTIFY_UUID: &'static str = "00000001-1000-1000-8000-00805f9b34fb";
}

impl Controller for Daydream {
    fn name(&self) -> &'static str {
        Self::NAME
    }

    fn service_uuid(&self) -> &'static str {
        Self::SERVICE_UUID
    }

    fn notify_uuid(&self) -> &'static str {
        Self::NOTIFY_UUID
    }

    fn decode(&self, packet: &[u8; 20]) -> Sample {
        daydream::decode(packet)
    }
}
