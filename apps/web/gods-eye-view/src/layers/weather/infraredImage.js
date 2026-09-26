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

import { readResponseBytesCapped } from '../../sources/httpBody.js';
import { weatherImageUrl } from './source.js';
import { infraredAlpha } from './infraredAlpha.js';

export const MAX_MOSAIC_BYTES = 4 * 1024 * 1024;

/** Apply the display transfer once to a decoded image; `flipY` draws a
 * bottom-up image back upright. */
export function processInfraredImage(
  image,
  mode,
  createCanvas,
  { flipY = false } = {},
) {
  const canvas = createCanvas();
  canvas.width = image.width;
  canvas.height = image.height;
  const context = canvas.getContext('2d');
  if (flipY) context.setTransform(1, 0, 0, -1, 0, image.height);
  context.drawImage(image, 0, 0);
  if (flipY) context.setTransform(1, 0, 0, 1, 0, 0);
  const pixels = context.getImageData(0, 0, canvas.width, canvas.height);
  pixels.data.set(infraredAlpha(pixels.data, mode));
  context.putImageData(pixels, 0, 0);
  return canvas;
}

/** Decode locally, releasing the object URL on success, failure or cancellation. */
export function decodeInfraredImage(blob, signal) {
  signal.throwIfAborted();
  if (typeof globalThis.createImageBitmap === 'function')
    return globalThis.createImageBitmap(blob);
  return new Promise((resolve, reject) => {
    const image = new Image();
    const url = URL.createObjectURL(blob);
    const cleanup = () => {
      signal.removeEventListener('abort', abort);
      image.onload = image.onerror = null;
      URL.revokeObjectURL(url);
    };
    const abort = () => {
      cleanup();
      image.src = '';
      reject(signal.reason);
    };
    image.onload = () => {
      cleanup();
      resolve(image);
    };
    image.onerror = () => {
      cleanup();
      reject(new Error('Infrared decode failed'));
    };
    signal.addEventListener('abort', abort, { once: true });
    image.src = url;
  });
}

/** Fetch one capped whole-extent frame, or a `bbox` detail window of it, and draw
 * it into a canvas. Infrared frames get the display transfer; a canvas also keeps
 * Cesium's texture row order, which an ImageBitmap upload would not. The decoded
 * image is always released. */
export async function acquireWeatherImage(
  product,
  time,
  {
    signal,
    mode,
    size,
    bbox = null,
    maxBytes,
    createCanvas,
    fetchImpl,
    decodeImage = decodeInfraredImage,
    now = () => performance.now(),
    onFetched = () => {},
  },
) {
  const response = await fetchImpl(weatherImageUrl(product, time, size, bbox), {
    signal,
  });
  if (!response.ok) throw new Error(`Weather HTTP ${response.status}`);
  const bytes = await readResponseBytesCapped(response, maxBytes);
  signal.throwIfAborted();
  onFetched();
  const started = now();
  const image = await decodeImage(
    new Blob([bytes], { type: 'image/png' }),
    signal,
  );
  try {
    signal.throwIfAborted();
    if (image.width !== size.width || image.height !== size.height)
      throw new Error('Invalid weather image dimensions');
    let texture;
    if (product === 'clouds' || product === 'clouds-regional')
      texture = processInfraredImage(image, mode, createCanvas);
    else {
      texture = createCanvas();
      texture.width = image.width;
      texture.height = image.height;
      texture.getContext('2d').drawImage(image, 0, 0);
    }
    return { texture, decodeMs: now() - started };
  } finally {
    image.close?.();
  }
}

/** Acquire one capped global mosaic before adding any imagery layer. */
export function acquireInfraredMosaic(time, options) {
  return acquireWeatherImage('clouds', time, {
    ...options,
    size: { width: 2048, height: 1024 },
    maxBytes: MAX_MOSAIC_BYTES,
  });
}
