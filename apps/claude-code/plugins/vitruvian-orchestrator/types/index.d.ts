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

export type Phase = "plan" | "design" | "delegate" | "review" | "close";

export type Tier = "lead" | "core" | "fast";

export type TaskState =
  "waiting" | "ready" | "running" | "review" | "returned" | "accepted";

export type Harness = "claude-code" | "antigravity" | "opencode";

export type RunStatus = "running" | "done" | "error";

export type RunRole = "lead" | "worker";

export type TokenCounts = {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
};

export type StepProgress = {
  done: number;
  total: number;
  note: string;
};

export type ReplanPoint = {
  at: number;
  total: number;
};

export type HistoryPoint = {
  at: number;
  remaining: number;
};

export type Task = {
  n: number;
  title: string;
  specialist: string;
  tier: Tier;
  after: number[];
  state: TaskState;
  round: number;
};

export type Run = {
  id: string;
  harness: Harness;
  agent: string;
  model: string;
  effort: string | null;
  title: string;
  taskN: number | null;
  startedAt: number;
  endedAt: number | null;
  status: RunStatus;
  tokens: TokenCounts;
  steps: StepProgress | null;
  contextPct: number | null;
  role: RunRole;
};

export type Flow = {
  title: string;
  phase: Phase;
  startedAt: number;
  closedAt: number | null;
  tasks: Task[];
  runs: Run[];
  replans: ReplanPoint[];
  history: HistoryPoint[];
};

export type PlanTaskInput = {
  title: string;
  specialist: string;
  tier: Tier;
  after?: number[];
};

export type BurnDown = {
  points: HistoryPoint[];
  replans: ReplanPoint[];
  ideal: HistoryPoint[];
};

export type TaskBoardRow = {
  n: number;
  title: string;
  specialist: string;
  tier: Tier;
  state: TaskState;
  round: number;
  after: number[];
  waitingOn: number[];
};

export type UnpricedSummary = {
  runs: number;
  tokens: number;
};

export type SpendSummary = {
  total: number;
  byModel: Record<string, number>;
  lead: number;
  workers: number;
  unpriced: UnpricedSummary;
};

export type FlowEvent = {
  type: string;
  at: number;
  title?: string;
  tasks?: PlanTaskInput[];
  phase?: Phase;
  id?: string;
  harness?: Harness;
  agent?: string;
  model?: string;
  effort?: string | null;
  role?: RunRole;
  tokens?: Partial<TokenCounts>;
  steps?: Partial<StepProgress> | null;
  contextPct?: number | null;
  status?: RunStatus;
  n?: number;
};

export type Panel = {
  isCompact: boolean;
  autoOpenedFor: string;
};

declare module "claude-code" {
  interface PluginState {
    "vitruvian-orchestrator": {
      flow: Flow | null;
      panel: Panel;
      now: number;
    };
  }
}
