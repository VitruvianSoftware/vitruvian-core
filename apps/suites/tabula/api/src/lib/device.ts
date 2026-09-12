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
 * Helpers for the optional x-device-id request header.
 *
 * Devices identify themselves with `x-device-id` (string, max 100 chars).
 * The id is advisory: it feeds the workspace active-device lease and is echoed
 * in published sync events so a device can ignore its own changes.
 */
import type { FastifyRequest } from "fastify";

export const MAX_DEVICE_ID_LENGTH = 100;

/**
 * Read and validate the optional x-device-id header.
 * Returns undefined when absent, empty, or longer than 100 characters.
 */
export function getDeviceId(request: FastifyRequest): string | undefined {
  const header = request.headers["x-device-id"];
  const value = Array.isArray(header) ? header[0] : header;
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_DEVICE_ID_LENGTH)
    return undefined;
  return trimmed;
}
