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

import PanelRailView from './PanelRailView.vue';
import { PANEL_RAIL_HOST_CLASS, PANEL_RAIL_ITEMS } from './panelRailCatalog.js';
import { usePanelStore } from './stores/panels.js';

/**
 * Own the desktop panel rails: publish each side's panels to the panel store
 * and open or close a panel when its rail item is selected. Disclosure itself
 * stays with PanelChrome, which enforces one open panel per side.
 */
export class PanelNavigation {
  /**
   * @param {object} options
   * @param {{pinia: object, mount: Function}} options.ui Shell Vue runtime.
   * @param {{left: HTMLElement|null, right: HTMLElement|null}} options.stacks Side panel stacks.
   * @param {Function} options.setPanelCollapsed PanelChrome's disclosure operation.
   */
  constructor({ ui, stacks, setPanelCollapsed }) {
    this._ui = ui;
    this._stacks = stacks;
    this._setPanelCollapsed = setPanelCollapsed;
    this._store = usePanelStore(ui.pinia);
    this._unmounts = [];
    this._hosts = [];
    this._observer = null;
    this._destroyed = false;
  }

  init() {
    if (this._destroyed) return;
    for (const side of ['left', 'right']) {
      const stack = this._stacks[side];
      if (!stack) continue;
      // Inside the stack, the rail shows and hides with its panels in every
      // presentation mode (Cockpit, clean view, recording, phone sheets).
      const host = stack.ownerDocument.createElement('div');
      host.className = `${PANEL_RAIL_HOST_CLASS} ${PANEL_RAIL_HOST_CLASS}--${side}`;
      stack.prepend(host);
      this._hosts.push(host);
      this._unmounts.push(
        this._ui.mount(PanelRailView, host, {
          side,
          onSelect: (panelId) => this.select(panelId),
        }),
      );
    }
    if (typeof MutationObserver !== 'undefined') {
      // Only the panels themselves matter: their order, disclosure and
      // availability, not changes inside them or inside the rails.
      this._observer = new MutationObserver((records) => {
        if (records.some((record) => this._isPanelRecord(record))) this.sync();
      });
      for (const stack of Object.values(this._stacks)) {
        if (!stack) continue;
        this._observer.observe(stack, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['class', 'hidden'],
        });
      }
    }
    this.sync();
  }

  /** Publish both sides' panels in display order. */
  sync() {
    if (this._destroyed) return;
    for (const side of ['left', 'right']) {
      const stack = this._stacks[side];
      const panels = stack
        ? [...stack.children]
            .filter((panel) => panel.matches('[data-panel-id]'))
            .map((panel) => {
              const shownBy = PANEL_RAIL_ITEMS[panel.id]?.shownBy;
              return {
                id: panel.id,
                title:
                  panel
                    .querySelector('.panel-title, .pp-header-label')
                    ?.textContent.trim() || panel.id,
                open: !panel.classList.contains('collapsed'),
                available:
                  !panel.hidden &&
                  (!shownBy || panel.classList.contains(shownBy)),
              };
            })
        : [];
      this._store.setSide(side, panels);
    }
  }

  /**
   * Toggle a panel from its rail item.
   * @param {string} panelId Panel element id.
   */
  select(panelId) {
    if (this._destroyed) return;
    // The panel itself, not the store: the store follows its class a
    // microtask later, after a same-task setPanelCollapsed.
    const panel = document.getElementById(panelId);
    if (!panel) return;
    this._setPanelCollapsed(panelId, !panel.classList.contains('collapsed'), {
      explicit: true,
    });
  }

  _isPanelRecord(record) {
    const stacks = Object.values(this._stacks);
    return record.type === 'childList'
      ? stacks.includes(record.target) &&
          [...record.addedNodes, ...record.removedNodes].some(
            (node) => !this._hosts.includes(node),
          )
      : stacks.includes(record.target.parentElement);
  }

  destroy() {
    if (this._destroyed) return;
    this._destroyed = true;
    this._observer?.disconnect();
    this._observer = null;
    for (const unmount of this._unmounts) unmount();
    this._unmounts = [];
    for (const host of this._hosts) host.remove();
    this._hosts = [];
  }
}
