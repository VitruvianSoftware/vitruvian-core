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
import { coreTools, toFunctionOutput, toFunctionTools } from './index.js';

test('catalog tools become independent function records', () => {
  const records = toFunctionTools(coreTools, {
    exclude: ['show_in_gods_eye_view'],
  });
  assert.equal(records.length, coreTools.length - 1);
  assert.ok(!records.some((tool) => tool.name === 'show_in_gods_eye_view'));
  const weather = records.find((tool) => tool.name === 'get_weather');
  const source = coreTools.find((tool) => tool.name === 'get_weather');
  assert.deepEqual(Object.keys(weather), [
    'type',
    'name',
    'description',
    'parameters',
  ]);
  assert.equal(weather.type, 'function');
  assert.equal(weather.description, source.description);
  assert.deepEqual(weather.parameters, source.inputSchema);
  assert.notEqual(weather.parameters, source.inputSchema);
  weather.parameters.properties.location.description = 'changed';
  assert.notEqual(
    source.inputSchema.properties.location.description,
    'changed',
  );
  assert.ok(records.every((tool) => tool.parameters.type === 'object'));
});

test('results become function outputs without image data', () => {
  assert.deepEqual(
    toFunctionOutput('get_wind', { summary: 'Calm.', data: { calm: true } }),
    { ok: true, tool: 'get_wind', summary: 'Calm.', data: { calm: true } },
  );
  assert.deepEqual(
    toFunctionOutput('get_weather_map', {
      summary: 'Radar.',
      data: {},
      images: [{ mimeType: 'image/png', data: 'AAAA' }],
    }),
    {
      ok: true,
      tool: 'get_weather_map',
      summary: 'Radar.',
      data: {},
      images_omitted: 1,
    },
  );
});
