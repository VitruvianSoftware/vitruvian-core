# Wind

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/wind`.

## Interface
- `[catalog.js:GFS_BUCKET]`
- `[catalog.js:gfsObjectKey]`
- `[catalog.js:selectLatestGfsCycle]`
- `[catalog.js:nearestGfsStep]`
- `[decode.js:decodeWindGribMessage]`
- `[gfs.js:parseGfsIdx]`
- `[gfs.js:windMessageRanges]`
- `[gfs.js:fetchText]`
- `[gfs.js:fetchRange]`
- `[gfs.js:loadOptionalScalar]`
- `[gfs.js:fetchGfsWind]`
- `[grid.js:resampleWindGrid]`
- `[grid.js:weatherScalarMetadata]`
- `[grid.js:resampleWeatherFields]`
- `[grid.js:resampleWeatherSnapshot]`
- `[grid.js:weatherScalarError]`
- `[ifs.js:selectLatestIfsCycle]`
- `[ifs.js:ifsObjectUrls]`
- `[ifs.js:parseIfsIndex]`
- `[ifs.js:ifsWindRanges]`

## Invariants
- None

## Side Effects
- [decode.js:45]: `eccodes.writeFile(file, buffer);`
- [decode.js:71]: `eccodes.writeFile(file, new Uint8Array(0));`
- [gfs.js:94]: `/** Fetch a bounded text response as a Buffer. */`
- [gfs.js:95]: `export async function fetchText({ url, fetchImpl = fetch, signal }) {`
- [gfs.js:105]: `* Fetch one bounded byte range. Rejects oversized ranges, non-206 responses`
- [ifs.js:126]: `* Fetch and decode the IFS 10 m wind field valid closest to now.`
- [ifs.js:132]: `fetchImpl = fetch,`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/wind/...`
