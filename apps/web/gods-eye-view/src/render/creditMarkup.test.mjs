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
import { creditFromMarkup, splitLink } from './creditMarkup.js';

test('text, the first link and the first logo are read from markup', () => {
  assert.deepEqual(
    creditFromMarkup(
      'Map data <a href="https://www.openstreetmap.org/copyright" target="_blank">&copy; OpenStreetMap</a> (<a href="https://opendatacommons.org/">ODbL</a>)',
    ),
    {
      text: 'Map data © OpenStreetMap (ODbL)',
      href: 'https://www.openstreetmap.org/copyright',
      linkText: '© OpenStreetMap',
    },
  );
  assert.deepEqual(
    creditFromMarkup(
      '<a href=\'https://cesium.com/\'><img src="/ion.png" title="Cesium ion"/></a>',
    ),
    { text: 'Cesium ion', href: 'https://cesium.com/', logoUrl: '/ion.png' },
  );
  assert.deepEqual(creditFromMarkup('<img src=x.png alt="Logo">'), {
    text: 'Logo',
    logoUrl: 'x.png',
  });
});

test('character references decode; tags, comments and scripts drop', () => {
  assert.deepEqual(
    creditFromMarkup(
      '  A&nbsp;&amp;&#39;B&#x2014;&unknown; <!-- c --><script>x</script>\n  <b>C</b>',
    ),
    { text: "A &'B—&unknown; C" },
  );
  assert.deepEqual(creditFromMarkup('<a data-href="no" href="yes">x</a>'), {
    text: 'x',
    href: 'yes',
  });
  assert.deepEqual(
    creditFromMarkup(
      '<a title="A > B" href="https://example.com/?q=>">Provider</a>',
    ),
    { text: 'Provider', href: 'https://example.com/?q=>' },
  );
  assert.deepEqual(
    creditFromMarkup(
      '<a href="javascript:alert(1)"><img src="javascript:x" alt="L"></a>',
    ),
    { text: 'L' },
  );
  assert.deepEqual(creditFromMarkup('<img src="data:text/html,x" alt="L">'), {
    text: 'L',
  });
  assert.deepEqual(creditFromMarkup(''), { text: '' });
  assert.deepEqual(creditFromMarkup(undefined), { text: '' });
});

test('a link around some of the words keeps those words as the linked ones', () => {
  const credit = creditFromMarkup(
    'Street Level: imagery © <a href="https://www.mapillary.com" target="_blank" rel="noopener">Mapillary</a> contributors, CC BY-SA 4.0',
  );
  assert.equal(
    credit.text,
    'Street Level: imagery © Mapillary contributors, CC BY-SA 4.0',
  );
  assert.equal(credit.linkText, 'Mapillary');
  assert.deepEqual(splitLink(credit), [
    'Street Level: imagery © ',
    'Mapillary',
    ' contributors, CC BY-SA 4.0',
  ]);
});

test('a link around all of the words needs no linked words', () => {
  const credit = creditFromMarkup('<a href="https://example.com/">Example</a>');
  assert.equal(credit.linkText, undefined);
  assert.deepEqual(splitLink(credit), ['', 'Example', '']);
});
