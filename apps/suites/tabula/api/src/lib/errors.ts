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
 * Typed errors shared across services and routes
 */

/**
 * Thrown when an optimistic-concurrency check fails (client baseVersion is
 * older than the stored version). Routes translate this into a 409 response
 * carrying the current server copy of the entity.
 */
export class ConflictError extends Error {
  readonly currentVersion: number;

  constructor(message: string, currentVersion: number) {
    super(message);
    this.name = "ConflictError";
    this.currentVersion = currentVersion;
  }
}

/**
 * Thrown when the caller can SEE a resource but lacks the role to perform the
 * requested action (e.g. a VIEW collaborator attempting a write). Distinct from
 * "not found": this confirms the resource exists. `statusCode` lets the central
 * errorHandler map it to 403; routes that catch locally check `instanceof`.
 */
export class ForbiddenError extends Error {
  readonly statusCode = 403;

  constructor(message = "Forbidden") {
    super(message);
    this.name = "ForbiddenError";
  }
}

/**
 * Thrown when a resource does not exist OR the caller has no visibility into it
 * at all. The two cases are deliberately indistinguishable to avoid leaking
 * existence to strangers (enumeration masking). The default message matches the
 * pre-existing "Workspace not found" sentinel so older string-matching catch
 * blocks keep mapping it to 404; `statusCode` covers handlers that bubble.
 */
export class NotFoundError extends Error {
  readonly statusCode = 404;

  constructor(message = "Workspace not found") {
    super(message);
    this.name = "NotFoundError";
  }
}
