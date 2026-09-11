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

import { realpathSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyPinokioEnvironment } from './pinokio-environment.mjs';
import { formatSetupReport, inspectSetup, npmProcessSpec } from './setup-doctor.mjs';

const MODULE_PATH = fileURLToPath(import.meta.url);
const ROOT = realpathSync(path.resolve(path.dirname(MODULE_PATH), '..'));
const READY_FILE = path.join(ROOT, 'pinokio', '.installed');

export function runChecked(command, args, { shell = false } = {}) {
  const result = spawnSync(command, args, {
    cwd: ROOT,
    env: { ...process.env, PUPPETEER_SKIP_DOWNLOAD: '1' },
    shell,
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}

export function installPinokioDependencies() {
  applyPinokioEnvironment();
  rmSync(READY_FILE, { force: true });
  const npm = npmProcessSpec();
  runChecked(npm.command, ['ci'], { shell: npm.shell });

  // Pinokio starts Vite directly and loads only its ENVIRONMENT file plus the
  // normal dotenv ladder. Unlike dev-fresh.sh, it does not import macOS
  // Keychain items, so its install report must describe that exact runtime.
  const report = inspectSetup({
    includeKeychain: false,
    // The raw app ENVIRONMENT file was applied above. Even an empty field now
    // shadows Vite's dotenv ladder, so diagnosis must stop there instead of
    // claiming a dotenv-only value will reach the launched app.
    authoritativeEnvironment: true,
  });
  console.log(`\n${formatSetupReport(report, {
    readyMessage: 'Ready. Return to Pinokio and choose Start.',
  })}\n`);
  if (!report.ready) process.exit(1);

  writeFileSync(READY_FILE, `${new Date().toISOString()}\n`, { mode: 0o600 });
  console.log('[Pinokio] Installation ready.');
}

export function isDirectInvocation(
  invokedPath = process.argv[1],
  modulePath = MODULE_PATH,
) {
  if (typeof invokedPath !== 'string' || invokedPath.length === 0) return false;
  if (typeof modulePath !== 'string' || modulePath.length === 0) return false;
  try {
    return realpathSync(path.resolve(invokedPath)) === realpathSync(path.resolve(modulePath));
  } catch {
    return path.resolve(invokedPath) === path.resolve(modulePath);
  }
}

if (isDirectInvocation()) {
  installPinokioDependencies();
}
