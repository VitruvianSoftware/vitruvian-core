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
 * Monorepo Vite entry: upstream's standalone config with a Bazel-safe Cesium
 * asset copy. (Upstream's file is a two-line re-export of the same config.)
 *
 * vite-plugin-cesium copies Build/Cesium into dist with fs-extra, which
 * lstat/readlinks every file. Under Bazel the rules_js node fs patches reject
 * that walk with EINVAL on the pnpm-store symlinks, the plugin logs "copy
 * failed" and the bundle ships without dist/cesium. Its closeBundle is replaced
 * with a dereferencing fs.cp of the same five targets; :cesium_assets_test
 * (scripts/verify-cesium-assets.sh) checks the result.
 */
import fs from 'node:fs';
import { promises as fsp } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import standalone from './server/standalone/vite.config.js';

// Preserve existing test and tooling imports while provider modules are split.
export * from './server/providers/local.js';

const CESIUM_TARGETS = ['Assets', 'ThirdParty', 'Workers', 'Widgets', 'Cesium.js'];

function cesiumBuildDir() {
  const local = path.resolve('node_modules/cesium/Build/Cesium');
  if (fs.existsSync(local)) return local;
  const cesiumDir = path.dirname(createRequire(import.meta.url).resolve('cesium/package.json'));
  return path.join(cesiumDir, 'Build', 'Cesium');
}

function bazelSafeCesiumPlugin(base) {
  let resolvedConfig;
  return {
    ...base,
    configResolved(config) {
      resolvedConfig = config;
      return base.configResolved?.(config);
    },
    async closeBundle() {
      if (resolvedConfig?.command !== 'build') return;
      const outDir = path.resolve(resolvedConfig.root, resolvedConfig.build?.outDir || 'dist');
      const outCesiumDir = path.join(outDir, 'cesium');
      const buildDir = cesiumBuildDir();
      if (!fs.existsSync(buildDir)) {
        throw new Error(`Cesium build directory not found at ${buildDir}`);
      }
      await fsp.mkdir(outCesiumDir, { recursive: true });
      for (const target of CESIUM_TARGETS) {
        const src = path.join(buildDir, target);
        if (!fs.existsSync(src)) throw new Error(`Required Cesium asset not found: ${src}`);
        await fsp.cp(src, path.join(outCesiumDir, target), { recursive: true, dereference: true });
      }
    },
  };
}

export default function config(env) {
  const resolved = standalone(env);
  resolved.plugins = resolved.plugins.map((plugin) =>
    plugin?.name === 'vite-plugin-cesium' ? bazelSafeCesiumPlugin(plugin) : plugin,
  );
  return resolved;
}
