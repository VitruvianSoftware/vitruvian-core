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

#include <iostream>
#include <cassert>
#include <cstring>
#include <vector>
#include <string>
#include <ArduinoJson.h>

// Mirror exact structs from ui.h and helper functions from main.cpp
struct DynamicButtonConfig {
    char label[32];
    uint32_t color;
    uint8_t mod;
    uint8_t key;
    uint16_t cons;
};

static uint32_t parse_color_hex(const char* str, uint32_t default_color = 0x0A84FF) {
    if (!str || strlen(str) == 0) return default_color;
    if (str[0] == '#') {
        return (uint32_t)strtoul(str + 1, NULL, 16);
    } else if (strncmp(str, "0x", 2) == 0 || strncmp(str, "0X", 2) == 0) {
        return (uint32_t)strtoul(str + 2, NULL, 16);
    }
    return (uint32_t)strtoul(str, NULL, 16);
}

static uint32_t extract_color(JsonVariant v, uint32_t default_color = 0x0A84FF) {
    if (v.is<uint32_t>()) {
        return v.as<uint32_t>();
    } else if (v.is<const char*>()) {
        return parse_color_hex(v.as<const char*>(), default_color);
    }
    return default_color;
}

// Function simulating the exact deserialization logic from main.cpp loop()
struct ParseResult {
    bool success;
    std::string error;
    std::string type;
    std::string app_name;
    uint32_t app_color;
    int button_count;
    DynamicButtonConfig btns[6];
};

ParseResult parse_incoming_json(const std::string& line) {
    ParseResult res;
    res.success = false;
    res.button_count = 0;

    if (line.length() == 0 || !line.starts_with("{") || !line.ends_with("}")) {
        res.error = "Pre-filter rejection: missing braces";
        return res;
    }

    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, line);
    if (err) {
        res.error = std::string("Deserialization error: ") + err.c_str();
        return res;
    }

    const char* type = doc["type"] | "";
    res.type = (type != nullptr) ? type : "";

    if (strcmp(type, "stats") == 0 || (strlen(type) == 0 && !doc["cpu"].isNull())) {
        res.success = true;
        res.app_name = "stats";
        return res;
    }
    else if (strcmp(type, "app") == 0) {
        const char* app_name = doc["app"] | doc["name"] | "Default";
        res.app_name = (app_name != nullptr) ? app_name : "";

        uint32_t app_color = extract_color(doc["color"], 0x0A84FF);
        res.app_color = app_color;

        JsonArray btn_arr = doc["buttons"].as<JsonArray>();
        int count = 0;

        for (JsonObject b : btn_arr) {
            if (count >= 6) break;
            const char* lbl = b["label"] | "";
            if (lbl == nullptr) {
                // Potential null pointer dereference bug!
                res.error = "NULL_LBL_POINTER";
                lbl = "";
            }
            strncpy(res.btns[count].label, lbl, sizeof(res.btns[count].label) - 1);
            res.btns[count].label[sizeof(res.btns[count].label) - 1] = '\0';

            res.btns[count].mod   = b["mod"] | 0;
            res.btns[count].key   = b["key"] | 0;
            res.btns[count].cons  = b["cons"] | 0;
            res.btns[count].color = extract_color(b["color"], app_color);
            count++;
        }

        for (int i = count; i < 6; i++) {
            snprintf(res.btns[i].label, sizeof(res.btns[i].label), "-");
            res.btns[i].mod   = 0;
            res.btns[i].key   = 0;
            res.btns[i].cons  = 0;
            res.btns[i].color = 0x2C2C2E;
        }

        res.button_count = count;
        res.success = true;
        return res;
    }

    res.error = "Unhandled packet type";
    return res;
}

