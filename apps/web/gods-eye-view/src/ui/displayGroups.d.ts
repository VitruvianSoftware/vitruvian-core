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

/** A row of a group added to the Display panel. */
export type DisplayGroupRow =
  | {
      kind: 'toggle';
      id: string;
      label: string;
      icon?: string;
      title?: string;
      checked: boolean;
      onChange(checked: boolean): void;
    }
  | {
      kind: 'slider';
      id: string;
      label: string;
      min: number;
      max: number;
      /** Shown in percent. */
      value: number;
      onChange(value: number): void;
    }
  | { kind: 'note'; id: string; text: string };

/**
 * Show the group `id` on the page's Display panel, under Effects, in place
 * where it is shown already; null takes it away.
 */
export function publishDisplayGroup(
  id: string,
  group: { rows: DisplayGroupRow[] } | null,
): void;
