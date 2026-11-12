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

export type PostKind = "note" | "question" | "defect" | "result";

export type PauseReason = "quota" | "error";

export type PauseInfo = {
  reason: PauseReason;
  detail?: string;
};

export type MemberState =
  "working" | "waiting" | "paused" | "killed" | "retired";

export type Post = {
  seq: number;
  at: number;
  from: string;
  text: string;
  to: string[];
  kind: PostKind;
  replyTo: number | null;
  channel: string;
  runId?: string;
};

export type MemberRow = {
  id: string;
  agent: string;
  state: MemberState;
  reason?: PauseReason;
  detail?: string;
  taskN?: number;
  model: string;
  delegate?: string;
  taskModel?: string;
  worktree?: string;
  lastPostSeq?: number;
  lastActivityAt: number;
};

export type MentionGraphNode = {
  id: string;
  posts: number;
};

export type MentionGraphEdge = {
  from: string;
  to: string;
  count: number;
};

export type MentionGraph = {
  nodes: MentionGraphNode[];
  edges: MentionGraphEdge[];
};

export type MembersView = {
  active: MemberRow[];
  standingBy: MemberRow[];
  retired: MemberRow[];
};

export type ChannelInfo = {
  name: string;
  archived: boolean;
};

export type OverviewMember = {
  agent: string;
  state: MemberState;
  line: string;
};

export type OpenQuestion = {
  seq: number;
  from: string;
  text: string;
};

export type OpenDefect = {
  seq: number;
  from: string;
  to: string[];
  text: string;
};

export type OverviewView = {
  members: OverviewMember[];
  openQuestions: OpenQuestion[];
  openDefects: OpenDefect[];
  stalls: StallRow[];
};

export type PendingWake = {
  seq: number;
  target: string;
  runId?: string;
  from: string;
  excerpt: string;
};

export type TokenCounts = {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
};

export type DelegateTokenCounts = {
  input: number;
  output: number;
  thinking: number;
  cacheRead: number;
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
  model?: string;
  warning?: string;
  worktree?: string;
};

export type Run = {
  id: string;
  harness: Harness;
  agent: string;
  model: string;
  effort: string | null;
  delegate: string | null;
  worktree?: string;
  title: string;
  taskN: number | null;
  startedAt: number;
  /** When the run last did anything; absent on runs an older version stored. */
  lastActivityAt?: number;
  /** True while the run is held on work it started (a background job). */
  waiting?: boolean;
  endedAt: number | null;
  status: RunStatus;
  tokens: TokenCounts;
  delegateTokens?: DelegateTokenCounts | null;
  steps: StepProgress | null;
  contextPct: number | null;
  role: RunRole;
  paused?: PauseInfo | null;
  memberState?: "killed" | "retired" | null;
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
  posts?: Post[];
  postsDropped?: number;
  woken?: string[];
  hasMemberEvents?: boolean;
  channels?: ChannelInfo[];
};

export type PlanTaskInput = {
  title: string;
  specialist: string;
  tier: Tier;
  after?: number[];
  model?: string;
  worktree?: string;
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
  model?: string;
  warning?: string;
  worktree?: string;
};

export type UnpricedSummary = {
  runs: number;
  tokens: number;
};

export type DelegatedSummary = {
  runs: number;
  unpriced: number;
  byModel: Record<string, number>;
};

export type SpendSummary = {
  total: number;
  byModel: Record<string, number>;
  lead: number;
  workers: number;
  unpriced: UnpricedSummary;
  delegated: DelegatedSummary;
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
  delegate?: string | null;
  worktree?: string;
  role?: RunRole;
  tokens?: Partial<TokenCounts>;
  delegateTokens?: Partial<DelegateTokenCounts> | null;
  steps?: Partial<StepProgress> | null;
  contextPct?: number | null;
  status?: RunStatus;
  n?: number;
  waiting?: boolean;
  from?: string;
  text?: string;
  to?: string[];
  kind?: PostKind;
  replyTo?: number;
  channel?: string;
  action?: "create" | "archive";
  name?: string;
  runId?: string;
  reason?: PauseReason;
  detail?: string;
  seq?: number;
  target?: string;
};

export type StallState = "active" | "quiet" | "waiting" | "stalled";

export type StallRow = {
  id: string;
  agent: string;
  title: string;
  taskN: number | null;
  lastActivityAt: number;
  idleMs: number;
  state: StallState;
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
