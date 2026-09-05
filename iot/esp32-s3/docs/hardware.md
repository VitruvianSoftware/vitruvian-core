# mac-controller Hardware & BOM Specification

This document provides the hardware bill of materials, complete pinout tables, display and touch controller specifications, power characteristics, and enclosure guidelines for the ESP32-S3 Mac Controller.

---

## 1. Bill of Materials (BOM)

| Component | Manufacturer & Part Number | Key Specifications |
|---|---|---|
| **Development Board** | Waveshare ESP32-S3-Touch-LCD-1.69 (SKU: 26145) | Complete module with display, touch, MCU, and power circuit |
| **Microcontroller (MCU)** | Espressif Systems ESP32-S3R8 / ESP32-S3FN8 | Xtensa 32-bit LX7 dual-core up to 240 MHz, 512KB SRAM, 384KB ROM |
| **Flash Memory** | Winbond / GigaDevice 16 MB SPI Flash | 128 Mbit Quad SPI (QIO mode, 80 MHz) |
| **PSRAM Memory** | APMemory 8 MB Octal PSRAM | 64 Mbit Octal SPI (OPI mode, 80 MHz) |
| **Display Panel** | Waveshare 1.69" IPS LCD | 240 × 280 resolution, 262K colors, IPS wide viewing angle |
| **Display Driver IC** | Sitronix ST7789V2 | 4-wire SPI interface up to 80 MHz, internal frame memory |
| **Touch Controller** | Hynitron CST816T | Single-touch capacitive touch sensor, gesture engine, I2C interface |
| **Inertial Measurement Unit** | QST QMI8658 | 6-axis IMU (3-axis accelerometer + 3-axis gyroscope), I2C interface, drives display auto-rotate |
| **Audio Transducer** | SMD Piezoelectric Buzzer | Driven via GPIO 42 (active 2.4 kHz resonant frequency) |
| **Power Management** | SGM6603 / TP4056-compatible | 5V USB-C input, 3.3V LDO regulator, lithium battery charger |
| **Battery Connector** | 2-pin JST-SH / MX1.25 connector | For optional 3.7V rechargeable LiPo battery |
| **Enclosure** | 3D Printed Desk Stand | 35°–45° ergonomic desk viewing angle |

---

## 2. Complete GPIO Pinout Table

| GPIO Pin | Net Name | Target Subsystem | Direction | Voltage | Protocol / Electrical Notes |
|---|---|---|---|---|---|
| **GPIO 1** | `BAT_ADC_PIN` | Power Management | Input | 0–3.3V | Analog ADC channel connected to internal battery voltage divider |
| **GPIO 4** | `LCD_DC` | ST7789V2 Display | Output | 3.3V | Data/Command mode selection line |
| **GPIO 5** | `LCD_CS` | ST7789V2 Display | Output | 3.3V | SPI Chip Select (Active Low) |
| **GPIO 6** | `LCD_SCK` | ST7789V2 Display | Output | 3.3V | SPI Clock line (up to 80 MHz) |
| **GPIO 7** | `LCD_MOSI` | ST7789V2 Display | Output | 3.3V | SPI Master-Out-Slave-In data line |
| **GPIO 8** | `LCD_RST` | ST7789V2 Display | Output | 3.3V | Hardware LCD Reset (Active Low) |
| **GPIO 10** | `IIC_SCL` | CST816T Touch + QMI8658 IMU | Output | 3.3V | Shared I2C Clock (100 kHz standard mode) |
| **GPIO 11** | `IIC_SDA` | CST816T Touch + QMI8658 IMU | In/Out | 3.3V | Shared I2C Bidirectional Data (Internal pull-up) |
| **GPIO 13** | `TP_RST` | CST816T Touch | Output | 3.3V | Hardware Touch Reset (Active Low) |
| **GPIO 14** | `TP_INT` | CST816T Touch | Input | 3.3V | Touch Interrupt line (Active Low, falling-edge) |
| **GPIO 15** | `LCD_BL` | Display Backlight | Output | 3.3V | LEDC Backlight PWM (Channel 7, 5 kHz, 8-bit resolution) |
| **GPIO 19** | `USB_D-` | USB OTG | In/Out | 3.3V | Native USB 2.0 Full-Speed Data Minus line |
| **GPIO 20** | `USB_D+` | USB OTG | In/Out | 3.3V | Native USB 2.0 Full-Speed Data Plus line |
| **GPIO 42** | `BUZZER_PIN` | Haptics & Audio | Output | 3.3V | Piezoelectric buzzer drive pin (2.4 kHz PWM pulse) |
| **3V3** | `3V3` | Power Rail | Power | 3.3V | Regulated 3.3V logic supply rail |
| **GND** | `GND` | Power Rail | Power | 0.0V | Common circuit ground |

---

## 3. Display Controller (ST7789V2) Configuration

- **Physical Resolution**: 240 horizontal pixels × 280 vertical pixels.
- **Color Format**: RGB565 (16 bits per pixel: 5 bits Red, 6 bits Green, 5 bits Blue).
- **Coordinate Offsets**:
  The ST7789V2 driver has an internal 240×320 memory matrix. To center the 240×280 physical panel, memory addresses are offset:
  - Column Offset: `0`
  - Row Offset: `20`
  - Active Window: X `[0..239]`, Y `[20..299]`
