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

class GevSdrAudioPlayer extends AudioWorkletProcessor {
  constructor() {
    super();
    this.queue = [];
    this.offset = 0;
    this.volume = 0.8;
    this.port.onmessage = (event) => {
      if (
        event.data?.type === 'samples' &&
        event.data.samples instanceof Float32Array
      ) {
        this.queue.push(event.data.samples);
        if (this.queue.length > 48)
          this.queue.splice(0, this.queue.length - 48);
      } else if (event.data?.type === 'volume') {
        this.volume = Math.max(0, Math.min(1, Number(event.data.value) || 0));
      } else if (event.data?.type === 'clear') {
        this.queue.length = 0;
        this.offset = 0;
      }
    };
  }

  process(_inputs, outputs) {
    const output = outputs[0]?.[0];
    if (!output) return true;
    output.fill(0);
    let outputOffset = 0;
    while (outputOffset < output.length && this.queue.length) {
      const samples = this.queue[0];
      const available = samples.length - this.offset;
      const count = Math.min(output.length - outputOffset, available);
      for (let index = 0; index < count; index += 1) {
        output[outputOffset + index] =
          samples[this.offset + index] * this.volume;
      }
      outputOffset += count;
      this.offset += count;
      if (this.offset >= samples.length) {
        this.queue.shift();
        this.offset = 0;
      }
    }
    return true;
  }
}

registerProcessor('gev-sdr-audio-player', GevSdrAudioPlayer);
