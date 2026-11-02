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
import RailCards from './rail/RailCards.vue';

/**
 * Keyed cards with optional ordered blocks; the feature owns open-card choice.
 * Renders the RailCards component into `container`, which it owns, and
 * patches it synchronously on every update so the owner can measure at once.
 */
export function createRailCards({
  container,
  document = container?.ownerDocument,
  cardClassName = '',
  badgeClassName = '',
  onParams = () => {},
  onOpen = () => {},
} = {}) {
  if (!document?.createElement || !container) return null;
  let destroyed = false;
  return {
    update(cards = []) {
      if (destroyed) return;
      render(
        h(RailCards, {
          cards,
          cardClassName,
          badgeClassName,
          onParams,
          onOpen,
        }),
        container,
      );
    },
    destroy() {
      if (destroyed) return;
      destroyed = true;
      render(null, container);
    },
  };
}
