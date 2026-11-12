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

//! Wire protocol decoders for supported BLE controllers.

pub mod daydream {
    //! Google Daydream controller 20-byte notification decoder.
    //!
    //! The bit layout and scale constants are ported from
    //! [`mrdoob/daydream-controller.js`](https://github.com/mrdoob/daydream-controller.js)
    //! by Ricardo Cabello (`mrdoob`), licensed under the MIT License.

    use serde::{Deserialize, Serialize};
    use std::f32::consts::PI;

    /// Scale factor converting a signed 13-bit orientation value (`-4096..=4095`) to radians.
    pub const ORI_SCALE: f32 = 2.0 * PI / 4095.0;

    /// Scale factor converting a signed 13-bit accelerometer value (`-4096..=4095`) to m/s².
    pub const ACC_SCALE: f32 = 8.0 * 9.8 / 4095.0;

    /// Scale factor converting a signed 13-bit gyroscope value (`-4096..=4095`) to rad/s.
    pub const GYRO_SCALE: f32 = (2048.0 / 180.0) * PI / 4095.0;

    /// Three-axis vector used for orientation, acceleration (m/s²), and angular velocity (rad/s).
    #[derive(Debug, Clone, Copy, PartialEq, Default, Serialize, Deserialize)]
    pub struct Vec3 {
        pub x: f32,
        pub y: f32,
        pub z: f32,
    }

    impl Vec3 {
        /// Creates a new `Vec3`.
        #[inline]
        pub const fn new(x: f32, y: f32, z: f32) -> Self {
            Self { x, y, z }
        }

        /// Returns the Euclidean norm `sqrt(x² + y² + z²)`.
        #[inline]
        pub fn norm(self) -> f32 {
            (self.x * self.x + self.y * self.y + self.z * self.z).sqrt()
        }
    }

    /// Decoded state from a single 20-byte Daydream BLE notification packet.
    #[derive(Debug, Clone, Copy, PartialEq, Default, Serialize, Deserialize)]
    pub struct Sample {
        /// 9-bit controller timestamp (`0..=511`).
        pub time: u16,
        /// 5-bit packet sequence number (`0..=31`).
        pub seq: u8,
        /// Orientation vector in radians.
        pub orientation: Vec3,
        /// Linear acceleration vector in m/s².
        pub accel: Vec3,
        /// Angular velocity vector in rad/s.
        pub gyro: Vec3,
        /// Normalized horizontal touch coordinate in `0.0..=1.0` (`0.0` when untouched).
        pub touch_x: f32,
        /// Normalized vertical touch coordinate in `0.0..=1.0` (`0.0` when untouched).
        pub touch_y: f32,
        /// `true` when a finger is touching the pad (`touch_x > 0.0 || touch_y > 0.0`).
        pub touching: bool,
        /// Touchpad click button pressed (`byte[18] & 0x01`).
        pub click: bool,
        /// Home button pressed (`byte[18] & 0x02`).
        pub home: bool,
        /// App button pressed (`byte[18] & 0x04`).
        pub app: bool,
        /// Volume down button pressed (`byte[18] & 0x08`).
        pub vol_down: bool,
        /// Volume up button pressed (`byte[18] & 0x10`).
        pub vol_up: bool,
    }

    /// Sign-extends an unsigned 13-bit integer (`0..=0x1FFF`) to a signed `i16` (`-4096..=4095`).
    #[inline]
    pub fn sign_extend_13(raw: u16) -> i16 {
        (((raw & 0x1FFF) << 3) as i16) >> 3
    }

