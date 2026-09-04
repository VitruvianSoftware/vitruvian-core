#include "touch_cst816t.h"
#include "pin_config.h"
#include <Wire.h>

#define CST816T_ADDRESS   0x15
#define REG_GESTURE_ID    0x01
#define REG_FINGER_NUM    0x02
#define REG_XPOS_H        0x03
#define REG_XPOS_L        0x04
#define REG_YPOS_H        0x05
#define REG_YPOS_L        0x06
#define REG_CHIP_ID       0xA7
#define REG_IRQ_CTL       0xFA
#define REG_MOTION_MASK   0xEC
#define REG_DIS_AUTOSLEEP 0xFE

static uint8_t chip_id = 0;
static volatile bool tp_irq_fired = false;

static void IRAM_ATTR touch_isr() {
    tp_irq_fired = true;
}

static uint8_t i2c_read_reg(uint8_t reg, uint8_t *data, size_t len) {
    Wire.beginTransmission(CST816T_ADDRESS);
    Wire.write(reg);
    if (Wire.endTransmission(true) != 0) return 1;
    if (Wire.requestFrom((uint8_t)CST816T_ADDRESS, len, (bool)true) != len) return 2;
    for (size_t i = 0; i < len; i++) {
        data[i] = Wire.read();
    }
    return 0;
}

static uint8_t i2c_write_reg(uint8_t reg, uint8_t val) {
    Wire.beginTransmission(CST816T_ADDRESS);
    Wire.write(reg);
    Wire.write(val);
    return Wire.endTransmission(true);
}

bool touch_init() {
    // 1. Hardware Reset sequence
    pinMode(TP_RST, OUTPUT);
    digitalWrite(TP_RST, HIGH);
    delay(50);
    digitalWrite(TP_RST, LOW);
    delay(20);
    digitalWrite(TP_RST, HIGH);
    delay(100);

    // 2. Configure I2C bus at 100kHz standard speed with pullups
    pinMode(IIC_SDA, INPUT_PULLUP);
    pinMode(IIC_SCL, INPUT_PULLUP);
    pinMode(TP_INT, INPUT_PULLUP);
    Wire.begin(IIC_SDA, IIC_SCL, 100000);

    // 3. Attach interrupt on TP_INT falling edge
    attachInterrupt(digitalPinToInterrupt(TP_INT), touch_isr, FALLING);

    // 4. Read Chip ID
    uint8_t dta[4] = {0};
    if (i2c_read_reg(REG_CHIP_ID, dta, 4) == 0) {
        chip_id = dta[0];
        Serial.printf("CST816T Detected! Chip ID: 0x%02X, FW: 0x%02X\n", chip_id, dta[3]);
    } else {
        Serial.println("CST816T read ID failed!");
    }

    // 5. CRITICAL: Configure IRQ mode to continuous touch notifications (0x40 = TOUCH periodic mode)
    i2c_write_reg(REG_IRQ_CTL, 0x40);

    // 6. CRITICAL: Disable Auto-Sleep (0xFE = 0xFF) so touch core stays awake
    i2c_write_reg(REG_DIS_AUTOSLEEP, 0xFF);

    return true;
}

uint8_t touch_get_chip_id() {
    return chip_id;
}

bool touch_read(uint16_t *x, uint16_t *y) {
    uint8_t dta[6] = {0};
    if (i2c_read_reg(REG_GESTURE_ID, dta, 6) != 0) {
        return false;
    }

    // dta[] maps to registers 0x01..0x06:
    //   [0]=GestureID [1]=FingerNum [2]=XposH [3]=XposL [4]=YposH [5]=YposL
    //
    // Gate on FingerNum ONLY -- this is what the vendor drivers
    // (esp_lcd_touch_cst816s / SensorLib TouchDrvCST816) do.
    //
    // GestureID (0x01) latches the last gesture and is NOT cleared on release,
    // so treating it as "pressed" leaves LVGL stuck in a permanent press at
    // stale coordinates after the first swipe.
    uint8_t fingers = dta[1];

    // Some CST816T parts report 0xFF for every register once auto-sleep has
    // been disabled (we write 0xFE=0xFF in touch_init). Treat that as "no touch"
    // rather than as 255 fingers.
    if (fingers == 0x00 || fingers == 0xFF) {
        return false;
    }

    fingers &= 0x0F;
    if (fingers == 0) {
        return false;
    }

    uint16_t raw_x = (((uint16_t)dta[2] & 0x0F) << 8) | (uint16_t)dta[3];
    uint16_t raw_y = (((uint16_t)dta[4] & 0x0F) << 8) | (uint16_t)dta[5];

    if (raw_x >= LCD_WIDTH || raw_y >= LCD_HEIGHT) {
        return false;
    }

    *x = raw_x;
    *y = raw_y;
    return true;
}
