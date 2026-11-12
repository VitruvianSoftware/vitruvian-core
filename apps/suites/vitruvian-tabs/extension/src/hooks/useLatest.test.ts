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
 * Tests for useLatest hook
 */

import { renderHook } from "@testing-library/react";
import { useLatest } from "./useLatest";

describe("useLatest", () => {
  it("should return a ref with the initial value", () => {
    const { result } = renderHook(() => useLatest("initial"));

    expect(result.current.current).toBe("initial");
  });

  it("should update ref when value changes", () => {
    const { result, rerender } = renderHook(({ value }) => useLatest(value), {
      initialProps: { value: "first" },
    });

    expect(result.current.current).toBe("first");

    rerender({ value: "second" });

    expect(result.current.current).toBe("second");
  });

  it("should return the same ref object across renders", () => {
    const { result, rerender } = renderHook(({ value }) => useLatest(value), {
      initialProps: { value: 1 },
    });

    const firstRef = result.current;

    rerender({ value: 2 });

    const secondRef = result.current;

    // Same ref object, just updated value
    expect(firstRef).toBe(secondRef);
    expect(secondRef.current).toBe(2);
  });

  it("should work with complex objects", () => {
    const obj1 = { id: 1, name: "first" };
    const obj2 = { id: 2, name: "second" };

    const { result, rerender } = renderHook(({ value }) => useLatest(value), {
      initialProps: { value: obj1 },
    });

    expect(result.current.current).toBe(obj1);

    rerender({ value: obj2 });

    expect(result.current.current).toBe(obj2);
  });

  it("should work with null values", () => {
    const { result, rerender } = renderHook(({ value }) => useLatest(value), {
      initialProps: { value: null as string | null },
    });

    expect(result.current.current).toBe(null);

    rerender({ value: "not null" });

    expect(result.current.current).toBe("not null");
  });
});
