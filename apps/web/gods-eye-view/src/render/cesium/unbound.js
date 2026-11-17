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
 * @module render/cesium/unbound
 * @description What to load, once, before handing the Cesium-free
 * layers a Cesium viewer with no renderer bound: the factories
 * that build a camera, credits, effects, draw, frame, globe, input and query
 * port over such a viewer when code first asks for one, a click's own
 * Cesium picks (`rendererOf.js`), the map engine the map stacks switch
 * through (`src/maps/engine.js`), and the sky's precise ICRF rotation
 * (`src/sky/icrf.js`).
 */
import './camera.js';
import './effects.js';
import './frame.js';
import './globe.js';
import './input.js';
import './mapEngine.js';
import './nativeClick.js';
import './query.js';
import './starrySky.js';
