#!/usr/bin/env node
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
 * Build the MCP Apps panel: the app under dist/panel, served at /panel/.
 * See build/panel.js.
 */

import { readFile, rename, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'vite';
import standaloneConfig from '../server/standalone/vite.config.js';
import {
  PANEL_BASE,
  PANEL_OUT_DIR,
  PANEL_WORKER_FILES,
  PANEL_WORKER_PRELUDE_PATH,
  panelBuildConfig,
  workerFilesPrelude,
} from '../build/panel.js';

const root = fileURLToPath(new URL('../', import.meta.url));
const outDir = join(root, PANEL_OUT_DIR);

const config = standaloneConfig({ command: 'build', mode: 'production' });
await build({
  configFile: false,
  root,
  ...panelBuildConfig(config),
});

// Cesium's plugin copies its files under the base path inside outDir.
const nested = join(outDir, PANEL_BASE, 'cesium');
await rm(join(outDir, 'cesium'), { recursive: true, force: true });
await rename(nested, join(outDir, 'cesium'));
await rm(join(outDir, PANEL_BASE.split('/')[1]), { recursive: true });

// Cesium's workers load these files themselves; embed them in a prelude the
// panel runs ahead of Cesium's workers script.
const files = {};
for (const name of PANEL_WORKER_FILES)
  files[name] = await readFile(join(outDir, 'cesium', name), 'utf8');
await writeFile(
  join(outDir, PANEL_WORKER_PRELUDE_PATH),
  workerFilesPrelude(files),
);
console.log(`Panel build written to ${PANEL_OUT_DIR}`);
