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

import {
  CLAUDE_MODES,
  DEFAULT_CLAUDE_MODE,
  isClaudeModeId,
  requiresDangerousSkipFlag,
  sdkPermissionOptionsForMode,
} from "../src/modes.js";

describe("modes", () => {
  test("defines the four Claude permission modes and default mode", () => {
    expect(DEFAULT_CLAUDE_MODE).toBe("default");
    expect(CLAUDE_MODES.map((m) => [m.id, m.name])).toEqual([
      ["default", "Ask before acting"],
      ["acceptEdits", "Auto-accept edits"],
      ["plan", "Plan"],
      ["auto", "Auto"],
      ["bypassPermissions", "Full access"],
    ]);
  });

  test("validates mode ids", () => {
    expect(isClaudeModeId("default")).toBe(true);
    expect(isClaudeModeId("acceptEdits")).toBe(true);
    expect(isClaudeModeId("plan")).toBe(true);
    expect(isClaudeModeId("bypassPermissions")).toBe(true);
    expect(isClaudeModeId("auto")).toBe(true);
    expect(isClaudeModeId("yolo")).toBe(false);
  });

  test("sets allowDangerouslySkipPermissions only for bypassPermissions", () => {
    expect(requiresDangerousSkipFlag("bypassPermissions")).toBe(true);
    expect(requiresDangerousSkipFlag("default")).toBe(false);
    expect(requiresDangerousSkipFlag("acceptEdits")).toBe(false);
    expect(requiresDangerousSkipFlag("plan")).toBe(false);

    expect(sdkPermissionOptionsForMode("default")).toEqual({
      permissionMode: "default",
    });
    expect(sdkPermissionOptionsForMode("acceptEdits")).toEqual({
      permissionMode: "acceptEdits",
    });
    expect(sdkPermissionOptionsForMode("plan")).toEqual({
      permissionMode: "plan",
    });
    // No Claude version gate, as in T3 Code's ClaudeAdapterV2.
    expect(requiresDangerousSkipFlag("auto")).toBe(false);
    expect(sdkPermissionOptionsForMode("auto")).toEqual({
      permissionMode: "auto",
    });
    expect(sdkPermissionOptionsForMode("bypassPermissions")).toEqual({
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
    });
  });
});
