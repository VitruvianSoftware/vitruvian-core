# Street Level

## Overview
Component package providing implementation for `apps/web/gods-eye-view/scripts/fixtures/street-level`.

## Interface
- `[kartaView.mjs:KV_SEQUENCE_ID]`
- `[kartaView.mjs:KV_LINE]`
- `[kartaView.mjs:KV_OLD_STREET]`
- `[kartaView.mjs:resetKartaViewFixture]`
- `[kartaView.mjs:kartaViewPhotos]`
- `[kartaView.mjs:maskTilePng]`
- `[kartaView.mjs:describeKartaViewCall]`
- `[kartaView.mjs:answerKartaViewRequest]`
- `[mapillaryGraph.mjs:PHOTO_SEQUENCE_ID]`
- `[mapillaryGraph.mjs:PHOTO_LINE]`
- `[mapillaryGraph.mjs:THUMB_HOST]`
- `[mapillaryGraph.mjs:metresApart]`
- `[mapillaryGraph.mjs:photoImages]`
- `[mapillaryGraph.mjs:photoJpeg]`
- `[mapillaryGraph.mjs:describeCall]`
- `[mapillaryGraph.mjs:answerMapillaryRequest]`
- `[panoramax.mjs:PNX_SEQUENCES]`
- `[panoramax.mjs:PNX_LINE]`
- `[panoramax.mjs:PNX_PARK]`
- `[panoramax.mjs:resetPanoramaxFixture]`

## Invariants
- None

## Side Effects
- [kartaView.mjs:166]: `/** Whether a street has photos passing a filtered tile's query. */`
- [kartaView.mjs:167]: `function passesTileQuery(street, query) {`
- [kartaView.mjs:168]: `const view = query.get('fieldOfView');`
- [mapillaryGraph.mjs:208]: `...json(400, { error: 'unsupported images query' }),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/scripts/fixtures/street-level/...`
