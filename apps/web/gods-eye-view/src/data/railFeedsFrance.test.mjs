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

// France (2026-11-10): the Bordeaux and Montpellier tram networks, from
// transport.data.gouv.fr. Registered, switched on with the dataset's licence
// field quoted, polled for live positions, and sorted into categories; no
// registry URL is on a download path its host's robots.txt disallows.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  RAIL_FEED_REGISTRY,
  classifyTrain,
  getRailFeed,
  getRegisteredRailFeed,
  railFeedHasTripUpdates,
  railFeedPositions,
} from './railFeeds.js';

const kind = (id, routeId) => {
  const train = classifyTrain(getRegisteredRailFeed(id), routeId);
  return train ? `${train.category}/${train.mode}` : null;
};

const FR_FEEDS = ['tbm-bordeaux', 'tam-montpellier'];

// ------------------------------------------------------------ registry

test('the French feeds are on and quote the dataset licence field', () => {
  for (const id of FR_FEEDS) {
    const feed = getRegisteredRailFeed(id);
    assert.ok(feed, `${id} is registered`);
    assert.ok(getRailFeed(id), `${id} is pollable`);
    assert.equal(feed.defaultEnabled, true, id);
    assert.match(feed.staticGtfsUrl, /^https:\/\//, id);
    assert.ok(['lov2', 'odc-odbl', 'fr-lo'].includes(feed.terms.quote), id);
    assert.match(feed.terms.note, /transport\.data\.gouv\.fr dataset "/, id);
    assert.match(feed.terms.note, /2026-11-10/, id);
  }
});

test('the ODbL dataset carries the share-alike note and the access point conditions', () => {
  const feed = getRegisteredRailFeed('tam-montpellier');
  assert.equal(feed.license, 'ODbL 1.0');
  assert.match(feed.terms.note, /share-alike/);
  assert.match(feed.terms.note, /dans le format d'origine/);
  assert.equal(
    getRegisteredRailFeed('tbm-bordeaux').license,
    'Licence Ouverte / Open Licence 1.0',
  );
});

test('positions: Bordeaux and Montpellier trams are GPS, with trip updates', () => {
  for (const id of FR_FEEDS) {
    assert.equal(railFeedPositions(getRegisteredRailFeed(id)), 'gps', id);
    assert.ok(railFeedHasTripUpdates(getRegisteredRailFeed(id)), id);
  }
});

// ------------------------------------------------------------ categories

test('tram lines are transit; buses are dropped', () => {
  const cases = [
    ['tbm-bordeaux', '164', 'transit/tram'],
    ['tbm-bordeaux', '901', null],
    ['tam-montpellier', '5', 'transit/tram'],
    ['tam-montpellier', 'A', null],
  ];
  for (const [id, route, expected] of cases)
    assert.equal(kind(id, route), expected, `${id} ${route}`);
});

// ------------------------------------------------------------ download

// Hosts whose robots.txt disallows the download paths French publishers use.
const DISALLOWED = [
  /^https:\/\/eu\.ftp\.opendatasoft\.com\//,
  /^https:\/\/thello\.axelor\.com\//,
  /^https:\/\/static\.data\.gouv\.fr\/resources\//,
  /^https:\/\/www\.data\.gouv\.fr\/(fr\/)?(api\/1\/)?datasets\/r\//,
  /\/explore\/dataset\/.*\/download/,
];

test('no registry URL is on a download path its robots.txt disallows', () => {
  for (const feed of RAIL_FEED_REGISTRY)
    for (const url of [feed.url, feed.tripUpdatesUrl, feed.staticGtfsUrl])
      if (url)
        for (const pattern of DISALLOWED)
          assert.ok(!pattern.test(url), `${feed.id} ${url}`);
});
