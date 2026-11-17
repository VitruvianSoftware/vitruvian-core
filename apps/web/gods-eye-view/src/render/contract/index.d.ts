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
 * The renderer contract: what the application asks of a renderer, typed
 * one file per port.
 */
export * from './common';
export * from './renderer';
export * from './frame';
export * from './globe';
export * from './draw';
export * from './camera';
export * from './query';
export * from './input';
export * from './effects';
export * from './credits';
export * from './quality';

/** Every capability a renderer may list. */
export declare const CAPABILITIES: readonly import('./common').Capability[];

/** The contract version this module describes. */
export declare const CONTRACT_VERSION: import('./renderer').ContractVersion;

/** One port's members: null when required, else the capability that adds it. */
export type PortDescriptor = Readonly<
  Record<string, import('./common').Capability | null>
>;

/** Every port's members, by port name. */
export declare const PORTS: Readonly<Record<string, PortDescriptor>>;

/** One of the roles a renderer plays, and the members that make it up. */
export interface ContractRole {
  readonly id: 'surface' | 'scene' | 'view' | 'queries' | 'look' | 'host';
  readonly title: string;
  readonly summary: string;
  /** `port` or `port.member`; the most specific entry wins. */
  readonly members: readonly string[];
}

/** What a renderer does, by role: every member of {@link PORTS} in one. */
export declare const ROLES: readonly ContractRole[];

/**
 * The role of `port`'s `member` (dotted), or of the port itself without one;
 * undefined for a member the port does not have.
 */
export declare function roleOf(
  port: string,
  member?: string,
): ContractRole['id'] | undefined;

/** Every quality setting a renderer may support. */
export declare const QUALITY_KEYS: readonly import('./quality').QualityKey[];

/** The phases and steps of one frame, in order. */
export declare const FRAME_STEPS: readonly import('./frame').FrameStep[];

/**
 * What a renderer is missing against the contract: each required member it
 * lacks, and each capability-gated member present without its capability.
 */
export declare function checkRendererShape(renderer: unknown): string[];

/** What one port (or handed-out shape) is missing against its descriptor. */
export declare function checkPortShape(
  target: object,
  port: string,
  capabilities: ReadonlySet<string>,
): string[];
