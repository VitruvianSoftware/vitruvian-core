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

/** Only this adapter knows the Realtime transcript and response event names. */
export function realtimeSessionEvent(payload) {
  const type = payload?.type;
  if (type === 'input_audio_buffer.speech_started')
    return { type: 'interruption', reason: 'user-speech' };
  if (type === 'conversation.item.input_audio_transcription.completed')
    return {
      type: 'transcript',
      role: 'user',
      text: payload.transcript || '',
      final: true,
      itemId: payload.item_id || null,
    };
  if (
    [
      'response.output_audio_transcript.delta',
      'response.output_audio_transcript.done',
      'response.output_text.delta',
      'response.output_text.done',
      'response.audio_transcript.delta',
      'response.audio_transcript.done',
      'response.text.delta',
      'response.text.done',
    ].includes(type)
  ) {
    const final = type.endsWith('.done');
    return {
      type: 'transcript',
      role: 'assistant',
      text: final
        ? (payload.transcript ?? payload.text ?? '')
        : payload.delta || '',
      final,
      itemId: payload.item_id || null,
      responseId: payload.response_id || null,
    };
  }
  if (type === 'response.done')
    return {
      type: 'completion',
      responseId: payload.response?.id || null,
      status: payload.response?.status || 'unknown',
    };
  return null;
}
