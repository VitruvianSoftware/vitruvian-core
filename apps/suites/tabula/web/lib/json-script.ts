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

// The two JS line-terminator code points (0x2028, 0x2029), built from
// their numeric code points rather than typed as a backslash-u escape in
// source: this file hit real cases of that escape sequence getting
// silently transcoded into the raw control character it describes, which
// is exactly the bug this function exists to prevent from reaching output.
const LINE_SEPARATOR = String.fromCharCode(0x2028);
const PARAGRAPH_SEPARATOR = String.fromCharCode(0x2029);

/**
 * Escape a value for safe embedding inside an inline <script type="application/json">.
 * Plain JSON.stringify does NOT neutralize the `</script>` sequence (a value
 * containing it could break out of the element), nor U+2028/U+2029 (valid
 * inside a JSON string but illegal as raw, unescaped line terminators in a
 * <script> body in some parsers) — mirrors
 * tabula/api/src/routes/auth.routes.ts's escapeJsonForScript.
 */
export function escapeJsonForScript(value: unknown): string {
  return JSON.stringify(value)
    .split("<")
    .join("\\u003c")
    .split(">")
    .join("\\u003e")
    .split(LINE_SEPARATOR)
    .join("\\u2028")
    .split(PARAGRAPH_SEPARATOR)
    .join("\\u2029");
}
