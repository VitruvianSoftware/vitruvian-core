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

import { h, render } from 'vue';
import RailTimeline from './rail/RailTimeline.vue';

export { utcClock } from './rail/utcClock.js';

/**
 * Stable native transport with local preview and a coalesced 150 ms drag
 * commit. Renders the RailTimeline component into `container` and patches it
 * synchronously on every update.
 */
export function createRailTimeline({
  container,
  document = container?.ownerDocument,
  sliderClassName = '',
  heading = true,
  onCommit = () => {},
  onPreview = () => {},
  onStep = () => {},
  onLatest = () => {},
  onPlay = () => {},
} = {}) {
  if (!document?.createElement || !container) return null;
  let destroyed = false;
  const paint = (state) =>
    render(
      h(RailTimeline, {
        state,
        sliderClassName,
        heading,
        onCommit,
        onPreview,
        onStep,
        onLatest,
        onPlay,
      }),
      container,
    );
  paint({
    ticks: [],
    index: 0,
    mode: 'latest',
    playing: false,
    readout: '',
    disabled: true,
  });
  return {
    update(state) {
      if (!destroyed) paint(state);
    },
    destroy() {
      if (destroyed) return;
      destroyed = true;
      render(null, container);
    },
  };
}
