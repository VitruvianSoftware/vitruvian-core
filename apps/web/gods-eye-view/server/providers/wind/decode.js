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

/** Lazy shared ecCodes WASM instance, created only for an active wind request. */
let eccodesPromise = null;
function loadEccodes() {
  eccodesPromise ??= import('@meri-imperiumi/eccodes-wasm')
    .then((module) => module.createEccodes())
    .catch((error) => {
      eccodesPromise = null;
      throw error;
    });
  return eccodesPromise;
}

/** Decode one bounded message in WASM memory without mounting the host filesystem. */
export async function decodeWindGribMessage(buffer, { eccodesModule } = {}) {
  if (buffer.byteLength > 8 * 1024 * 1024)
    throw new Error('Wind GRIB exceeds byte budget');
  const eccodes = eccodesModule ?? (await loadEccodes());
  // Everything after this await is synchronous. A shared virtual file is safe
  // across U/V and model requests and its storage is released after each decode.
  const file = '/gev-wind.grib2';
  let handle = null;
  try {
    eccodes.writeFile(file, buffer);
    handle = eccodes.openGrib(file);
    const ni = handle.getLong('Ni');
    const nj = handle.getLong('Nj');
    if (
      !Number.isInteger(ni) ||
      !Number.isInteger(nj) ||
      ni < 1 ||
      nj < 1 ||
      ni * nj > 2_000_000
    )
      throw new Error('Invalid wind GRIB geometry');
    return {
      ni,
      nj,
      lo1: handle.getDouble('longitudeOfFirstGridPointInDegrees'),
      la1: handle.getDouble('latitudeOfFirstGridPointInDegrees'),
      di: handle.getDouble('iDirectionIncrementInDegrees'),
      dj: handle.getDouble('jDirectionIncrementInDegrees'),
      values: handle.getDoubleArray('values'),
      shortName: handle.getString('shortName'),
      level: handle.getLong('level'),
      units: handle.getString('units'),
    };
  } finally {
    handle?.delete();
    eccodes.writeFile(file, new Uint8Array(0));
  }
}
