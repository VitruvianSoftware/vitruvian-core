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

/**
 * Tests for useTheme hook
 *
 * Tests theme state management, storage persistence, and theme cycling.
 */

import { renderHook, act } from "@testing-library/react";
import { useTheme } from "./useTheme";

// Mock Chrome API
const mockChrome = {
  storage: {
    local: {
      get: jest.fn(),
      set: jest.fn(),
    },
  },
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = mockChrome;

// Mock document.documentElement.setAttribute
const mockSetAttribute = jest.fn();
Object.defineProperty(document, "documentElement", {
  value: {
    setAttribute: mockSetAttribute,
  },
  writable: true,
});

// Mock window.matchMedia
const mockMatchMedia = jest.fn();
Object.defineProperty(window, "matchMedia", {
  value: mockMatchMedia,
  writable: true,
});

describe("useTheme", () => {
  beforeEach(() => {
    jest.clearAllMocks();

    // Default: no stored theme
    mockChrome.storage.local.get.mockImplementation((_keys, callback) => {
      callback({});
    });

    // Default: light mode system preference
    mockMatchMedia.mockReturnValue({ matches: false });
  });

  describe("initial state", () => {
    it("should default to system theme", () => {
      const { result } = renderHook(() => useTheme());

      expect(result.current.theme).toBe("system");
    });

    it("should load theme from storage on mount", () => {
      mockChrome.storage.local.get.mockImplementation((_keys, callback) => {
        callback({ "tabula-theme": "dark" });
      });

      const { result } = renderHook(() => useTheme());

      // After the effect runs, theme should be loaded
      expect(result.current.theme).toBe("dark");
    });

    it("should ignore invalid stored theme values", () => {
      mockChrome.storage.local.get.mockImplementation((_keys, callback) => {
        callback({ "tabula-theme": "invalid-theme" });
      });

      const { result } = renderHook(() => useTheme());

      // Should remain at default
      expect(result.current.theme).toBe("system");
    });
  });

  describe("setTheme", () => {
    it("should update theme state", () => {
      const { result } = renderHook(() => useTheme());

      act(() => {
        result.current.setTheme("dark");
      });

      expect(result.current.theme).toBe("dark");
    });

    it("should persist theme to storage", () => {
      const { result } = renderHook(() => useTheme());

      act(() => {
        result.current.setTheme("light");
      });

      expect(mockChrome.storage.local.set).toHaveBeenCalledWith({
        "tabula-theme": "light",
      });
    });

    it("should apply theme to document", () => {
      const { result } = renderHook(() => useTheme());

      act(() => {
        result.current.setTheme("dark");
      });

      expect(mockSetAttribute).toHaveBeenCalledWith("data-theme", "dark");
    });
  });

  describe("cycleTheme", () => {
    it("should cycle from system to light", () => {
      const { result } = renderHook(() => useTheme());

      expect(result.current.theme).toBe("system");

      act(() => {
        result.current.cycleTheme();
      });

      expect(result.current.theme).toBe("light");
    });

    it("should cycle from light to dark", () => {
      const { result } = renderHook(() => useTheme());

      act(() => {
        result.current.setTheme("light");
      });
      expect(result.current.theme).toBe("light");

      act(() => {
        result.current.cycleTheme();
      });

      expect(result.current.theme).toBe("dark");
    });

    it("should cycle from dark to system", () => {
      const { result } = renderHook(() => useTheme());

      act(() => {
        result.current.setTheme("dark");
      });
      expect(result.current.theme).toBe("dark");

      act(() => {
        result.current.cycleTheme();
      });

      expect(result.current.theme).toBe("system");
    });

    it("should complete full cycle", () => {
      const { result } = renderHook(() => useTheme());

      // Start at system
      expect(result.current.theme).toBe("system");

      // First cycle: system -> light
      act(() => {
        result.current.cycleTheme();
      });
      expect(result.current.theme).toBe("light");

      // Second cycle: light -> dark
      act(() => {
        result.current.cycleTheme();
      });
      expect(result.current.theme).toBe("dark");

      // Third cycle: dark -> system
      act(() => {
        result.current.cycleTheme();
      });
      expect(result.current.theme).toBe("system");
    });
  });

  describe("getEffectiveTheme", () => {
    it("should return light when system prefers light", () => {
      mockMatchMedia.mockReturnValue({ matches: false });

      const { result } = renderHook(() => useTheme());

      expect(result.current.getEffectiveTheme()).toBe("light");
    });

    it("should return dark when system prefers dark", () => {
      mockMatchMedia.mockReturnValue({ matches: true });

      const { result } = renderHook(() => useTheme());

      expect(result.current.getEffectiveTheme()).toBe("dark");
    });

    it("should return light when theme is explicitly light", () => {
      const { result } = renderHook(() => useTheme());

      act(() => {
        result.current.setTheme("light");
      });

      // System preference should be ignored
      mockMatchMedia.mockReturnValue({ matches: true });

      expect(result.current.getEffectiveTheme()).toBe("light");
    });

    it("should return dark when theme is explicitly dark", () => {
      const { result } = renderHook(() => useTheme());

      act(() => {
        result.current.setTheme("dark");
      });

      // System preference should be ignored
      mockMatchMedia.mockReturnValue({ matches: false });

      expect(result.current.getEffectiveTheme()).toBe("dark");
    });
  });

  describe("document theme application", () => {
    it("should apply theme attribute on mount", () => {
      renderHook(() => useTheme());

      expect(mockSetAttribute).toHaveBeenCalledWith("data-theme", "system");
    });

    it("should update document when theme changes", () => {
      const { result } = renderHook(() => useTheme());

      act(() => {
        result.current.setTheme("dark");
      });

      expect(mockSetAttribute).toHaveBeenCalledWith("data-theme", "dark");

      act(() => {
        result.current.setTheme("light");
      });

      expect(mockSetAttribute).toHaveBeenCalledWith("data-theme", "light");
    });
  });
});
