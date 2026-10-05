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

/** The local MCP server: Core's tools over services backed by a running app. */

import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import {
  composeCatalog,
  coreTools,
  catalogForSurface,
} from '../../src/tools/index.js';
import {
  createGlobePanelResource,
  panelRuntime,
} from '../../src/tools/panel.js';
import { createMcpServer } from '../../src/tools/mcp/index.js';
import { DEFAULT_API_BASE, createLocalToolServices } from './services.js';

const INSTRUCTIONS =
  "Tools answer questions from God's Eye View's live public data. Location " +
  'tools take an area: a place name, a bbox, or lat/lon with radius_km. ' +
  'Results are capped; check truncated and total before concluding there is nothing more. ' +
  "Answers that can be shown in God's Eye View include data.view; to show one, call " +
  'show_in_gods_eye_view with that view, adding layers, style, a camera or marks as ' +
  "needed. It shows live God's Eye View where the client displays apps and " +
  'returns a link everywhere.';

/** Construct the local MCP server for Core's tools. */
export function createLocalMcpServer({
  apiBase = DEFAULT_API_BASE,
  fetchImpl,
} = {}) {
  const { version } = JSON.parse(
    readFileSync(new URL('../../package.json', import.meta.url), 'utf8'),
  );
  // Each server makes a new key for its panel. The panel's page carries it
  // and panel_request requires it; any client may read the page, so it keeps
  // the tool from clients that only list it, and is not access control.
  const panelKey = randomBytes(32).toString('base64url');
  return createMcpServer({
    catalog: catalogForSurface(
      composeCatalog({
        tools: coreTools,
        services: createLocalToolServices({ apiBase, fetchImpl, panelKey }),
      }),
      'mcp',
    ),
    name: 'gods-eye-view',
    version,
    instructions: INSTRUCTIONS,
    resources: [createGlobePanelResource({ runtime: panelRuntime, panelKey })],
  });
}
