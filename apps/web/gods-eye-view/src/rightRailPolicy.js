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
 * Tactical HUD gives an expanded right-rail panel the whole control lane.
 * Other HUD layouts keep collapsed launchers visible for quick switching.
 *
 * @param {object} input Current rail state.
 * @param {string} input.hudVariant Active HUD layout variant.
 * @param {boolean} input.hasExpandedPanel Whether any rail panel is expanded.
 * @returns {boolean} Whether collapsed sibling launchers should be hidden.
 */
export function shouldHideCollapsedRightPanels({ hudVariant, hasExpandedPanel }) {
  return hudVariant === 'tactical' && Boolean(hasExpandedPanel);
}

const GLOBAL_CONTEXT_EXPLICIT_ACTIONS = new Set([
  'contacts',
  'space-missions',
  'cockpit',
]);

/**
 * Decide whether a completed action should reveal the Global Context panel.
 * Expansion belongs only to an explicit, successful owner action. Restoring a
 * session or replaying saved state must preserve the saved collapsed state,
 * and a failed transition must leave the prior panel state untouched.
 *
 * Whether an aircraft is already selected is deliberately irrelevant: an
 * explicit Cockpit action still reveals the context that supports that track.
 *
 * @param {object} input Action outcome and coordination state.
 * @param {'contacts'|'space-missions'|'cockpit'|string} input.action Completed action.
 * @param {boolean} input.explicitUserAction Whether the user directly requested it.
 * @param {boolean} input.succeeded Whether the requested transition completed.
 * @param {boolean} [input.restoring=false] Whether saved/session state is being restored.
 * @returns {boolean} Whether Global Context should be expanded.
 */
export function shouldExpandGlobalContextPanel({
  action,
  explicitUserAction,
  succeeded,
  restoring = false,
}) {
  return Boolean(
    GLOBAL_CONTEXT_EXPLICIT_ACTIONS.has(action)
    && explicitUserAction
    && succeeded
    && !restoring
  );
}
