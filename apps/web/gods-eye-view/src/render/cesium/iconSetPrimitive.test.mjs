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

import assert from 'node:assert/strict';
import test from 'node:test';
import * as Cesium from 'cesium';
import { createIconSet } from '../../data/iconSet.js';
import { IconSetPrimitive } from './iconSetPrimitive.js';

// Node has no WebGL context to report line-width limits.
Cesium.ContextLimits._minimumAliasedLineWidth = 1;
Cesium.ContextLimits._maximumAliasedLineWidth = 10;

/** The primitive's draw commands, made without a context: programs stubbed. */
function commandsOf(options = {}) {
  const made = [];
  const fromCache = Cesium.ShaderProgram.fromCache;
  Cesium.ShaderProgram.fromCache = ({ fragmentShaderSource }) => {
    const program = { defines: fragmentShaderSource.defines, destroy() {} };
    made.push(program);
    return program;
  };
  try {
    const primitive = new IconSetPrimitive({
      set: createIconSet(),
      renderTime: () => Cesium.JulianDate.now(),
      ...options,
    });
    primitive._createCommands(undefined);
    return { primitive, programs: made };
  } finally {
    Cesium.ShaderProgram.fromCache = fromCache;
  }
}

test('a translucent set draws one blended pass in order, as translucent billboards do', () => {
  const { primitive } = commandsOf({ translucent: () => true });
  const single = primitive._singleCommand;
  // In the opaque pass, out of the translucent pass's order-independent blend.
  assert.equal(single.pass, Cesium.Pass.OPAQUE);
  const state = single.renderState;
  // Equal depths pass, so the last row drawn is on top.
  assert.equal(state.depthTest.enabled, true);
  assert.equal(state.depthTest.func, Cesium.DepthFunction.LESS_OR_EQUAL);
  assert.equal(state.depthMask, true);
  assert.equal(state.blending.enabled, true);
  // Every fragment drawn: neither pass's alpha split.
  assert.deepEqual(single.shaderProgram.defines, []);
  assert.equal(primitive.drawsBlend('translucent'), true);
  assert.equal(primitive.drawsBlend('additive'), false);
});

test('by default the set draws an opaque pass and a translucent one, and draws no blend itself', () => {
  const { primitive } = commandsOf();
  const [opaque, translucent] = primitive._commands;
  assert.equal(opaque.pass, Cesium.Pass.OPAQUE);
  assert.deepEqual(opaque.shaderProgram.defines, ['OPAQUE']);
  assert.equal(opaque.renderState.depthTest.func, Cesium.DepthFunction.LESS);
  assert.equal(translucent.pass, Cesium.Pass.TRANSLUCENT);
  assert.deepEqual(translucent.shaderProgram.defines, ['TRANSLUCENT']);
  assert.equal(translucent.renderState.depthMask, false);
  assert.equal(primitive.drawsBlend('translucent'), false);
});
