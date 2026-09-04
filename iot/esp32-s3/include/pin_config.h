#pragma once

// Display Pins (ST7789V2 SPI)
#define LCD_DC 4
#define LCD_CS 5
#define LCD_SCK 6
#define LCD_MOSI 7
#define LCD_RST 8
#define LCD_BL 15
#define LCD_WIDTH 240
#define LCD_HEIGHT 280

// Touch Pins (CST816T I2C)
#define IIC_SDA 11
#define IIC_SCL 10
#define TP_RST 13
#define TP_INT 14
#define CST816T_DEVICE_ADDRESS 0x15

// Optional Onboard Peripherals
#define BUZZER_PIN 42
#define BAT_ADC_PIN 1
