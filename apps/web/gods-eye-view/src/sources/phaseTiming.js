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

/** Optional development phase measurements; no provider payloads or credentials. */
export function phaseTiming(phase, start, detail = {}, scope = 'roads') {
  if (import.meta.env?.DEV)
    performance.measure(`${scope}:${phase}`, {
      start,
      end: performance.now(),
      detail,
    });
}

/** Bounded development evidence for one physical outline installation. */
export function createWorkTrace() {
  if (!import.meta.env?.DEV) return null;
  try {
    return {
      timeOrigin: performance.timeOrigin,
      slices: [],
      dropped: 0,
      probes: 0,
      samplerStart: null,
      samplerHeadAt: null,
      samplerStatus: null,
      rendererStatus: null,
      status: 'pending',
      completedAt: null,
    };
  } catch {
    return null;
  }
}

/** Never let optional diagnostic recording change an installation outcome. */
export function recordWorkSlice(trace, phase, start, end, detail) {
  if (!trace) return;
  try {
    if (trace.slices.length >= 16) {
      trace.dropped += 1;
      return;
    }
    trace.slices.push({
      phase,
      start,
      end: end ?? performance.now(),
      ...(detail === undefined ? {} : { detail }),
    });
  } catch {
    try {
      trace.dropped += 1;
    } catch {
      // Missing or incomplete evidence fails the measurement, not the product.
    }
  }
}
