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

const CLOUD_VOICE_AUTH_MODES = Object.freeze(['api-key', 'oauth']);
const DEFAULT_CLOUD_VOICE_AUTH_MODE = 'api-key';
export const CLOUD_VOICE_AUTH_STORAGE_KEY = 'godsEyeView.voice.cloudAuth';

function storageRef(storage) {
  if (storage) return storage;
  try {
    return typeof localStorage === 'undefined' ? null : localStorage;
  } catch {
    return null;
  }
}

function normalizeCloudVoiceAuthMode(mode) {
  const normalized = String(mode || '')
    .trim()
    .toLowerCase();
  return CLOUD_VOICE_AUTH_MODES.includes(normalized)
    ? normalized
    : DEFAULT_CLOUD_VOICE_AUTH_MODE;
}

export function readStoredCloudVoiceAuthMode(storage) {
  try {
    return normalizeCloudVoiceAuthMode(
      storageRef(storage)?.getItem(CLOUD_VOICE_AUTH_STORAGE_KEY),
    );
  } catch {
    return DEFAULT_CLOUD_VOICE_AUTH_MODE;
  }
}

export function writeStoredCloudVoiceAuthMode(mode, storage) {
  const resolved = normalizeCloudVoiceAuthMode(mode);
  try {
    storageRef(storage)?.setItem(CLOUD_VOICE_AUTH_STORAGE_KEY, resolved);
  } catch {
    /* best effort */
  }
  return resolved;
}
