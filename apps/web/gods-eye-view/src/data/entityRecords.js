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
 * @module entityRecords
 * @description Records for the entities layers draw, so layer state lives in the app
 * rather than on the renderer's objects. A layer writes the record for an entity it draws;
 * the tracked readout, follow camera, cockpit, share links and awareness read it back
 * through the entity the renderer hands them (a pick or the tracked entity).
 *
 * Fields a record may hold:
 * - `trackedId`: the normalized `layer:id` identity, e.g. `flights:a1b2c3`.
 * - `displayPosition()`: the layer's cached display position (the follow camera's
 *   anti-jitter contract: the value the camera settled on, never recomputed late).
 * - `visualPosition()`: where a 3D model is actually drawn, for the tracked card.
 * - `labelModel`: the tracked card's `{ title, details, accent, … }`.
 * - `selectionOrigin`: what started the selection (`'user'`, …).
 * - `sprite`: a tracked billboard's pushed `{ width, height, scale, scaleByDistance }`, for
 *   the close-range camera guard and the screen annotations' tracked footprint.
 * - `groundSets()`: the draw set ids a height sample under the contact sees through (its own
 *   icons and models), for Cockpit's ground probe.
 *
 * A layer's private per-entity state goes in its own store ({@link createEntityStore}).
 */

/**
 * A store of one record per renderer object, held by the app and dropped with the object.
 * @returns {{ write: (entity: Object) => Object, read: (entity: unknown) => Object|null }}
 *   `write` makes the record empty on first use; `read` gives null when there is none.
 */
export function createEntityStore() {
  const records = new WeakMap();
  return {
    write(entity) {
      let record = records.get(entity);
      if (!record) {
        record = {};
        records.set(entity, record);
      }
      return record;
    },
    read(entity) {
      if (!entity || typeof entity !== 'object') return null;
      return records.get(entity) ?? null;
    },
  };
}

const shared = createEntityStore();

/**
 * The record for `entity`, made empty on first use. For layers writing their own state.
 * @param {Object} entity An entity the layer draws.
 * @returns {Object}
 */
export function entityRecord(entity) {
  return shared.write(entity);
}

/**
 * The record for `entity`, or null when it has none (or there is no entity). For readers.
 * @param {Object|null|undefined} entity
 * @returns {Object|null}
 */
export function readEntityRecord(entity) {
  return shared.read(entity);
}

/**
 * Write `fields` into `entity`'s record and return the entity.
 * @param {Object} entity
 * @param {Object} fields Record fields to set.
 * @returns {Object} `entity`
 */
export function withEntityRecord(entity, fields) {
  Object.assign(entityRecord(entity), fields);
  return entity;
}
