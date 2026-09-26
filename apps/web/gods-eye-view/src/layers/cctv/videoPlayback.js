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

/** One decoder per active camera; both surfaces consume this video element. */
export function attachCctvVideo(
  video,
  url,
  feedType,
  {
    loadHls = () => import('hls.js'),
    onFailure = () => {},
    fetchImpl = globalThis.fetch,
  } = {},
) {
  // Preserve replay for existing finite video feeds; live HLS must not loop.
  video.loop = feedType !== 'hls';
  let disposed = false;
  let hls = null;
  const leaseId = feedType === 'hls' ? globalThis.crypto.randomUUID() : null;
  const mediaUrl =
    feedType === 'hls'
      ? `${url}${url.includes('?') ? '&' : '?'}lease=${leaseId}`
      : url;
  let timer = null;
  let startup = null;
  let governor = null;
  let retries = 0;
  const release = () => {
    if (feedType === 'hls') {
      void fetchImpl?.(mediaUrl, { method: 'DELETE', keepalive: true }).catch(
        () => {},
      );
    }
  };
  const dispose = () => {
    if (disposed) return;
    disposed = true;
    clearTimeout(timer);
    clearTimeout(startup);
    clearInterval(governor);
    hls?.destroy();
    hls = null;
    video.removeEventListener('canplay', play);
    video.removeEventListener('error', fail);
    video.pause();
    video.removeAttribute('src');
    video.load();
    release();
  };
  const fail = () => {
    if (disposed) return;
    dispose();
    onFailure();
  };
  const play = () => {
    if (disposed) return;
    clearTimeout(startup);
    video.play().catch(() => {});
  };
  video.addEventListener('canplay', play);
  video.addEventListener('error', fail);
  startup = setTimeout(fail, 30000);
  const ready = (async () => {
    if (feedType !== 'hls') {
      video.src = mediaUrl;
      return;
    }
    try {
      const { default: Hls } = await loadHls();
      if (disposed) return;
      if (!Hls.isSupported()) {
        if (video.canPlayType('application/vnd.apple.mpegurl'))
          video.src = mediaUrl;
        else fail();
        return;
      }
      hls = new Hls({
        enableWorker: true,
        maxBufferLength: 24,
        maxMaxBufferLength: 30,
        backBufferLength: 0,
        maxBufferSize: 16 * 1024 * 1024,
        liveSyncDurationCount: 3,
      });
      hls.on(Hls.Events.ERROR, (_event, data) => {
        if (disposed || !data?.fatal) return;
        if (++retries > 2) {
          fail();
          return;
        }
        clearTimeout(timer);
        timer = setTimeout(() => {
          if (disposed) return;
          if (data.type === Hls.ErrorTypes.MEDIA_ERROR) hls.recoverMediaError();
          else hls.loadSource(mediaUrl);
        }, 2000);
      });
      governor = setInterval(() => {
        if (disposed || !video.buffered?.length) return;
        const ahead =
          video.buffered.end(video.buffered.length - 1) - video.currentTime;
        // Some agency encoders publish less media time than wall time. Bound
        // correction rather than repeatedly draining the live buffer at 1x.
        video.playbackRate =
          ahead < 6 ? 0.8 : ahead < 12 ? 0.9 : ahead > 24 ? 1.05 : 1;
      }, 1000);
      hls.attachMedia(video);
      hls.loadSource(mediaUrl);
    } catch {
      fail();
    }
  })();
  return { dispose, ready };
}
