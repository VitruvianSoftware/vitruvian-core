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

import { validateValue } from '../../../src/tools/schema.js';

export function invalidCalls(calls, tools) {
  const schemas = new Map(tools.map((tool) => [tool.name, tool.parameters]));
  return calls.flatMap((call, index) => {
    const schema = schemas.get(call.name);
    const errors = !schema
      ? ['Unknown tool']
      : call.parseError
        ? ['Arguments must be valid JSON']
        : validateValue(schema, call.args === undefined ? {} : call.args);
    return errors.length
      ? [{ index, error: errors.slice(0, 4).join('; ').slice(0, 1000) }]
      : [];
  });
}

// Missing usage stays unknown, never an invented zero-cost request.
export function parseUsage(provider, data) {
  const raw = provider === 'gemini' ? data?.usageMetadata : data?.usage;
  const number = (value) =>
    Number.isSafeInteger(value) && value >= 0 ? value : null;
  const inputTokens = number(
    provider === 'gemini' ? raw?.promptTokenCount : raw?.prompt_tokens,
  );
  const candidateTokens = number(
    provider === 'gemini' ? raw?.candidatesTokenCount : raw?.completion_tokens,
  );
  const totalTokens = number(
    provider === 'gemini' ? raw?.totalTokenCount : raw?.total_tokens,
  );
  if (inputTokens === null || candidateTokens === null || totalTokens === null)
    return null;
  const reasoningTokens =
    number(
      provider === 'gemini'
        ? raw?.thoughtsTokenCount
        : raw?.completion_tokens_details?.reasoning_tokens,
    ) ?? 0;
  const outputTokens =
    candidateTokens + (provider === 'gemini' ? reasoningTokens : 0);
  return {
    inputTokens,
    outputTokens,
    totalTokens,
    reasoningTokens,
    cachedInputTokens:
      number(
        provider === 'gemini'
          ? raw?.cachedContentTokenCount
          : raw?.prompt_tokens_details?.cached_tokens,
      ) ?? 0,
  };
}
