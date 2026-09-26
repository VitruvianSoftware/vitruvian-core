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

/** Route Cockpit keys while preserving the active disclosure and form-control owner. */

export function onKeyDown(event) {
  if (this.destroyed) return false;
  if (event.repeat || event.isComposing) return;
  if (event.key === 'Escape' && this.active) {
    // The credit lightbox owns Escape while its Close control or links hold
    // focus. Its target handler closes the overlay and restores attribution
    // focus; Cockpit must stay active behind it.
    if (event.target?.closest?.('.cesium-credit-lightbox')) return;
    if (
      document
        .getElementById('context-radio-dock')
        ?.classList.contains('disclosure-open')
    )
      return;
    if (
      document.querySelector('#cockpit-utility-controls [aria-expanded="true"]')
    )
      return;
    if (this.context?.contains(event.target) && !this.contextCollapsed) {
      event.preventDefault();
      event.stopImmediatePropagation();
      this.setContextCollapsed(true);
      if (
        event.target === this.contextToggle ||
        this.contextToggle?.contains?.(event.target)
      ) {
        this.contextToggle?.blur?.();
      } else {
        this.contextToggle?.focus({ preventScroll: true });
      }
      return;
    }
    if (this.signalStream?.contains(event.target) && !this.signalCollapsed) {
      event.preventDefault();
      event.stopImmediatePropagation();
      this.setSignalCollapsed(true, { user: true });
      if (
        event.target === this.signalToggle ||
        this.signalToggle?.contains?.(event.target)
      ) {
        this.signalToggle?.blur?.();
      } else {
        this.signalToggle?.focus({ preventScroll: true });
      }
      return;
    }
    event.preventDefault();
    event.stopImmediatePropagation();
    this.exit();
    return;
  }
  if (event.target?.closest?.('input, textarea, select, [contenteditable]'))
    return;
  const key = event.key?.toLowerCase();
  if (key === 'c' && !event.metaKey && !event.ctrlKey && !event.altKey) {
    if (!this.active) {
      const cockpitAttempt = !!(
        this.readAircraftInfo() && this.viewer.trackedEntity?.position
      );
      if (!cockpitAttempt) return;
    }
    event.preventDefault();
    event.stopImmediatePropagation();
    if (!this.active && !this.isEntryAllowed()) return;
    const changed = this.active ? this.exit() : this.enter();
    return;
  }
}