int main() {
    std::cout << "Starting ArduinoJson Empirical Stress Harness..." << std::endl;

    // Test 1: Canonical payload
    {
        std::string json = "{\"type\":\"app\",\"app\":\"VS Code\",\"color\":\"0x007ACC\",\"buttons\":[{\"label\":\"Pal\",\"mod\":10,\"key\":112,\"cons\":0,\"color\":\"0x007ACC\"}]}";
        ParseResult r = parse_incoming_json(json);
        assert(r.success);
        assert(r.app_name == "VS Code");
        assert(r.app_color == 0x007ACC);
        assert(r.button_count == 1);
        assert(std::string(r.btns[0].label) == "Pal");
        assert(r.btns[0].mod == 10);
        assert(r.btns[0].key == 112);
        std::cout << "  [PASS] Test 1: Canonical payload" << std::endl;
    }

    // Test 2: Color extraction formats (#RRGGBB, 0xRRGGBB, integer, invalid, null)
    {
        JsonDocument doc;
        deserializeJson(doc, "{\"c1\":\"#FF0000\",\"c2\":\"0x00FF00\",\"c3\":255,\"c4\":\"invalid\",\"c5\":null,\"c6\":true}");
        assert(extract_color(doc["c1"]) == 0xFF0000);
        assert(extract_color(doc["c2"]) == 0x00FF00);
        assert(extract_color(doc["c3"]) == 255);
        assert(extract_color(doc["c4"], 0x123456) == 0); // strtoul("invalid") returns 0
        assert(extract_color(doc["c5"], 0x123456) == 0x123456); // null falls back to default
        assert(extract_color(doc["c6"], 0x123456) == 0x123456); // bool falls back to default
        std::cout << "  [PASS] Test 2: Color extraction formats" << std::endl;
    }

    // Test 3: Null pointer safety in buttons array
    {
        std::string json = "{\"type\":\"app\",\"app\":\"NullTest\",\"buttons\":[{\"label\":null,\"mod\":null,\"key\":null,\"cons\":null,\"color\":null}]}";
        ParseResult r = parse_incoming_json(json);
        assert(r.success);
        assert(r.button_count == 1);
        assert(std::string(r.btns[0].label) == "");
        assert(r.btns[0].mod == 0);
        assert(r.btns[0].key == 0);
        assert(r.btns[0].cons == 0);
        std::cout << "  [PASS] Test 3: Null pointer safety in button fields" << std::endl;
    }

    // Test 4: Invalid types in button fields (int label, string mod, dict key)
    {
        std::string json = "{\"type\":\"app\",\"buttons\":[{\"label\":12345,\"mod\":\"invalid\",\"key\":[1,2],\"cons\":{}}]}";
        ParseResult r = parse_incoming_json(json);
        assert(r.success);
        assert(r.button_count == 1);
        // ArduinoJson v7: b["label"] | "" where b["label"] is int: returns ""
        assert(std::string(r.btns[0].label) == "");
        assert(r.btns[0].mod == 0);
        assert(r.btns[0].key == 0);
        assert(r.btns[0].cons == 0);
        std::cout << "  [PASS] Test 4: Type confusion in button fields" << std::endl;
    }

    // Test 5: Buttons array is not an array (null, integer, string)
    {
        std::string json_null_btns = "{\"type\":\"app\",\"buttons\":null}";
        ParseResult r1 = parse_incoming_json(json_null_btns);
        assert(r1.success);
        assert(r1.button_count == 0);
        assert(std::string(r1.btns[0].label) == "-");

        std::string json_int_btns = "{\"type\":\"app\",\"buttons\":999}";
        ParseResult r2 = parse_incoming_json(json_int_btns);
        assert(r2.success);
        assert(r2.button_count == 0);

        std::cout << "  [PASS] Test 5: Non-array buttons attribute" << std::endl;
    }

    // Test 6: Button array overflow (100 buttons provided)
    {
        std::string json = "{\"type\":\"app\",\"buttons\":[";
        for (int i = 0; i < 100; i++) {
            if (i > 0) json += ",";
            json += "{\"label\":\"B" + std::to_string(i) + "\",\"mod\":0,\"key\":" + std::to_string(i) + "}";
        }
        json += "]}";
        ParseResult r = parse_incoming_json(json);
        assert(r.success);
        assert(r.button_count == 6); // Hard-capped at 6
        assert(std::string(r.btns[0].label) == "B0");
        assert(std::string(r.btns[5].label) == "B5");
        std::cout << "  [PASS] Test 6: Button array overflow guard (capped at 6)" << std::endl;
    }

    // Test 7: Truncation of extremely long labels (>31 characters)
    {
        std::string long_lbl(200, 'X');
        std::string json = "{\"type\":\"app\",\"buttons\":[{\"label\":\"" + long_lbl + "\"}]}";
        ParseResult r = parse_incoming_json(json);
        assert(r.success);
        assert(strlen(r.btns[0].label) == 31); // 31 chars max + null
        assert(r.btns[0].label[31] == '\0');
        assert(r.btns[0].label[0] == 'X');
        std::cout << "  [PASS] Test 7: Label buffer overflow protection (31-char cap)" << std::endl;
    }

    // Test 8: ArduinoJson memory capacity stress (8KB payload)
    {
        std::string huge_json = "{\"type\":\"app\",\"app\":\"HugePayload\",\"metadata\":\"";
        huge_json.append(7000, 'A');
        huge_json += "\",\"buttons\":[{\"label\":\"Save\",\"mod\":8,\"key\":115}]}";
        ParseResult r = parse_incoming_json(huge_json);
        assert(r.success);
        assert(r.app_name == "HugePayload");
        assert(r.button_count == 1);
        assert(std::string(r.btns[0].label) == "Save");
        std::cout << "  [PASS] Test 8: Large payload buffer scaling (8KB JsonDocument)" << std::endl;
    }

    // Test 9: Malformed JSON syntax error recovery
    {
        ParseResult r1 = parse_incoming_json("{\"type\":\"app\", broken}");
        assert(!r1.success);
        assert(r1.error.find("Deserialization error") != std::string::npos);

        ParseResult r2 = parse_incoming_json("not a json");
        assert(!r2.success);
        assert(r2.error.find("Pre-filter rejection") != std::string::npos);
        std::cout << "  [PASS] Test 9: Syntax error detection & rejection" << std::endl;
    }

    std::cout << "\nAll 9 ArduinoJson empirical stress tests PASSED successfully!\n" << std::endl;
    return 0;
}
