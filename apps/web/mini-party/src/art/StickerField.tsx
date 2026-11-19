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

import { Sticker } from "./Sticker";

// Every game's sticker, scattered around the edges of the screen like a
// sticker sheet. Fixed positions (left %, top %, size in vmin, tilt) so the
// layout is the same on every visit and the middle stays clear for the lobby.
const SCATTER: [string, number, number, number, number][] = [
  // Left column
  ["reaction", 3, 5, 14, -14],
  ["dodge", 13, 22, 11, 6],
  ["count", 4, 38, 12, 8],
  ["scan", 12, 54, 11, -6],
  ["mash", 3, 70, 14, -10],
  ["target", 13, 85, 12, 10],
  // Right column
  ["pattern", 89, 9, 12, 12],
  ["balance", 88, 22, 10, -4],
  ["fuel", 86, 38, 12, -8],
  ["smash", 88, 54, 12, 16],
  ["tug", 80, 70, 14, -6],
  ["stop", 90, 86, 11, -12],
  ["match", 68, 91, 9, 14],
];

export default function StickerField({ opacity = 0.6 }: { opacity?: number }) {
  return (
    <div
      className="absolute inset-0 overflow-hidden pointer-events-none"
      style={{ opacity }}
      aria-hidden
    >
      {SCATTER.map(([id, left, top, size, tilt]) => (
        <Sticker
          key={id}
          id={id}
          className="absolute"
          // Sizes in vmin keep the sheet in proportion from phone to TV.
          style={{
            left: `${left}%`,
            top: `${top}%`,
            width: `${size}vmin`,
            height: `${size}vmin`,
            transform: `rotate(${tilt}deg)`,
          }}
        />
      ))}
    </div>
  );
}
