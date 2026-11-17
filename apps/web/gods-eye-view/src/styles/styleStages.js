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
 * @module styles/styleStages
 * @description The app's record of each visual style on a scene object (the
 * viewer the application's visual effects are made for): its
 * intensity, parameter values and whether it draws, as the application set
 * them. Code that must follow a style's picture (sensor picks) reads it here
 * rather than asking the renderer.
 */

const records = new WeakMap();

/**
 * Another object a scene object's styles may be recorded on, for test
 * doubles whose tests record them on the engine's own scene.
 */
let aliasOf = null;

/**
 * Let `styleStagesOf` also find records made on `alias(host)`; a later call
 * replaces it. For test doubles (src/input/testDoubles.mjs).
 * @param {((host: object) => object|null|undefined) | null} alias
 */
export function provideStyleStageAlias(alias) {
  aliasOf = alias;
}

/**
 * @param {object} scene The scene object.
 * @param {Record<string, {enabled: boolean, uniforms: Record<string, number>}>} stages
 * @returns {() => void} Forgets them, if they are still the scene's.
 */
export function registerStyleStages(scene, stages) {
  if (!scene || typeof scene !== 'object') return () => {};
  records.set(scene, stages);
  return () => {
    if (records.get(scene) === stages) records.delete(scene);
  };
}

/**
 * @param {object} scene
 * @returns {Record<string, {enabled: boolean, uniforms: Record<string, number>}> | null}
 */
export function styleStagesOf(scene) {
  if (!scene || typeof scene !== 'object') return null;
  const own = records.get(scene);
  if (own) return own;
  const alias = aliasOf?.(scene);
  return (alias && typeof alias === 'object' && records.get(alias)) || null;
}
