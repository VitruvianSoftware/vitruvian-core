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

const MAX_SWITCHES_LENGTH = 256;
const ENTRY = /^([a-z][a-z0-9-]*)-([01])$/;

/** Canonical, bounded boolean switches keyed by stable slugs. */
export function normalizeIdSwitches(value, reservedIds = []) {
  if (typeof value !== 'string' || value.length > MAX_SWITCHES_LENGTH)
    return null;
  if (!value) return '';
  const entries = new Map();
  for (const field of value.split('*')) {
    const match = ENTRY.exec(field);
    if (!match || reservedIds.includes(match[1]) || entries.has(match[1]))
      return null;
    entries.set(match[1], match[2] === '1');
  }
  return [...entries]
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([id, on]) => `${id}-${on ? '1' : '0'}`)
    .join('*');
}

/** Encode by stable IDs rather than registration order or generated tokens. */
export function encodeIdSwitches(switches) {
  const value = [...switches]
    .map(([id, on]) => `${id}-${on === true ? '1' : '0'}`)
    .join('*');
  if (value.length > MAX_SWITCHES_LENGTH)
    throw new RangeError(
      `Switch IDs exceed the ${MAX_SWITCHES_LENGTH}-character share-link limit`,
    );
  const normalized = normalizeIdSwitches(value);
  if (normalized === null) throw new TypeError('Invalid boolean switch IDs');
  return normalized;
}

/** A Map keeps switch IDs separate from object prototype properties. */
export function decodeIdSwitches(value) {
  const normalized = normalizeIdSwitches(value);
  return new Map(
    normalized
      ? normalized.split('*').map((entry) => {
          const [, id, on] = ENTRY.exec(entry);
          return [id, on === '1'];
        })
      : [],
  );
}

/** Persist only explicitly requested switch IDs, not unrelated live changes. */
export function patchRequestedIdSwitches(previous, applied, requested) {
  const current = decodeIdSwitches(applied);
  const next = new Map(
    [...decodeIdSwitches(previous)].filter(([id]) => current.has(id)),
  );
  let changed = false;
  for (const [id, on] of current) {
    if (Object.hasOwn(requested, id) && typeof requested[id] === 'boolean') {
      next.set(id, on);
      changed = true;
    }
  }
  return changed ? encodeIdSwitches(next) : undefined;
}
