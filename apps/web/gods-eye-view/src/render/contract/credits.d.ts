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
 * Attribution. The renderer reports every credit it owes (its own, each
 * base layer's, and per-tile credits as tiles load); the application renders the
 * credit DOM, so the credits always look the same.
 */
import type { Off } from './common';

/** One credit, as plain data: the application renders and escapes it. */
export interface Credit {
  /** Plain text, never markup. */
  text: string;
  /** Where the credit links to. */
  href?: string;
  /** The words of `text` the link covers; the whole text when absent. */
  linkText?: string;
  /** A logo, drawn in place of the text; the text names it. */
  logoUrl?: string;
  /** Shown on the map itself, rather than in the expanded list. */
  inline?: boolean;
}

export interface CreditsPort {
  /** Add a credit the application owes (a layer's source). */
  addStatic(credit: Credit): Off;
  /** Every credit owed now, in display order. */
  list(): Credit[];
  on(event: 'change', cb: (credits: Credit[]) => void): Off;
}
