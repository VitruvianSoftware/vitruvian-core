/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import { ChromeStorageProvider } from "../../src/lib/flags/chrome-storage-provider";
import {
  initFeatureFlags,
  getFeatureFlagClient,
  FLAGS,
} from "../../src/lib/flags";
import {
  useFeatureFlag,
  setFeatureFlag,
} from "../../src/lib/flags/use-feature-flag";
import { renderHook, act } from "@testing-library/react";

const mockChromeStorage = {
  get: jest.fn(),
  set: jest.fn(),
};

const mockListeners: ((changes: any, areaName: string) => void)[] = [];
const mockChromeOnChanged = {
  addListener: jest.fn((cb) => mockListeners.push(cb)),
};

(global as any).chrome = {
  storage: {
    local: mockChromeStorage,
    onChanged: mockChromeOnChanged,
  },
};

describe("ChromeStorageProvider", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockListeners.length = 0;
    mockChromeStorage.get.mockResolvedValue({
      tabula_feature_flags: { "test-flag": true },
    });
  });

  it("initializes from chrome.storage", async () => {
    const provider = new ChromeStorageProvider();
    await provider.initialize();

    expect(mockChromeStorage.get).toHaveBeenCalledWith("tabula_feature_flags");
    expect(provider.resolveBooleanEvaluation("test-flag", false).value).toBe(
      true,
    );
    expect(provider.resolveBooleanEvaluation("unknown-flag", false).value).toBe(
      false,
    );
  });

  it("updates cache on storage change", async () => {
    const provider = new ChromeStorageProvider();
    await provider.initialize();

    // Simulate chrome.storage.onChanged
    const changes = {
      tabula_feature_flags: { newValue: { "test-flag": false } },
    };
    mockListeners.forEach((cb) => cb(changes, "local"));

    expect(provider.resolveBooleanEvaluation("test-flag", true).value).toBe(
      false,
    );
  });

  it("falls back when chrome.storage is unavailable", async () => {
    const originalChrome = (global as any).chrome;
    (global as any).chrome = undefined;

    const provider = new ChromeStorageProvider();
    await provider.initialize(); // Should not throw

    expect(provider.resolveBooleanEvaluation("test-flag", false).value).toBe(
      false,
    );
    expect(provider.resolveBooleanEvaluation("test-flag", false).reason).toBe(
      "DEFAULT",
    );

    (global as any).chrome = originalChrome;
  });
});

describe("Feature Flags Integration", () => {
  beforeEach(async () => {
    jest.clearAllMocks();
    mockListeners.length = 0;
    mockChromeStorage.get.mockResolvedValue({});
    await initFeatureFlags();
  });

  it("useFeatureFlag hook responds to changes", async () => {
    const { result } = renderHook(() => useFeatureFlag("react-flag", false));
    expect(result.current).toBe(false);

    // Simulate change
    act(() => {
      const changes = {
        tabula_feature_flags: { newValue: { "react-flag": true } },
      };
      mockListeners.forEach((cb) => cb(changes, "local"));
    });

    expect(result.current).toBe(true);
  });

  it("setFeatureFlag updates storage", async () => {
    mockChromeStorage.get.mockResolvedValue({});
    await setFeatureFlag("test-set", true);
    expect(mockChromeStorage.set).toHaveBeenCalledWith({
      tabula_feature_flags: { "test-set": true },
    });
  });
});
