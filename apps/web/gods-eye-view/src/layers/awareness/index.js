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

import { createModel } from './model.js';
import { createSubject } from './subject.js';
import { createPanel } from './panel.js';
import { createQueries } from './queries.js';
import { createNavigation } from './navigation.js';
import { createFocus } from './focus.js';
import { createTesting } from './testing.js';
import { createHistory } from './history.js';
import { createRendering } from './rendering.js';
import { createLifecycle } from './lifecycle.js';
import { createDependencies } from './dependencies.js';
import { createControls } from './controls.js';
import { createIngestion } from './ingestion.js';
import { createState } from './state.js';

/** Construct one layer with its own scene state and supplied application services. */
export function createAwarenessLayer({ services, source }) {
  const state = createState({ services });
  const parts = {};
  const context = { state, services, parts, source };
  parts.model = createModel(context);
  parts.subject = createSubject(context);
  parts.panel = createPanel(context);
  parts.queries = createQueries(context);
  parts.navigation = createNavigation(context);
  parts.focus = createFocus(context);
  parts.testing = createTesting(context);
  parts.history = createHistory(context);
  parts.rendering = createRendering(context);
  parts.lifecycle = createLifecycle(context);
  parts.dependencies = createDependencies(context);
  parts.controls = createControls(context);
  parts.ingestion = createIngestion(context);
  return Object.assign(
    {},
    parts.controls.methods,
    parts.lifecycle.methods,
    parts.ingestion?.methods,
    {
      contextTargetFlyToAllowed: parts.model.contextTargetFlyToAllowed,
      awarenessClearMatchesSubject: parts.subject.awarenessClearMatchesSubject,
      awarenessRefreshIntervalMs: parts.model.awarenessRefreshIntervalMs,
      awarenessRefreshDecision: parts.model.awarenessRefreshDecision,
      awarenessClearIsEviction: parts.model.awarenessClearIsEviction,
      awarenessRefreshRequired: parts.model.awarenessRefreshRequired,
      summarizeInstallationViewport:
        parts.queries.summarizeInstallationViewport,
      contactsWindowFromSnapshot: parts.model.contactsWindowFromSnapshot,
      buildAwarenessContextSnapshot: parts.model.buildAwarenessContextSnapshot,
      collectAircraftProximityWindow:
        parts.queries.collectAircraftProximityWindow,
      _getAwarenessNavigationStateForTest:
        parts.testing._getAwarenessNavigationStateForTest,
      canNavigateAwarenessNext: parts.navigation.canNavigateAwarenessNext,
      historySubjectSnapshot: parts.history.historySubjectSnapshot,
      findCompatibleHistoryIndex: parts.history.findCompatibleHistoryIndex,
      awarenessPanelControlKey: parts.panel.awarenessPanelControlKey,
      captureAwarenessPanelFocus: parts.panel.captureAwarenessPanelFocus,
      restoreAwarenessPanelFocus: parts.panel.restoreAwarenessPanelFocus,
      awarenessResultsAreLive: parts.panel.awarenessResultsAreLive,
      awarenessNeedsContinuousRender:
        parts.model.awarenessNeedsContinuousRender,
    },
  );
}
export { AWARENESS_QUERY_LIMIT } from './policy.js';
