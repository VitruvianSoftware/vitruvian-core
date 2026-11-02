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

import { displayPanelScroller } from './displayPanelScroll.js';

/**
 * Show the existing Display groups in Cockpit's Display popover while Cockpit
 * is on. The portal publishes the popover's slots; the Display panel
 * teleports its groups into them and back. The portal keeps each surface's
 * scroll position and puts back focus the move dropped.
 */
export class CockpitDisplayPortal {
  constructor({
    standardPanel,
    cockpitPanel,
    groups,
    layout,
    publish = () => {},
    afterRender = (callback) => callback(),
  }) {
    this.standardPanel = standardPanel;
    this.cockpitPanel = cockpitPanel;
    this.layout = layout;
    this.publish = publish;
    this.afterRender = afterRender;
    this.active = false;
    this.destroyed = false;
    this.stopped = false;
    this.restoreOwner = null;
    this.generation = 0;
    this.frames = new Set();
    this.listeners = new AbortController();
    this.records = groups.flatMap(([name, group]) => {
      const slot = cockpitPanel?.querySelector(
        `[data-cockpit-display-slot="${name}"]`,
      );
      if (!group || !slot) return [];
      return [{ name, group, slot }];
    });
    this.slots = Object.freeze(
      Object.fromEntries(this.records.map(({ name, slot }) => [name, slot])),
    );
    this.standardScrollTop =
      displayPanelScroller(standardPanel)?.scrollTop || 0;
    this.cockpitScrollTop = cockpitPanel?.scrollTop || 0;
    const options = { passive: true, signal: this.listeners.signal };
    standardPanel?.addEventListener(
      'scroll',
      () => {
        if (!this.active)
          this.standardScrollTop =
            displayPanelScroller(standardPanel).scrollTop;
      },
      { ...options, capture: true },
    );
    cockpitPanel?.addEventListener(
      'scroll',
      () => {
        if (this.active) this.cockpitScrollTop = cockpitPanel.scrollTop;
      },
      options,
    );
    window.addEventListener(
      'gev:cockpit-mode-changed',
      (event) => {
        this.setActive(event?.detail?.active === true);
      },
      { signal: this.listeners.signal },
    );
    this.setActive(document.body.classList.contains('cockpit-mode'));
  }

  _frame(generation, callback) {
    const frame = requestAnimationFrame(() => {
      this.frames.delete(frame);
      if (!this.stopped && generation === this.generation) callback();
    });
    this.frames.add(frame);
  }

  _cancelFrames() {
    for (const frame of this.frames) cancelAnimationFrame(frame);
    this.frames.clear();
    this.generation += 1;
  }

  setActive(active, { settle = true } = {}) {
    if (this.stopped) return;
    const nextActive = active === true;
    if (this.active === nextActive) return;
    this._cancelFrames();
    const generation = this.generation;
    const focusedRecord = this.records.find((record) =>
      record.group.contains(document.activeElement),
    );
    const focusedElement = focusedRecord ? document.activeElement : null;
    this.restoreOwner = nextActive ? 'cockpit' : 'standard';
    this.active = nextActive;
    this.publish(nextActive ? this.slots : null);
    const restoreScroll = () => {
      if (nextActive && this.cockpitPanel)
        this.cockpitPanel.scrollTop = this.cockpitScrollTop;
      if (!nextActive && this.standardPanel)
        displayPanelScroller(this.standardPanel).scrollTop =
          this.standardScrollTop;
    };
    if (!settle) {
      this.afterRender(() => {
        if (generation !== this.generation) return;
        restoreScroll();
        this.restoreOwner = null;
      });
      return;
    }
    this._frame(generation, () => {
      restoreScroll();
      // Restore only the focus the move dropped: Cockpit entry hands focus to
      // its exit button in the meantime, and that wins.
      const current = document.activeElement;
      if (
        !current ||
        current === document.body ||
        focusedRecord?.group.contains(current)
      )
        focusedElement?.focus?.({ preventScroll: true });
      this._frame(generation, () => {
        restoreScroll();
        this.restoreOwner = null;
      });
    });
    // The surfaces are measured once the groups have moved.
    this.afterRender(() => {
      if (!this.stopped && generation === this.generation) this.layout();
    });
  }

  stop() {
    if (this.stopped) return;
    this.stopped = true;
    this._cancelFrames();
    this.listeners.abort();
  }

  destroy() {
    if (this.destroyed) return;
    this.stop();
    this.destroyed = true;
    this.active = false;
    this.publish(null);
    const { standardPanel, standardScrollTop } = this;
    this.afterRender(() => {
      if (standardPanel)
        displayPanelScroller(standardPanel).scrollTop = standardScrollTop;
    });
    this.records = [];
    this.restoreOwner = null;
  }
}
