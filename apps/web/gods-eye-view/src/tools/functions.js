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

/** Function-calling adapter for a tool catalog: tool records and results. */

/** Tools as `{ type: 'function', name, description, parameters }` records. */
export function toFunctionTools(tools, { exclude = [] } = {}) {
  const skipped = new Set(exclude);
  return tools
    .filter((tool) => !skipped.has(tool.name))
    .map((tool) => ({
      type: 'function',
      name: tool.name,
      description: tool.description,
      parameters: structuredClone(tool.inputSchema),
    }));
}

/**
 * A tool result as one JSON function output. Images are counted rather than
 * sent, since function outputs carry text.
 */
export function toFunctionOutput(name, result) {
  return {
    ok: true,
    tool: name,
    summary: result.summary,
    data: result.data,
    ...(result.images?.length ? { images_omitted: result.images.length } : {}),
  };
}
