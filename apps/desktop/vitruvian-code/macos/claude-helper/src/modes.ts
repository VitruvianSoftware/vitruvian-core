// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

export type ClaudeModeId =
  "default" | "acceptEdits" | "plan" | "auto" | "bypassPermissions";

export interface ClaudeModeDescriptor {
  readonly id: ClaudeModeId;
  readonly name: string;
  readonly description: string;
}

export const DEFAULT_CLAUDE_MODE: ClaudeModeId = "default";

export const CLAUDE_MODES: readonly ClaudeModeDescriptor[] = [
  {
    id: "default",
    name: "Ask before acting",
    description: "Prompt before running tools or making edits.",
  },
  {
    id: "acceptEdits",
    name: "Auto-accept edits",
    description:
      "Automatically accept file edits while asking for other actions.",
  },
  {
    id: "plan",
    name: "Plan",
    description: "Plan actions without modifying files or running commands.",
  },
  {
    id: "auto",
    name: "Auto",
    description:
      "Claude decides for itself what is safe to run, and asks only when unsure.",
  },
  {
    id: "bypassPermissions",
    name: "Full access",
    description: "Allow actions without prompting for permission.",
  },
] as const;

const CLAUDE_MODE_IDS: ReadonlySet<string> = new Set(
  CLAUDE_MODES.map((mode) => mode.id),
);

export function isClaudeModeId(value: string): value is ClaudeModeId {
  return CLAUDE_MODE_IDS.has(value);
}

export function requiresDangerousSkipFlag(mode: ClaudeModeId): boolean {
  return mode === "bypassPermissions";
}

/** Maps a mode to SDK permission options (`ClaudeAdapterV2.ts:2939-2944`). */
export function sdkPermissionOptionsForMode(mode: ClaudeModeId): {
  readonly permissionMode: ClaudeModeId;
  readonly allowDangerouslySkipPermissions?: true;
} {
  return {
    permissionMode: mode,
    ...(requiresDangerousSkipFlag(mode)
      ? { allowDangerouslySkipPermissions: true }
      : {}),
  };
}
