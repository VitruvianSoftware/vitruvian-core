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

module.exports = {
  run: [
    {
      method: 'shell.run',
      params: {
        path: '..',
        // Update reuses the install doctor. The child re-reads raw app
        // ENVIRONMENT so blank fields override Pinokio-global values too.
        env: {
          GOOGLE_MAPS_API_KEY: '{{env.GOOGLE_MAPS_API_KEY || ""}}',
          CESIUM_ION_TOKEN: '{{env.CESIUM_ION_TOKEN || ""}}',
          OPENAI_API_KEY: '{{env.OPENAI_API_KEY || ""}}',
          AISSTREAM_API_KEY: '{{env.AISSTREAM_API_KEY || ""}}',
          FIRMS_MAP_KEY: '{{env.FIRMS_MAP_KEY || ""}}',
          TOMTOM_API_KEY: '{{env.TOMTOM_API_KEY || ""}}',
          OPENSKY_CLIENT_ID: '{{env.OPENSKY_CLIENT_ID || ""}}',
          OPENSKY_CLIENT_SECRET: '{{env.OPENSKY_CLIENT_SECRET || ""}}',
          LL2_API_TOKEN: '{{env.LL2_API_TOKEN || ""}}',
          GEV_RATELIMIT_OPENAI_PER_MIN: '{{env.GEV_RATELIMIT_OPENAI_PER_MIN || ""}}',
          GEV_RATELIMIT_GOOGLE_PER_MIN: '{{env.GEV_RATELIMIT_GOOGLE_PER_MIN || ""}}',
        },
        message: 'node scripts/pinokio-update.mjs',
      },
    },
  ],
};
