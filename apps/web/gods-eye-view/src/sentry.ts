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

import type { App } from 'vue';

export interface SentryClientOptions {
  dsn?: string;
  environment?: string;
  tracesSampleRate?: number;
  diagnosticsEnabled?: boolean;
}

export interface RuntimeSentryConfig {
  dsn: string;
  environment: string;
  diagnosticsEnabled: boolean;
  tracesSampleRate: number;
}

export declare function fetchRuntimeSentryConfig(): Promise<RuntimeSentryConfig | null>;
export declare function initClientSentry(app?: App, options?: SentryClientOptions): Promise<boolean>;
export declare function attachVueApp(app: App): void;
export declare function captureClientException(err: unknown, context?: Record<string, unknown>): string | undefined;
export declare function triggerClientTestException(): string | undefined;
export declare function isClientSentryInitialized(): boolean;
export declare function isDiagnosticsEnabled(): boolean;
export declare function onDiagnosticsChange(fn: (enabled: boolean) => void): () => void;
