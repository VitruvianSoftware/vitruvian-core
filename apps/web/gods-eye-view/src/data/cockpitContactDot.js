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
 * Lazily create the shared white contact pip used by aircraft layers while the
 * first-person cockpit is active. Cesium multiplies this white texture by the
 * billboard color, so civilian and military owners retain their provenance
 * colors without maintaining separate image assets.
 *
 * @returns {string} One stable data-URL identity shared by every billboard.
 */
export function cockpitContactDotImage() {
  if (cockpitContactDotImage._dataUrl) return cockpitContactDotImage._dataUrl;

  const canvas = document.createElement('canvas');
  canvas.width = 16;
  canvas.height = 16;
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, 16, 16);

  // Match the visor's fine-line symbology: a restrained luminous ring with a
  // crisp center fix, rather than a solid map-marker blob. The layer tint
  // supplies civilian cyan-white or military amber provenance.
  ctx.save();
  ctx.shadowBlur = 2.5;
  ctx.shadowColor = 'rgba(255, 255, 255, 0.55)';
  ctx.beginPath();
  ctx.arc(8, 8, 4.25, 0, Math.PI * 2);
  ctx.lineWidth = 1.25;
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.82)';
  ctx.stroke();
  ctx.shadowBlur = 1.5;
  ctx.beginPath();
  ctx.arc(8, 8, 1.55, 0, Math.PI * 2);
  ctx.fillStyle = 'rgba(255, 255, 255, 0.98)';
  ctx.fill();
  ctx.restore();

  // Billboard.image assigns a fresh texture-atlas id to non-string sources.
  // Returning the same canvas for hundreds of contacts therefore still made
  // Cesium upload/repack hundreds of identical textures at cockpit entry.
  // A stable URL is keyed once and shared by the entire fleet.
  cockpitContactDotImage._dataUrl = canvas.toDataURL('image/png');
  return cockpitContactDotImage._dataUrl;
}

cockpitContactDotImage._dataUrl = null;
