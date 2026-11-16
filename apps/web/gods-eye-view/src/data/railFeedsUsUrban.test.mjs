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

// United States streetcar feeds (Seattle, Cincinnati): switched on with
// their basis, polled for live positions, and sorted into categories with
// the buses dropped.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  RAIL_ENABLED_FEEDS,
  classifyTrain,
  getRailFeed,
  getRegisteredRailFeed,
  railFeedHasTripUpdates,
  railFeedPositions,
} from './railFeeds.js';

// Licensed and switched on.
const ON = ['seattle-streetcar', 'cincinnati-connector'];

const TRAM = { category: 'transit', mode: 'tram' };

const feed = (id) => getRegisteredRailFeed(id);
const kind = (id, routeId, context) =>
  classifyTrain(feed(id), routeId, context);

test('the US streetcar feeds: licensed feeds on, each with its basis', () => {
  for (const id of ON) {
    assert.ok(getRailFeed(id), `${id} is pollable`);
    assert.ok(RAIL_ENABLED_FEEDS.includes(feed(id)), id);
    assert.ok(feed(id).terms.note, `${id} explains its basis`);
    assert.ok(feed(id).staticGtfsUrl, `${id} has a timetable`);
    assert.ok(feed(id).terms.quote, `${id} quotes its terms`);
    // Nothing personal in the recorded basis.
    assert.doesNotMatch(feed(id).terms.note, /@/, id);
  }
});

test('the US streetcar feeds poll positions and trip updates', () => {
  for (const id of ON) {
    assert.equal(railFeedPositions(feed(id)), 'gps', id);
    assert.ok(railFeedHasTripUpdates(feed(id)), id);
  }
});

test('Seattle Streetcar: the two City of Seattle routes of the King County feed', () => {
  assert.deepEqual(kind('seattle-streetcar', '100340'), TRAM);
  assert.deepEqual(kind('seattle-streetcar', '102638'), TRAM);
  assert.equal(kind('seattle-streetcar', '100001'), null, 'a Metro bus');
  assert.equal(kind('seattle-streetcar', null), null);
  assert.equal(
    feed('seattle-streetcar').attribution,
    'Transit scheduling, geographic, and real-time data provided by permission of King County',
  );
});

test('Cincinnati Connector: the streetcar route, buses dropped', () => {
  assert.deepEqual(kind('cincinnati-connector', '100'), TRAM);
  assert.equal(kind('cincinnati-connector', '78'), null);
});
