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
 * Draw order of the weather imagery through the globe port: scalar context
 * (wind), infrared, radar, then lightning, independent of enable order, and
 * above the port's other layers (zOrder 0).
 */
/** What each product's imagery shows (the imagery's `shows`): both cloud products are clouds. */
export const WEATHER_IMAGERY_SHOWS = Object.freeze({
  wind: 'wind',
  clouds: 'clouds',
  'clouds-regional': 'clouds',
  radar: 'radar',
  lightning: 'lightning',
});

export const WEATHER_IMAGERY_Z = Object.freeze({
  wind: 1,
  clouds: 2,
  'clouds-regional': 2,
  radar: 3,
  lightning: 4,
});
