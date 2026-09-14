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

/** Decide whether a loaded aircraft participates in a proximity query.
 *
 * `modelRendering` is the OWNERSHIP question, not `model.show`: a model that
 * exists but is hidden, unplaced, or still loading is not what the operator sees,
 * and the billboard flag is what answers for the contact in those states. Reading
 * a bare `show` here counted a contact whose model had been admitted but was
 * drawing nothing. */
export function aircraftIncludedInNearby({
  isTracked = false,
  billboardShown = false,
  modelRendering = false,
  includeHidden = false,
} = {}) {
  return Boolean(includeHidden || isTracked || billboardShown || modelRendering);
}