    /// Decodes a 20-byte Daydream controller BLE notification packet into a [`Sample`].
    ///
    /// Bit layout adapted from [`mrdoob/daydream-controller.js`](https://github.com/mrdoob/daydream-controller.js) (MIT).
    pub fn decode(b: &[u8; 20]) -> Sample {
        let time = ((b[0] as u16) << 1) | ((b[1] as u16 & 0x80) >> 7);
        let seq = (b[1] & 0x7C) >> 2;

        // NOTE on xOri low bit(s):
        // mrdoob/daydream-controller.js writes:
        //   (b[1] & 0x03) << 11 | (b[2] & 0xFF) << 3 | (b[3] & 0x80) >> 5
        // Every other packed field in the packet shifts its trailing bits down to bit 0,
        // and masking with 0x80 isolates only 1 bit (bit 7 of byte 3), so `>> 5` leaves
        // bits 1..=0 always zero and puts bit 7 at bit 2 instead of bit 0 (almost certainly
        // a typo for either `(b[3] & 0xE0) >> 5` or `(b[3] & 0x80) >> 7`). Per specification,
        // we shift the carried bit `b[3] & 0x80` to bit 0 via `>> 7`.
        let x_ori_raw =
            ((b[1] as u16 & 0x03) << 11) | ((b[2] as u16) << 3) | ((b[3] as u16 & 0x80) >> 7);
        let y_ori_raw = ((b[3] as u16 & 0x1F) << 8) | (b[4] as u16);
        let z_ori_raw = ((b[5] as u16) << 5) | ((b[6] as u16 & 0xF8) >> 3);

        let x_acc_raw =
            ((b[6] as u16 & 0x07) << 10) | ((b[7] as u16) << 2) | ((b[8] as u16 & 0xC0) >> 6);
        let y_acc_raw = ((b[8] as u16 & 0x3F) << 7) | ((b[9] as u16 & 0xFE) >> 1);
        let z_acc_raw =
            ((b[9] as u16 & 0x01) << 12) | ((b[10] as u16) << 4) | ((b[11] as u16 & 0xF0) >> 4);

        let x_gyro_raw =
            ((b[11] as u16 & 0x0F) << 9) | ((b[12] as u16) << 1) | ((b[13] as u16 & 0x80) >> 7);
        let y_gyro_raw = ((b[13] as u16 & 0x7F) << 6) | ((b[14] as u16 & 0xFC) >> 2);
        let z_gyro_raw =
            ((b[14] as u16 & 0x03) << 11) | ((b[15] as u16) << 3) | ((b[16] as u16 & 0xE0) >> 5);

        let raw_touch_x = ((b[16] & 0x1F) << 3) | ((b[17] & 0xE0) >> 5);
        let raw_touch_y = ((b[17] & 0x1F) << 3) | ((b[18] & 0xE0) >> 5);
        let touching = raw_touch_x > 0 || raw_touch_y > 0;
        let touch_x = raw_touch_x as f32 / 255.0;
        let touch_y = raw_touch_y as f32 / 255.0;

        let buttons = b[18];
        let click = (buttons & 0x01) != 0;
        let home = (buttons & 0x02) != 0;
        let app = (buttons & 0x04) != 0;
        let vol_down = (buttons & 0x08) != 0;
        let vol_up = (buttons & 0x10) != 0;

        Sample {
            time,
            seq,
            orientation: Vec3 {
                x: sign_extend_13(x_ori_raw) as f32 * ORI_SCALE,
                y: sign_extend_13(y_ori_raw) as f32 * ORI_SCALE,
                z: sign_extend_13(z_ori_raw) as f32 * ORI_SCALE,
            },
            accel: Vec3 {
                x: sign_extend_13(x_acc_raw) as f32 * ACC_SCALE,
                y: sign_extend_13(y_acc_raw) as f32 * ACC_SCALE,
                z: sign_extend_13(z_acc_raw) as f32 * ACC_SCALE,
            },
            gyro: Vec3 {
                x: sign_extend_13(x_gyro_raw) as f32 * GYRO_SCALE,
                y: sign_extend_13(y_gyro_raw) as f32 * GYRO_SCALE,
                z: sign_extend_13(z_gyro_raw) as f32 * GYRO_SCALE,
            },
            touch_x,
            touch_y,
            touching,
            click,
            home,
            app,
            vol_down,
            vol_up,
        }
    }
}

pub use daydream::{Sample, Vec3};
