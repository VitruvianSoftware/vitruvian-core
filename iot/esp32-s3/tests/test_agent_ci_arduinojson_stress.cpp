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
#include <string>
#include <vector>
#include <ArduinoJson.h>

// Mirror exact structs from ui.h
enum AgentState {
    AGENT_STATE_IDLE = 0,
    AGENT_STATE_RUNNING,
    AGENT_STATE_REVIEW,
    AGENT_STATE_ERROR
};

enum CIStatus {
    CI_STATUS_UNKNOWN = 0,
    CI_STATUS_PASSING,
    CI_STATUS_FAILING,
    CI_STATUS_PENDING,
    CI_STATUS_NONE
};

struct AgentCIConfig {
    char agent_name[32];
    AgentState agent_state;
    char agent_task[64];
    int active_agents;

    char repo[32];
    char branch[48];
    CIStatus ci_status;
    int pr_number;
    int checks_passed;
    int checks_total;
    bool is_dirty;
    int dirty_files;
};

struct DeserializationResult {
    bool success;
    std::string error;
    std::string type;
    AgentCIConfig config;
};

// Mirror exact deserialization logic from main.cpp
DeserializationResult deserialize_agent_ci_packet(const std::string& line) {
    DeserializationResult res;
    res.success = false;
    memset(&res.config, 0, sizeof(res.config));

    if (line.empty() || line.front() != '{' || line.back() != '}') {
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
    res.type = type;

    if (strcmp(type, "agent_ci") == 0) {
        res.success = true;

        // Parse Agent Sub-Object
        JsonObject agent = doc["agent"];
        if (!agent.isNull()) {
            const char* a_name = agent["name"] | "Agent";
            strncpy(res.config.agent_name, a_name, sizeof(res.config.agent_name) - 1);
            res.config.agent_name[sizeof(res.config.agent_name) - 1] = '\0';

            const char* a_state = agent["state"] | "idle";
            if (strcasecmp(a_state, "running") == 0) {
                res.config.agent_state = AGENT_STATE_RUNNING;
            } else if (strcasecmp(a_state, "review") == 0) {
                res.config.agent_state = AGENT_STATE_REVIEW;
            } else if (strcasecmp(a_state, "error") == 0) {
                res.config.agent_state = AGENT_STATE_ERROR;
            } else {
                res.config.agent_state = AGENT_STATE_IDLE;
            }

            const char* a_task = agent["task"] | agent["detail"] | "Idle";
            strncpy(res.config.agent_task, a_task, sizeof(res.config.agent_task) - 1);
            res.config.agent_task[sizeof(res.config.agent_task) - 1] = '\0';

            res.config.active_agents = agent["active_agents"] | (res.config.agent_state == AGENT_STATE_RUNNING ? 1 : 0);
        } else {
            strncpy(res.config.agent_name, "Agent", sizeof(res.config.agent_name) - 1);
            res.config.agent_state = AGENT_STATE_IDLE;
            strncpy(res.config.agent_task, "No data", sizeof(res.config.agent_task) - 1);
        }

        // Parse CI Sub-Object
        JsonObject ci = doc["ci"];
        if (!ci.isNull()) {
            const char* c_repo = ci["repo"] | "repo";
            strncpy(res.config.repo, c_repo, sizeof(res.config.repo) - 1);
            res.config.repo[sizeof(res.config.repo) - 1] = '\0';

            const char* c_branch = ci["branch"] | "main";
            strncpy(res.config.branch, c_branch, sizeof(res.config.branch) - 1);
            res.config.branch[sizeof(res.config.branch) - 1] = '\0';

            const char* c_status = ci["status"] | ci["state"] | "unknown";
            if (strcasecmp(c_status, "passing") == 0 || strcasecmp(c_status, "success") == 0) {
                res.config.ci_status = CI_STATUS_PASSING;
            } else if (strcasecmp(c_status, "failing") == 0 || strcasecmp(c_status, "failure") == 0) {
                res.config.ci_status = CI_STATUS_FAILING;
            } else if (strcasecmp(c_status, "pending") == 0 || strcasecmp(c_status, "in_progress") == 0) {
                res.config.ci_status = CI_STATUS_PENDING;
            } else if (strcasecmp(c_status, "none") == 0) {
                res.config.ci_status = CI_STATUS_NONE;
            } else {
                res.config.ci_status = CI_STATUS_UNKNOWN;
            }

            res.config.pr_number = ci["pr"] | 0;
            res.config.checks_passed = ci["passed"] | 0;
            res.config.checks_total = ci["total"] | 0;
            res.config.is_dirty = ci["dirty"] | false;
            res.config.dirty_files = ci["dirty_files"] | 0;
        } else {
            strncpy(res.config.repo, "-", sizeof(res.config.repo) - 1);
            strncpy(res.config.branch, "-", sizeof(res.config.branch) - 1);
            res.config.ci_status = CI_STATUS_UNKNOWN;
        }
    }

    return res;
}

int main() {
    std::cout << "Starting ArduinoJson Agent/CI Empirical Stress Harness...\n";

    // Test 1: Canonical payload
    {
        std::string json = "{\"type\":\"agent_ci\",\"agent\":{\"name\":\"Antigravity\",\"state\":\"running\",\"task\":\"Orchestrating M3\",\"active_agents\":2},\"ci\":{\"repo\":\"vitruvian-core\",\"branch\":\"feat/agent-ci\",\"dirty\":true,\"dirty_files\":3,\"status\":\"passing\",\"pr\":42,\"passed\":12,\"total\":12}}";
        DeserializationResult r = deserialize_agent_ci_packet(json);
        assert(r.success);
        assert(strcmp(r.config.agent_name, "Antigravity") == 0);
        assert(r.config.agent_state == AGENT_STATE_RUNNING);
        assert(strcmp(r.config.agent_task, "Orchestrating M3") == 0);
        assert(r.config.active_agents == 2);
        assert(strcmp(r.config.repo, "vitruvian-core") == 0);
        assert(strcmp(r.config.branch, "feat/agent-ci") == 0);
        assert(r.config.ci_status == CI_STATUS_PASSING);
        assert(r.config.pr_number == 42);
        assert(r.config.checks_passed == 12);
        assert(r.config.checks_total == 12);
        assert(r.config.is_dirty == true);
        assert(r.config.dirty_files == 3);
        std::cout << "  [PASS] Test 1: Canonical payload deserialization\n";
    }

    // Test 2: Massive string buffer safety (10,000 character strings)
    {
        std::string big_task(10000, 'X');
        std::string big_branch(5000, 'B');
        std::string big_name(2000, 'N');
        std::string json = "{\"type\":\"agent_ci\",\"agent\":{\"name\":\"" + big_name + "\",\"task\":\"" + big_task + "\"},\"ci\":{\"branch\":\"" + big_branch + "\"}}";
        DeserializationResult r = deserialize_agent_ci_packet(json);
        assert(r.success);
        assert(strlen(r.config.agent_name) == sizeof(r.config.agent_name) - 1);
        assert(strlen(r.config.agent_task) == sizeof(r.config.agent_task) - 1);
        assert(strlen(r.config.branch) == sizeof(r.config.branch) - 1);
        std::cout << "  [PASS] Test 2: Bounded buffer safety against 10KB string overflow\n";
    }

    // Test 3: Null sub-objects
    {
        std::string json = "{\"type\":\"agent_ci\",\"agent\":null,\"ci\":null}";
        DeserializationResult r = deserialize_agent_ci_packet(json);
        assert(r.success);
        assert(strcmp(r.config.agent_name, "Agent") == 0);
        assert(r.config.agent_state == AGENT_STATE_IDLE);
        assert(strcmp(r.config.agent_task, "No data") == 0);
        assert(strcmp(r.config.branch, "-") == 0);
        assert(r.config.ci_status == CI_STATUS_UNKNOWN);
        std::cout << "  [PASS] Test 3: Null sub-objects safe defaults\n";
    }

    // Test 4: Case-insensitivity and aliases
    {
        std::string json = "{\"type\":\"agent_ci\",\"agent\":{\"state\":\"ReViEw\",\"detail\":\"Code review in progress\"},\"ci\":{\"state\":\"In_PrOgReSs\"}}";
        DeserializationResult r = deserialize_agent_ci_packet(json);
        assert(r.success);
        assert(r.config.agent_state == AGENT_STATE_REVIEW);
        assert(strcmp(r.config.agent_task, "Code review in progress") == 0);
        assert(r.config.ci_status == CI_STATUS_PENDING);
        std::cout << "  [PASS] Test 4: Case-insensitive enums and field aliases\n";
    }

    // Test 5: Unicode and emoji strings
    {
        std::string json = "{\"type\":\"agent_ci\",\"agent\":{\"name\":\"🤖 AI Agent\",\"task\":\"Building 🚀 feature\"},\"ci\":{\"branch\":\"feat/🔥-hotfix\"}}";
        DeserializationResult r = deserialize_agent_ci_packet(json);
        assert(r.success);
        assert(std::string(r.config.agent_name).find("AI Agent") != std::string::npos);
        assert(std::string(r.config.agent_task).find("feature") != std::string::npos);
        std::cout << "  [PASS] Test 5: Unicode and emoji string handling\n";
    }

    // Test 6: Extreme numbers
    {
        std::string json = "{\"type\":\"agent_ci\",\"agent\":{\"active_agents\":-5},\"ci\":{\"pr\":2147483647,\"passed\":-1,\"total\":1000000}}";
        DeserializationResult r = deserialize_agent_ci_packet(json);
        assert(r.success);
        assert(r.config.active_agents == -5);
        assert(r.config.pr_number == 2147483647);
        assert(r.config.checks_passed == -1);
        assert(r.config.checks_total == 1000000);
        std::cout << "  [PASS] Test 6: Extreme numbers handling\n";
    }

    // Test 7: Malformed JSON rejection
    {
        assert(!deserialize_agent_ci_packet("{bad json").success);
        assert(!deserialize_agent_ci_packet("").success);
        assert(!deserialize_agent_ci_packet("{\"type\":\"agent_ci\"").success);
        std::cout << "  [PASS] Test 7: Malformed JSON rejection\n";
    }

    std::cout << "\nAll 7 ArduinoJson Agent/CI empirical stress tests PASSED!\n";
    return 0;
}
