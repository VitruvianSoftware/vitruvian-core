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

import { realtimeInstructions } from '../openai/instructions.js';
import { GEV_REALTIME_TOOLS } from '../openai/tools.js';

export const GEMINI_LIVE_MODEL_DEFAULT = 'gemini-3.8-live';
export const GEMINI_TOKEN_ENDPOINT =
  'https://generativelanguage.googleapis.com/v1beta/auth_tokens';
export const GEMINI_LIVE_WEBSOCKET_URL =
  'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained';

export function normalizeGeminiModel(value) {
  const model = String(value ?? GEMINI_LIVE_MODEL_DEFAULT)
    .trim()
    .replace(/^models\//, '');
  return /^gemini-[a-z0-9][a-z0-9.-]{0,119}$/.test(model) ? model : null;
}

/** REST BidiGenerateContentSetup fields, excluding its model resource name. */
export function createGeminiLiveConfig(
  annotationGuidance,
  inputMode = 'open-mic',
  tools = GEV_REALTIME_TOOLS,
) {
  if (!['open-mic', 'push-to-talk'].includes(inputMode))
    throw new Error('Invalid Gemini input mode');
  const config = {
    generationConfig: { responseModalities: ['AUDIO'] },
    systemInstruction: {
      parts: [{ text: realtimeInstructions(annotationGuidance) }],
    },
    tools: [
      {
        functionDeclarations: tools.map(
          ({ name, description, parameters }) => ({
            name,
            description,
            // GEV's canonical schemas are JSON Schema, not Google's Schema.
            parametersJsonSchema: structuredClone(parameters),
            // App actions must finish before the model confirms their result.
            behavior: 'BLOCKING',
          }),
        ),
      },
    ],
    inputAudioTranscription: {},
    outputAudioTranscription: {},
    contextWindowCompression: { slidingWindow: {} },
  };
  if (inputMode === 'push-to-talk')
    config.realtimeInputConfig = {
      automaticActivityDetection: { disabled: true },
    };
  return config;
}