- **Backlight Control (LEDC)**:
  - Timer: 8-bit resolution (`0` to `255`).
  - Frequency: 5 kHz (eliminates audible PWM whine).
  - Pin: GPIO 15.
  - Safe Range: Clamped between 10% duty cycle (minimum visibility) and 100% duty cycle.

---

## 4. Capacitive Touch Controller (CST816T) Configuration

- **I2C Slave Address**: `0x15` (7-bit address).
- **Register Map**:
  | Address | Register Name | Description |
  |---|---|---|
  | `0x01` | `REG_GESTURE_ID` | Latched gesture ID (`0x01` Up, `0x02` Down, `0x03` Left, `0x04` Right, `0x05` Click). *Note: Ignored by firmware to prevent latching bugs.* |
  | `0x02` | `REG_FINGER_NUM` | Active finger count (`0x00` = released, `0x01` = 1 finger pressed). |
  | `0x03` | `REG_XPOS_H` | Touch X-coordinate high 4 bits. |
  | `0x04` | `REG_XPOS_L` | Touch X-coordinate low 8 bits. |
  | `0x05` | `REG_YPOS_H` | Touch Y-coordinate high 4 bits. |
  | `0x06` | `REG_YPOS_L` | Touch Y-coordinate low 8 bits. |
  | `0xA7` | `REG_CHIP_ID` | Chip identification byte (returns `0xB4` or `0xB5`). |
  | `0xFA` | `REG_IRQ_CTL` | Interrupt control register (`0x40` = continuous touch notification mode). |
  | `0xFE` | `REG_DIS_AUTOSLEEP` | Auto-sleep suppression (`0xFF` = permanently awake). |

---

## 5. Inertial Measurement Unit (QMI8658) Configuration

The onboard QMI8658 6-axis IMU shares the touch controller's I2C bus (`IIC_SDA` = GPIO 11, `IIC_SCL` = GPIO 10, 100 kHz). Only the accelerometer is used; it drives the Settings Deck's **Auto-Rotate** feature (NVS `settings:auto_rotate`).

- **I2C Slave Address**: `0x6B` primary, `0x6A` fallback (SA0 strap). The driver probes both at boot; if neither answers `WHO_AM_I == 0x05`, auto-rotate degrades to "IMU not detected" and the panel stays in portrait.
- **Register Map (as used by firmware)**:
  | Address | Register Name | Firmware Configuration |
  |---|---|---|
  | `0x00` | `WHO_AM_I` | Identification byte, must read `0x05`. |
  | `0x02` | `CTRL1` | `0x60` — address auto-increment enabled for multi-byte burst reads. |
  | `0x03` | `CTRL2` | `0x10` — accelerometer ±4g full scale, 50 Hz output data rate. |
  | `0x08` | `CTRL7` | `0x01` — `aEN=1`, accelerometer enabled (gyroscope stays off). |
  | `0x35`–`0x3A` | `AX_L`..`AZ_H` | Accelerometer output, three little-endian signed 16-bit words (one 6-byte burst read). |
- **Scale**: ±4g full scale → 1g ≈ 8192 LSB.
- **Orientation Logic** (`src/qmi8658.cpp`, modeled in `tests/test_orientation.py`):
  - **Classification**: gravity projected onto the panel's long axis decides the orientation — `Ay ≥ +0.5g` (4096 LSB) with `|Ay| > |Ax|` → orientation `0` (portrait, USB down); `Ay ≤ −0.5g` → orientation `2` (inverted portrait, USB up). The `|Ay| > |Ax|` dominance guard keeps sideways tilts from flipping the UI.
  - **Flat-table suppression**: when `|Az| > 0.8g` (≈6553 LSB) and `|Ax|`, `|Ay|` are inside a 0.35g deadband, the device is lying on the desk — the current orientation is held to prevent jitter.
  - **Debounce**: a candidate orientation must persist for ≥ 300 ms (polled every 100 ms from the main loop) before the display, touch remap, and LVGL are rotated.

---

## 6. Electrical & Thermal Characteristics

- **Operating Voltage**: 5.0 V via USB-C (regulated to 3.3V on-board).
- **Power Consumption Profile**:
  | Mode | Condition | Current Draw (@ 5V) | Power |
  |---|---|---|---|
  | **Full Active** | Display 100%, 240 MHz dual-core, USB streaming | ~115 mA | 0.575 W |
  | **Typical Desk** | Display 80%, 1 Hz telemetry | ~95 mA | 0.475 W |
  | **Standby** | Display 20%, link standby mode | ~45 mA | 0.225 W |
- **Thermal Behavior**: The board generates minimal heat (~32°C steady-state surface temperature at 22°C ambient). Safe for enclosed PLA, PETG, or resin 3D-printed enclosures without active cooling.

---

## 7. Mechanical Dimensions & Mounting

- **PCB Outer Dimensions**: 40.0 mm × 35.0 mm.
- **Display Window**: Centered 1.69" diagonal rectangle with 4-corner rounded bezels.
- **Mounting Holes**: 4 × M2 screw mounting holes located at PCB corners.
- **Enclosure Guidelines**:
  - Angle: 35°–45° tilt angle from desk surface for optimal touch ergonomics and anti-glare viewing.
  - Cutouts: USB-C port cutout (minimum 11mm × 6mm clearance for cable molding), reset/boot button access, and buzzer acoustic venting.
