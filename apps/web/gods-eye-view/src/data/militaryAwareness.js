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

import { createApplicationAwareness } from '../app/layers/militaryAwareness.js';
import flights from './flights.js';
import military from './militaryFlights.js';
import vessels from './aisLiveVessels.js';
import installations from './militaryInstallations.js';

const layer = createApplicationAwareness({
  flights,
  military,
  vessels,
  installations,
});
export const contextTargetFlyToAllowed = layer.contextTargetFlyToAllowed;
export const awarenessClearMatchesSubject = layer.awarenessClearMatchesSubject;
export const awarenessRefreshIntervalMs = layer.awarenessRefreshIntervalMs;
export const awarenessRefreshDecision = layer.awarenessRefreshDecision;
export const awarenessClearIsEviction = layer.awarenessClearIsEviction;
export const awarenessRefreshRequired = layer.awarenessRefreshRequired;
export const summarizeInstallationViewport =
  layer.summarizeInstallationViewport;
export const contactsWindowFromSnapshot = layer.contactsWindowFromSnapshot;
export const buildAwarenessContextSnapshot =
  layer.buildAwarenessContextSnapshot;
export const collectAircraftProximityWindow =
  layer.collectAircraftProximityWindow;
export const _getAwarenessNavigationStateForTest =
  layer._getAwarenessNavigationStateForTest;
export const canNavigateAwarenessNext = layer.canNavigateAwarenessNext;
export const historySubjectSnapshot = layer.historySubjectSnapshot;
export const findCompatibleHistoryIndex = layer.findCompatibleHistoryIndex;
export const awarenessPanelControlKey = layer.awarenessPanelControlKey;
export const captureAwarenessPanelFocus = layer.captureAwarenessPanelFocus;
export const restoreAwarenessPanelFocus = layer.restoreAwarenessPanelFocus;
export const awarenessResultsAreLive = layer.awarenessResultsAreLive;
export const awarenessNeedsContinuousRender =
  layer.awarenessNeedsContinuousRender;
export { AWARENESS_QUERY_LIMIT } from '../layers/awareness/index.js';
export default layer;
