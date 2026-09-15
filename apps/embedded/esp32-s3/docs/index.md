# ESP32-S3 Mac Desktop Companion & Touch Controller

Custom firmware for the **Waveshare ESP32-S3-Touch-LCD-1.69** development board, turning it into a desk companion that streams live Mac hardware metrics and triggers native macOS desktop shortcuts via USB HID.

## Hardware Specifications
- **MCU**: ESP32-S3 Xtensa Dual-Core @ 240MHz (16MB Flash, 8MB PSRAM)
- **Display**: 1.69" 240x280 IPS ST7789V2 SPI LCD
- **Touch**: CST816T Capacitive Touch Screen (I2C)
- **USB**: Native USB OTG in composite mode (CDC Serial + HID Keyboard & Consumer Control)
- **Wireless**: 2.4 GHz 802.11 b/g/n Wi-Fi + Bluetooth 5 LE (NimBLE HID keyboard & consumer control)
- **Haptics/Audio**: Onboard buzzer (GPIO 42, LEDC PWM) for tactile clicks and CI pass/fail chimes

## Documentation Hub
- [User Guide & Operator Manual](user-guide.md): Physical hardware controls, battery & power management, tethered vs. untethered operations, Bluetooth pairing, Wi-Fi companion daemon setup, 4-way screen rotation, and troubleshooting.
- [System Architecture](architecture.md): Deep dive into the subsystems, composite USB OTG mode, graphics rendering pipeline, and dual-transport packet router.
- [Hardware & BOM](hardware.md): Bill of materials, complete GPIO pinout table, power circuitry, and enclosure guidelines.
- [Wire Protocol](protocol.md): Serial and UDP JSON packet structures, commands, and telemetry payloads.
- [Flashing Guide](flashing.md): PlatformIO, Bazel, and esptool flashing instructions, partition layout, and OTA updates.
