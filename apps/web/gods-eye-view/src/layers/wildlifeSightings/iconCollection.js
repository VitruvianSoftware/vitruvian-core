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
 * @module layers/wildlifeSightings/iconCollection
 * @description The sighting badges' icons draw set behind the small
 * collection shape the billboard model (`billboardModel.js`) reconciles:
 * `add` hands back a point whose property writes (`position`, `image`,
 * `show` and the appearance) are batched and sent to the set as one upsert
 * per task, and `remove`/`removeAll` take items off it. A point's `id` is
 * its item id, so a pick on a badge names it.
 */

/** Item fields a point carries as they are (its appearance). */
const PASSED = [
  'size',
  'color',
  'scale',
  'scaleByDistance',
  'disableDepthTest',
  'pickable',
];

/**
 * @param {import('../../render/contract/draw').DrawSet<import('../../render/contract/draw').IconItem>} set
 * @param {{schedule?: (flush: () => void) => void}} [options] - How the
 *   batched writes are flushed (a microtask by default).
 */
export function createWildlifeIconCollection(
  set,
  { schedule = queueMicrotask } = {},
) {
  /** @type {Map<string, object>} Points by item id. */
  const points = new Map();
  /** @type {Set<object>} Points written since the last flush. */
  const dirty = new Set();
  let scheduled = false;
  const canvasKeys = new WeakMap();
  let canvasCount = 0;

  /** A sprite as the contract names it: a URL, or a canvas with its key. */
  function imageRef(image) {
    if (typeof image === 'string' || !image) return image;
    if (!canvasKeys.has(image))
      canvasKeys.set(image, `wildlife-sprite:${++canvasCount}`);
    return { canvas: image, key: canvasKeys.get(image) };
  }

  function itemOf(point) {
    const item = {
      id: point.id,
      pos: point.position,
      image: imageRef(point.image),
      show: point.show !== false,
    };
    for (const key of PASSED)
      if (point[key] !== undefined) item[key] = point[key];
    return item;
  }

  function flush() {
    scheduled = false;
    if (!dirty.size) return;
    const items = [];
    for (const point of dirty)
      if (points.get(point.id) === point) items.push(itemOf(point));
    dirty.clear();
    if (items.length) set.upsert(items);
  }

  function touch(point) {
    dirty.add(point);
    if (scheduled) return;
    scheduled = true;
    schedule(flush);
  }

  return {
    /** Add a point (`id`, `position`, `image` and its appearance). */
    add(options) {
      const point = new Proxy(
        { show: true, ...options },
        {
          set(target, key, value) {
            if (target[key] === value) return true;
            target[key] = value;
            touch(point);
            return true;
          },
        },
      );
      points.set(point.id, point);
      touch(point);
      return point;
    },
    remove(point) {
      if (points.get(point?.id) !== point) return false;
      points.delete(point.id);
      dirty.delete(point);
      set.remove([point.id]);
      return true;
    },
    removeAll() {
      points.clear();
      dirty.clear();
      set.clear();
    },
    /** Take the set off the renderer. */
    dispose() {
      points.clear();
      dirty.clear();
      set.dispose();
    },
    /** Send the batched writes now. */
    flush,
    get show() {
      return set.show;
    },
    set show(value) {
      set.show = value;
    },
    get length() {
      return points.size;
    },
  };
}
