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

import { randomUUID } from "node:crypto";

import {
  agent,
  RequestError,
  type AgentApp,
  type AgentContext,
  type CancelNotification,
  type CloseSessionRequest,
  type CloseSessionResponse,
  type ContentBlock,
  type InitializeRequest,
  type InitializeResponse,
  type McpServer,
  type NewSessionRequest,
  type NewSessionResponse,
  type PromptRequest,
  type PromptResponse,
  type ResumeSessionRequest,
  type ResumeSessionResponse,
  type SessionConfigOption,
  type SessionConfigSelectOption,
  type SessionModeState,
  type SetSessionConfigOptionRequest,
  type SetSessionConfigOptionResponse,
  type SetSessionModeRequest,
  type SetSessionModeResponse,
} from "@agentclientprotocol/sdk";
import {
  forkSession,
  query,
  type CanUseTool,
  type ForkSessionOptions,
  type ForkSessionResult,
  type McpServerConfig,
  type McpServerStatus,
  type ModelInfo,
  type Options as SdkQueryOptions,
  type Query as SdkQuery,
  type SDKMessage,
  type SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";

import {
  classifySdkResult,
  createMappingState,
  mapSdkMessageToNotifications,
  resetTurnMappingState,
  type MappingState,
} from "./mapping.js";
import {
  CLAUDE_MODES,
  DEFAULT_CLAUDE_MODE,
  isClaudeModeId,
  requiresDangerousSkipFlag,
  sdkPermissionOptionsForMode,
  type ClaudeModeId,
} from "./modes.js";
import { createCanUseToolHandler } from "./permissions.js";
import { discoverClaudeSkills } from "./skills.js";
import { extractUsageLimit } from "./usageLimits.js";
import { detectClaudeVersion } from "./version.js";

const DEFAULT_SUPPORTED_MODELS_TIMEOUT_MS = 250;
const SUPPORTED_IMAGE_MIME_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/gif",
  "image/webp",
]);
const AUTH_MESSAGE_PATTERN =
  /authentication_failed|auth_required|not logged in|invalid api key|claude auth login|unauthorized/i;

export type QueryFn = (params: {
  prompt: string | AsyncIterable<SDKUserMessage>;
  options?: SdkQueryOptions;
}) => SdkQuery;

export type ForkFn = (
  sessionId: string,
  options?: ForkSessionOptions,
) => Promise<ForkSessionResult>;

export interface McpServerSecrets {
  readonly env?: Record<string, string>;
  readonly headers?: Record<string, string>;
}

export interface SecretsPayload {
  readonly env?: Record<string, string>;
  readonly mcpServers?: Record<string, McpServerSecrets>;
}

export interface VitruvianForkParams {
  readonly sessionId: string;
}

export interface VitruvianForkResult {
  readonly sessionId: string;
}

export interface VitruvianMcpStatusParams {
  readonly sessionId: string;
}

export interface VitruvianMcpStatusResult {
  readonly servers: McpServerStatus[];
}

export interface ClaudeHelperAgentOptions {
  readonly claudePath: string;
  readonly helperVersion?: string;
  readonly defaultMode?: ClaudeModeId;
  readonly baseEnv?: NodeJS.ProcessEnv;
  readonly queryFn?: QueryFn;
  readonly forkFn?: ForkFn;
  readonly detectVersionFn?: (claudePath: string) => Promise<string | null>;
  readonly discoverSkillsFn?: typeof discoverClaudeSkills;
  readonly extractUsageLimitFn?: typeof extractUsageLimit;
  readonly createCanUseToolFn?: typeof createCanUseToolHandler;
  readonly generateSessionIdFn?: () => string;
  readonly supportedModelsTimeoutMs?: number;
}

interface ActiveTurn {
  cancelled: boolean;
  readonly abortController: AbortController;
  readonly announcedUsageLimitResets: Set<string>;
  readonly resolve: (value: PromptResponse) => void;
  readonly reject: (reason: unknown) => void;
}

interface SessionRecord {
  readonly id: string;
  readonly cwd: string;
  readonly additionalDirectories?: readonly string[];
  mcpServers?: Record<string, McpServerConfig>;
  /** The ACP server list as the app sent it, so a reopen can re-apply the current secrets. */
  readonly acpMcpServers?: readonly McpServer[];
  readonly canUseTool: CanUseTool;
  readonly client: AgentContext;
  query: SdkQuery;
  inputQueue: AsyncPushQueue<SDKUserMessage>;
  env: Record<string, string | undefined>;
  readonly mappingState: MappingState;
  currentMode: ClaudeModeId;
  openedWithDangerousSkip: boolean;
  models: ModelInfo[];
  currentModel: string | undefined;
  modelExplicitlySet: boolean;
  activeTurn: ActiveTurn | null;
  /**
   * A mode that needs the query reopened (bypassPermissions), asked for while a
   * turn was running. Applied when the next prompt starts, as T3 Code applies a
   * new query policy at the start of a turn (ClaudeAdapterV2.ts ~11204-11260),
   * so a running turn and its waiting approvals are never cut off.
   */
  pendingReopenMode: ClaudeModeId | null;
  closed: boolean;
  dead: boolean;
}

/** Single-consumer async push queue backing streaming input to one long-lived SDK query. */
class AsyncPushQueue<T> implements AsyncIterable<T> {
  private readonly buffer: T[] = [];
  private readonly waiters: Array<(result: IteratorResult<T>) => void> = [];
  private closed = false;

  push(item: T): void {
    if (this.closed) {
      return;
    }
    const waiter = this.waiters.shift();
    if (waiter) {
      waiter({ value: item, done: false });
      return;
    }
    this.buffer.push(item);
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    while (this.waiters.length > 0) {
      const waiter = this.waiters.shift()!;
      waiter({ value: undefined as unknown as T, done: true });
    }
  }

  [Symbol.asyncIterator](): AsyncIterator<T> {
    return {
      next: (): Promise<IteratorResult<T>> => {
        if (this.buffer.length > 0) {
          return Promise.resolve({ value: this.buffer.shift()!, done: false });
        }
        if (this.closed) {
          return Promise.resolve({
            value: undefined as unknown as T,
            done: true,
          });
        }
        return new Promise<IteratorResult<T>>((resolve) => {
          this.waiters.push(resolve);
        });
      },
    };
  }
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseStringRecord(
  value: unknown,
  label: string,
): Record<string, string> {
  if (!isPlainRecord(value)) {
    throw RequestError.invalidParams(undefined, `${label} must be an object`);
  }
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(value)) {
    if (typeof v !== "string") {
      throw RequestError.invalidParams(
        undefined,
        `${label}.${k} must be a string`,
      );
    }
    out[k] = v;
  }
  return out;
}

export function parseSecretsParams(raw: unknown): SecretsPayload {
  if (!isPlainRecord(raw)) {
    throw RequestError.invalidParams(
      undefined,
      "secrets params must be an object",
    );
  }
  const env =
    raw.env !== undefined ? parseStringRecord(raw.env, "env") : undefined;
  let mcpServers: Record<string, McpServerSecrets> | undefined;
  if (raw.mcpServers !== undefined) {
    if (!isPlainRecord(raw.mcpServers)) {
      throw RequestError.invalidParams(
        undefined,
        "mcpServers must be an object",
      );
    }
    mcpServers = {};
    for (const [serverName, entry] of Object.entries(raw.mcpServers)) {
      if (!isPlainRecord(entry)) {
        throw RequestError.invalidParams(
          undefined,
          `mcpServers.${serverName} must be an object`,
        );
      }
      mcpServers[serverName] = {
        env:
          entry.env !== undefined
            ? parseStringRecord(entry.env, `mcpServers.${serverName}.env`)
            : undefined,
        headers:
          entry.headers !== undefined
            ? parseStringRecord(
                entry.headers,
                `mcpServers.${serverName}.headers`,
              )
            : undefined,
      };
    }
  }
  return { env, mcpServers };
}

export function mergeSecrets(
  existing: SecretsPayload,
  incoming: SecretsPayload,
): SecretsPayload {
  const env =
    existing.env !== undefined || incoming.env !== undefined
      ? { ...(existing.env ?? {}), ...(incoming.env ?? {}) }
      : undefined;

  let mcpServers: Record<string, McpServerSecrets> | undefined;
  if (existing.mcpServers !== undefined || incoming.mcpServers !== undefined) {
    mcpServers = {};
    if (existing.mcpServers !== undefined) {
      for (const [serverName, entry] of Object.entries(existing.mcpServers)) {
        mcpServers[serverName] = {
          ...(entry.env !== undefined ? { env: { ...entry.env } } : {}),
          ...(entry.headers !== undefined
            ? { headers: { ...entry.headers } }
            : {}),
        };
      }
    }
    if (incoming.mcpServers !== undefined) {
      for (const [serverName, entry] of Object.entries(incoming.mcpServers)) {
        const prev = mcpServers[serverName];
        const mergedEnv =
          prev?.env !== undefined || entry.env !== undefined
            ? { ...(prev?.env ?? {}), ...(entry.env ?? {}) }
            : undefined;
        const mergedHeaders =
          prev?.headers !== undefined || entry.headers !== undefined
            ? { ...(prev?.headers ?? {}), ...(entry.headers ?? {}) }
            : undefined;
        mcpServers[serverName] = {
          ...(mergedEnv !== undefined ? { env: mergedEnv } : {}),
          ...(mergedHeaders !== undefined ? { headers: mergedHeaders } : {}),
        };
      }
    }
  }

  return {
    ...(env !== undefined ? { env } : {}),
    ...(mcpServers !== undefined ? { mcpServers } : {}),
  };
}

function parseSessionIdParams(raw: unknown, method: string): string {
  if (
    !isPlainRecord(raw) ||
    typeof raw.sessionId !== "string" ||
    raw.sessionId.trim().length === 0
  ) {
    throw RequestError.invalidParams(
      undefined,
      `${method} requires a non-empty string sessionId`,
    );
  }
  return raw.sessionId;
}

export function parseVitruvianForkParams(raw: unknown): VitruvianForkParams {
  return { sessionId: parseSessionIdParams(raw, "_vitruvian/fork") };
}

export function parseVitruvianMcpStatusParams(
  raw: unknown,
): VitruvianMcpStatusParams {
  return { sessionId: parseSessionIdParams(raw, "_vitruvian/mcpStatus") };
}

/**
 * The Claude Code this SDK release bundles. Only that version or newer takes
 * MCP servers over stdin (`mcpServersDelivery: "initialize"`); older ones get
 * them on the command line, where any local user can read their env and
 * headers. A test keeps this in step with the SDK's package.json.
 */
export const MCP_INITIALIZE_MIN_CLAUDE_VERSION = "2.1.326";

/** At most this many sessions open at once, so a misbehaving client can't grow the map without end. */
export const MAX_OPEN_SESSIONS = 32;

/** Compares two `x.y.z` versions numerically; prerelease and build parts are ignored. */
export function compareClaudeVersions(a: string, b: string): number {
  const parts = (v: string) =>
    v
      .split(/[-+]/, 1)[0]
      .split(".")
      .map((n) => Number.parseInt(n, 10) || 0);
  const [pa, pb] = [parts(a), parts(b)];
  for (let i = 0; i < 3; i += 1) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d < 0 ? -1 : 1;
  }
  return 0;
}

/** True when any converted MCP server carries env values or headers. */
export function mcpServersCarrySecrets(
  servers: Record<string, McpServerConfig> | undefined,
): boolean {
  return Object.values(servers ?? {}).some((server) => {
    const record = server as { env?: object; headers?: object };
    return (
      Object.keys(record.env ?? {}).length > 0 ||
      Object.keys(record.headers ?? {}).length > 0
    );
  });
}

function collectSecretValues(secrets: SecretsPayload): string[] {
  const values = new Set<string>();
  const add = (record: Readonly<Record<string, string>> | undefined) => {
    for (const value of Object.values(record ?? {})) {
      if (value.length > 0) values.add(value);
    }
  };
  add(secrets.env);
  for (const server of Object.values(secrets.mcpServers ?? {})) {
    add(server.env);
    add(server.headers);
  }
  // Longest first, so a secret that contains another is redacted whole.
  return Array.from(values).sort((x, y) => y.length - x.length);
}

function redactSecretsInText(text: string, secrets: readonly string[]): string {
  let out = text;
  for (const secret of secrets) {
    out = out.split(secret).join("***");
  }
  return out;
}

function buildSdkEnv(
  baseEnv: NodeJS.ProcessEnv,
  secretEnv: Readonly<Record<string, string>> | undefined,
): Record<string, string | undefined> {
  return {
    ...baseEnv,
    ...(secretEnv ?? {}),
    // Applied after the user's own env so a stray value there cannot turn
    // the plan off. Both are needed: claude 2.1.331 only offers `TodoWrite`
    // (which the helper maps to the app's plan) when tasks are disabled; with
    // tasks on it offers TaskCreate/TaskUpdate/TaskList/TaskGet instead, and
    // the plan never shows.
    CLAUDE_CODE_ENABLE_TODO_TOOLS: "1",
    CLAUDE_CODE_ENABLE_TASKS: "0",
  };
}

/**
 * True for a `result` that ends a turn the app did not ask for. When a session
 * is resumed, Claude Code first runs a turn for the stale background-task
 * notification of the previous process and ends it with an empty `result`
 * (`origin.kind` "task-notification", zero turns) before the user's own prompt
 * runs. Settling the prompt on that one loses the real reply.
 */
function isUnsolicitedResult(message: SDKMessage): boolean {
  if (message.type !== "result") {
    return false;
  }
  const origin = (message as { readonly origin?: unknown }).origin;
  if (typeof origin !== "object" || origin === null) {
    return false;
  }
  return (origin as { readonly kind?: unknown }).kind === "task-notification";
}

function namedPairsToRecord(
  pairs: ReadonlyArray<{ readonly name: string; readonly value: string }>,
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const pair of pairs) {
    out[pair.name] = pair.value;
  }
  return out;
}

function convertMcpServers(
  acpServers: readonly McpServer[] | undefined,
  secretServers: Readonly<Record<string, McpServerSecrets>> | undefined,
): Record<string, McpServerConfig> | undefined {
  if (!acpServers || acpServers.length === 0) {
    return undefined;
  }
  const converted: Record<string, McpServerConfig> = {};
  for (const server of acpServers) {
    const serverSecrets = secretServers?.[server.name];
    if ("type" in server && (server.type === "http" || server.type === "sse")) {
      const headers = {
        ...namedPairsToRecord(server.headers),
        ...(serverSecrets?.headers ?? {}),
      };
      converted[server.name] = {
        type: server.type,
        url: server.url,
        ...(Object.keys(headers).length > 0 ? { headers } : {}),
      };
    } else if ("command" in server) {
      const env = {
        ...namedPairsToRecord(server.env),
        ...(serverSecrets?.env ?? {}),
      };
      converted[server.name] = {
        type: "stdio",
        command: server.command,
        args: [...server.args],
        ...(Object.keys(env).length > 0 ? { env } : {}),
      };
    }
  }
  return Object.keys(converted).length > 0 ? converted : undefined;
}

function extractRequestedMode(
  meta: Record<string, unknown> | null | undefined,
  fallback: ClaudeModeId,
): ClaudeModeId {
  if (!isPlainRecord(meta) || !isPlainRecord(meta.vitruvian)) {
    return fallback;
  }
  const rawMode = meta.vitruvian.modeId;
  return typeof rawMode === "string" && isClaudeModeId(rawMode)
    ? rawMode
    : fallback;
}

/** Converts ACP prompt blocks into a single streaming SDK user message (T3 `ClaudeAdapterV2.ts:2398-2440`). */
export function convertPromptBlocksToSdkUserMessage(
  blocks: readonly ContentBlock[],
): SDKUserMessage {
  const contentBlocks: Array<Record<string, unknown>> = [];

  for (const block of blocks) {
    switch (block.type) {
      case "text":
        contentBlocks.push({ type: "text", text: block.text });
        break;
      case "image":
        if (SUPPORTED_IMAGE_MIME_TYPES.has(block.mimeType)) {
          contentBlocks.push({
            type: "image",
            source: {
              type: "base64",
              media_type: block.mimeType,
              data: block.data,
            },
          });
        } else {
          contentBlocks.push({
            type: "text",
            text: block.uri
              ? `[Image (${block.mimeType}): ${block.uri}]`
              : `[Image (${block.mimeType})]`,
          });
        }
        break;
      case "resource": {
        const res = block.resource;
        const mimeLabel = res.mimeType ? ` (${res.mimeType})` : "";
        if ("text" in res) {
          contentBlocks.push({
            type: "text",
            text: `[Resource: ${res.uri}${mimeLabel}]\n${res.text}`,
          });
        } else if (res.mimeType === "application/pdf") {
          contentBlocks.push({
            type: "document",
            source: {
              type: "base64",
              media_type: "application/pdf",
              data: res.blob,
            },
          });
        } else if (
          res.mimeType &&
          SUPPORTED_IMAGE_MIME_TYPES.has(res.mimeType)
        ) {
          contentBlocks.push({
            type: "image",
            source: {
              type: "base64",
              media_type: res.mimeType,
              data: res.blob,
            },
          });
        } else {
          contentBlocks.push({
            type: "text",
            text: `[Binary resource: ${res.uri}${mimeLabel}]`,
          });
        }
        break;
      }
      case "resource_link": {
        const desc = block.description ? ` - ${block.description}` : "";
        contentBlocks.push({
          type: "text",
          text: `[Resource link: ${block.name} (${block.uri})${desc}]`,
        });
        break;
      }
      case "audio":
        contentBlocks.push({
          type: "text",
          text: `[Audio attachment (${block.mimeType})]`,
        });
        break;
    }
  }

  return {
    type: "user",
    message: {
      role: "user",
      content:
        contentBlocks.length > 0
          ? (contentBlocks as unknown as SDKUserMessage["message"]["content"])
          : "",
    },
    parent_tool_use_id: null,
  };
}

function buildModesState(session: SessionRecord): SessionModeState {
  return {
    currentModeId: session.currentMode,
    availableModes: CLAUDE_MODES.map((m) => ({
      id: m.id,
      name: m.name,
      description: m.description,
    })),
  };
}

function buildConfigOptions(session: SessionRecord): SessionConfigOption[] {
  const modeOption: SessionConfigOption = {
    id: "mode",
    name: "Mode",
    category: "mode",
    type: "select",
    currentValue: session.currentMode,
    options: CLAUDE_MODES.map((m) => ({
      value: m.id,
      name: m.name,
      description: m.description,
    })),
  };

  const options: SessionConfigOption[] = [modeOption];
  const currentModel = session.currentModel ?? session.models[0]?.value;
  if (session.models.length > 0 || currentModel !== undefined) {
    const modelChoices: SessionConfigSelectOption[] = session.models.map(
      (model) => ({
        value: model.value,
        name: model.displayName || model.value,
        ...(model.description ? { description: model.description } : {}),
      }),
    );
    if (
      currentModel &&
      !modelChoices.some((choice) => choice.value === currentModel)
    ) {
      modelChoices.push({ value: currentModel, name: currentModel });
    }
    if (currentModel && modelChoices.length > 0) {
      options.push({
        id: "model",
        name: "Model",
        category: "model",
        type: "select",
        currentValue: currentModel,
        options: modelChoices,
      });
    }
  }

  return options;
}

function toRpcError(error: unknown): RequestError {
  if (error instanceof RequestError) {
    return error;
  }
  const message = error instanceof Error ? error.message : String(error);
  if (AUTH_MESSAGE_PATTERN.test(message)) {
    return RequestError.authRequired(
      { reason: "auth_required" },
      "Run `claude auth login` in your terminal and try again.",
    );
  }
  return new RequestError(-32603, message || "Claude SDK error");
}

export class ClaudeHelperAgent {
  readonly claudePath: string;
  readonly helperVersion: string;
  readonly defaultMode: ClaudeModeId;
  readonly baseEnv: NodeJS.ProcessEnv;
  readonly queryFn: QueryFn;
  readonly forkFn: ForkFn;
  readonly detectVersionFn: (claudePath: string) => Promise<string | null>;
  readonly discoverSkillsFn: typeof discoverClaudeSkills;
  readonly extractUsageLimitFn: typeof extractUsageLimit;
  readonly createCanUseToolFn: typeof createCanUseToolHandler;
  readonly generateSessionIdFn: () => string;
  readonly supportedModelsTimeoutMs: number;
  private secrets: SecretsPayload = {};
  /** The `claude` version found at initialize; null until then or when `--version` failed. */
  private claudeVersion: string | null = null;
  private readonly sessions = new Map<string, SessionRecord>();

  constructor(options: ClaudeHelperAgentOptions) {
    this.claudePath = options.claudePath;
    this.helperVersion = options.helperVersion ?? "0.1.0";
    this.defaultMode = options.defaultMode ?? DEFAULT_CLAUDE_MODE;
    this.baseEnv = options.baseEnv ?? process.env;
    this.queryFn = options.queryFn ?? query;
    this.forkFn = options.forkFn ?? forkSession;
    this.detectVersionFn = options.detectVersionFn ?? detectClaudeVersion;
    this.discoverSkillsFn = options.discoverSkillsFn ?? discoverClaudeSkills;
    this.extractUsageLimitFn = options.extractUsageLimitFn ?? extractUsageLimit;
    this.createCanUseToolFn =
      options.createCanUseToolFn ?? createCanUseToolHandler;
    this.generateSessionIdFn = options.generateSessionIdFn ?? randomUUID;
    this.supportedModelsTimeoutMs =
      options.supportedModelsTimeoutMs ?? DEFAULT_SUPPORTED_MODELS_TIMEOUT_MS;
  }

  async initialize(params: InitializeRequest): Promise<InitializeResponse> {
    void params;
    let claudeVersion: string | null = null;
    try {
      claudeVersion = await this.detectVersionFn(this.claudePath);
    } catch {
      claudeVersion = null;
    }
    this.claudeVersion = claudeVersion;
    return {
      protocolVersion: 1,
      agentInfo: {
        name: "vitruvian-claude-helper",
        version: this.helperVersion,
      },
      agentCapabilities: {
        loadSession: false,
        promptCapabilities: {
          image: true,
          embeddedContext: true,
        },
        mcpCapabilities: {
          http: true,
          sse: false,
        },
        sessionCapabilities: {
          resume: {},
          close: {},
        },
      },
      authMethods: [],
      _meta: {
        vitruvian: {
          claudeVersion,
          minClaudeVersionForMcpSecrets: MCP_INITIALIZE_MIN_CLAUDE_VERSION,
        },
      },
    };
  }

  async setSecrets(params: SecretsPayload): Promise<Record<string, never>> {
    this.secrets = mergeSecrets(this.secrets, params);
    return {};
  }

  async newSession(
    params: NewSessionRequest,
    client: AgentContext,
  ): Promise<NewSessionResponse> {
    const sessionId = this.generateSessionIdFn();
    const session = await this.openSession({
      sessionId,
      resume: false,
      cwd: params.cwd,
      mcpServers: params.mcpServers,
      additionalDirectories: params.additionalDirectories,
      meta: params._meta,
      client,
    });
    return {
      sessionId: session.id,
      modes: buildModesState(session),
      configOptions: buildConfigOptions(session),
    };
  }

  async resumeSession(
    params: ResumeSessionRequest,
    client: AgentContext,
  ): Promise<ResumeSessionResponse> {
    const session = await this.openSession({
      sessionId: params.sessionId,
      resume: true,
      cwd: params.cwd,
      mcpServers: params.mcpServers,
      additionalDirectories: params.additionalDirectories,
      meta: params._meta,
      client,
    });
    return {
      modes: buildModesState(session),
      configOptions: buildConfigOptions(session),
    };
  }

  async prompt(
    params: PromptRequest,
    client: AgentContext,
  ): Promise<PromptResponse> {
    void client;
    const session = this.requireSession(params.sessionId);
    if (session.activeTurn) {
      throw RequestError.invalidRequest(
        { sessionId: params.sessionId },
        "A prompt turn is already in progress for this session",
      );
    }

    if (session.pendingReopenMode !== null) {
      const mode = session.pendingReopenMode;
      session.pendingReopenMode = null;
      this.reopenSessionQuery(session, mode);
    }

    resetTurnMappingState(session.mappingState);
    const abortController = new AbortController();
    let currentTurn: ActiveTurn | null = null;

    return await new Promise<PromptResponse>((resolve, reject) => {
      currentTurn = {
        cancelled: false,
        abortController,
        announcedUsageLimitResets: new Set<string>(),
        resolve,
        reject,
      };
      session.activeTurn = currentTurn;
      try {
        const sdkMessage = convertPromptBlocksToSdkUserMessage(params.prompt);
        session.inputQueue.push(sdkMessage);
      } catch (error) {
        if (session.activeTurn === currentTurn) {
          session.activeTurn = null;
        }
        reject(toRpcError(error));
      }
    }).finally(() => {
      if (session.activeTurn === currentTurn) {
        session.activeTurn = null;
      }
    });
  }

  async cancel(params: CancelNotification): Promise<void> {
    const session = this.sessions.get(params.sessionId);
    if (!session || session.closed) {
      return;
    }
    const turn = session.activeTurn;
    if (turn) {
      turn.cancelled = true;
      turn.abortController.abort();
    }
    if (!session.dead) {
      try {
        await session.query.interrupt();
      } catch {
        // Ignore interrupt errors; still settle the active turn as cancelled below.
      }
    }
    if (turn && session.activeTurn === turn) {
      session.activeTurn = null;
      turn.resolve({ stopReason: "cancelled" });
    }
  }

  private async notifyModeChange(
    session: SessionRecord,
    client: AgentContext,
  ): Promise<SessionConfigOption[]> {
    await client.notify("session/update", {
      sessionId: session.id,
      update: {
        sessionUpdate: "current_mode_update",
        currentModeId: session.currentMode,
      },
    });
    const configOptions = buildConfigOptions(session);
    await client.notify("session/update", {
      sessionId: session.id,
      update: {
        sessionUpdate: "config_option_update",
        configOptions,
      },
    });
    return configOptions;
  }

  async setMode(
    params: SetSessionModeRequest,
    client: AgentContext,
  ): Promise<SetSessionModeResponse> {
    const session = this.requireSession(params.sessionId);
    if (!isClaudeModeId(params.modeId)) {
      throw RequestError.invalidParams(
        { modeId: params.modeId },
        `Unsupported modeId: ${params.modeId}`,
      );
    }
    await this.applyPermissionMode(session, params.modeId);
    await this.notifyModeChange(session, client);
    return {};
  }

  async setConfigOption(
    params: SetSessionConfigOptionRequest,
    client: AgentContext,
  ): Promise<SetSessionConfigOptionResponse> {
    const session = this.requireSession(params.sessionId);
    if (params.configId === "mode") {
      if (typeof params.value !== "string" || !isClaudeModeId(params.value)) {
        throw RequestError.invalidParams(
          { configId: params.configId, value: params.value },
          `Unsupported mode value: ${String(params.value)}`,
        );
      }
      await this.applyPermissionMode(session, params.value);
      const configOptions = await this.notifyModeChange(session, client);
      return { configOptions };
    } else if (params.configId === "model") {
      if (
        typeof params.value !== "string" ||
        params.value.trim().length === 0
      ) {
        throw RequestError.invalidParams(
          { configId: params.configId, value: params.value },
          "model config value must be a non-empty string",
        );
      }
      await session.query.setModel(params.value);
      session.currentModel = params.value;
      session.modelExplicitlySet = true;
    } else {
      throw RequestError.invalidParams(
        { configId: params.configId },
        `Unsupported config option: ${params.configId}`,
      );
    }

    const configOptions = buildConfigOptions(session);
    await client.notify("session/update", {
      sessionId: session.id,
      update: {
        sessionUpdate: "config_option_update",
        configOptions,
      },
    });
    return { configOptions };
  }

  async closeSession(
    params: CloseSessionRequest,
  ): Promise<CloseSessionResponse> {
    const session = this.sessions.get(params.sessionId);
    if (!session) {
      return {};
    }
    this.terminateSession(session);
    return {};
  }

  async closeAllSessions(): Promise<void> {
    for (const session of Array.from(this.sessions.values())) {
      this.terminateSession(session);
    }
  }

  async fork(params: VitruvianForkParams): Promise<VitruvianForkResult> {
    const session = this.sessions.get(params.sessionId);
    const result = await this.forkFn(
      params.sessionId,
      session ? { dir: session.cwd } : undefined,
    );
    return { sessionId: result.sessionId };
  }

  async mcpStatus(
    params: VitruvianMcpStatusParams,
  ): Promise<VitruvianMcpStatusResult> {
    const session = this.requireSession(params.sessionId);
    const rawServers = await session.query.mcpServerStatus();
    // Each status carries the server's config (with its env and headers), and
    // its error text may echo them: drop the config and redact the errors.
    const secretValues = collectSecretValues(this.secrets);
    const servers = rawServers.map((server) => {
      const {
        config: _config,
        error,
        ...rest
      } = server as typeof server & {
        config?: unknown;
        error?: unknown;
      };
      void _config;
      return {
        ...rest,
        ...(typeof error === "string"
          ? { error: redactSecretsInText(error, secretValues) }
          : {}),
      } as typeof server;
    });
    return { servers };
  }

  private requireSession(sessionId: string): SessionRecord {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw RequestError.sessionNotFound(sessionId);
    }
    if (session.dead) {
      throw new RequestError(
        -32603,
        "Session ended; use session/resume to continue.",
        { sessionId: session.id, reason: "session_ended" },
      );
    }
    return session;
  }

  /**
   * Sends MCP servers over stdin when this `claude` supports it. An older one
   * gets them on the command line only when none carries env or headers;
   * otherwise opening the session fails with an upgrade message, so a secret
   * never reaches argv.
   */
  private mcpServersDelivery(
    servers: Record<string, McpServerConfig>,
  ): "initialize" | "argv" {
    if (
      this.claudeVersion !== null &&
      compareClaudeVersions(
        this.claudeVersion,
        MCP_INITIALIZE_MIN_CLAUDE_VERSION,
      ) >= 0
    ) {
      return "initialize";
    }
    if (mcpServersCarrySecrets(servers)) {
      throw RequestError.invalidRequest(
        { minClaudeVersion: MCP_INITIALIZE_MIN_CLAUDE_VERSION },
        `Update Claude Code to ${MCP_INITIALIZE_MIN_CLAUDE_VERSION} or newer to use MCP servers that need secrets (run \`claude update\`). Found ${this.claudeVersion ?? "an unknown version"}.`,
      );
    }
    return "argv";
  }

  private terminateSession(session: SessionRecord): void {
    this.sessions.delete(session.id);
    session.closed = true;
    if (session.activeTurn) {
      const turn = session.activeTurn;
      session.activeTurn = null;
      turn.cancelled = true;
      turn.abortController.abort();
      turn.resolve({ stopReason: "cancelled" });
    }
    session.inputQueue.close();
    try {
      session.query.close();
    } catch {
      // Ignore query teardown errors when shutting down.
    }
  }

  private buildQueryOptions(input: {
    readonly sessionId: string;
    readonly resume: boolean;
    readonly cwd: string;
    readonly mode: ClaudeModeId;
    readonly canUseTool: CanUseTool;
    readonly env: Record<string, string | undefined>;
    readonly additionalDirectories?: readonly string[];
    readonly mcpServers?: Record<string, McpServerConfig>;
    readonly model?: string;
  }): SdkQueryOptions {
    return {
      cwd: input.cwd,
      pathToClaudeCodeExecutable: this.claudePath,
      includePartialMessages: true,
      settingSources: ["user", "project", "local"],
      canUseTool: input.canUseTool,
      ...sdkPermissionOptionsForMode(input.mode),
      ...(input.resume
        ? { resume: input.sessionId }
        : { sessionId: input.sessionId }),
      ...(input.additionalDirectories && input.additionalDirectories.length > 0
        ? { additionalDirectories: [...input.additionalDirectories] }
        : {}),
      ...(input.mcpServers
        ? {
            mcpServers: input.mcpServers,
            mcpServersDelivery: this.mcpServersDelivery(input.mcpServers),
          }
        : {}),
      ...(input.model ? { model: input.model } : {}),
      env: input.env,
    };
  }

  private async applyPermissionMode(
    session: SessionRecord,
    mode: ClaudeModeId,
  ): Promise<void> {
    if (requiresDangerousSkipFlag(mode) && !session.openedWithDangerousSkip) {
      if (session.activeTurn) {
        // Never cut a running turn off: reopen when the next prompt starts.
        session.pendingReopenMode = mode;
      } else {
        this.reopenSessionQuery(session, mode);
      }
    } else {
      session.pendingReopenMode = null;
      await session.query.setPermissionMode(mode);
    }
    session.currentMode = mode;
  }

  private reopenSessionQuery(session: SessionRecord, mode: ClaudeModeId): void {
    // Secrets the app sent after the session opened apply to the new process.
    session.env = buildSdkEnv(this.baseEnv, this.secrets.env);
    session.mcpServers = convertMcpServers(
      session.acpMcpServers,
      this.secrets.mcpServers,
    );
    const newInputQueue = new AsyncPushQueue<SDKUserMessage>();
    const queryOptions = this.buildQueryOptions({
      sessionId: session.id,
      resume: true,
      cwd: session.cwd,
      mode,
      canUseTool: session.canUseTool,
      env: session.env,
      additionalDirectories: session.additionalDirectories,
      mcpServers: session.mcpServers,
      model: session.modelExplicitlySet ? session.currentModel : undefined,
    });
    const newQuery = this.queryFn({
      prompt: newInputQueue,
      options: queryOptions,
    });

    const oldQuery = session.query;
    const oldInputQueue = session.inputQueue;

    // Swap before closing the old query so the old pumpQueryOutput exits
    // without marking the session dead or touching the new query.
    session.query = newQuery;
    session.inputQueue = newInputQueue;
    session.openedWithDangerousSkip = requiresDangerousSkipFlag(mode);
    session.dead = false;

    if (session.activeTurn) {
      const turn = session.activeTurn;
      session.activeTurn = null;
      turn.cancelled = true;
      turn.abortController.abort();
      turn.resolve({ stopReason: "cancelled" });
    }

    oldInputQueue.close();
    try {
      oldQuery.close();
    } catch {
      // Ignore old query teardown errors when reopening.
    }

    void this.pumpQueryOutput(session, newQuery);
  }

  private async openSession(input: {
    readonly sessionId: string;
    readonly resume: boolean;
    readonly cwd: string;
    readonly mcpServers?: readonly McpServer[];
    readonly additionalDirectories?: readonly string[];
    readonly meta?: Record<string, unknown> | null;
    readonly client: AgentContext;
  }): Promise<SessionRecord> {
    const existing = this.sessions.get(input.sessionId);
    if (!existing && this.sessions.size >= MAX_OPEN_SESSIONS) {
      throw RequestError.invalidRequest(
        { maxOpenSessions: MAX_OPEN_SESSIONS },
        `Too many open sessions (${MAX_OPEN_SESSIONS}); close one first.`,
      );
    }
    if (existing) {
      if (input.resume && existing.dead) {
        existing.closed = true;
        existing.inputQueue.close();
        this.sessions.delete(input.sessionId);
      } else {
        throw RequestError.invalidParams(
          { sessionId: input.sessionId },
          `Session already open: ${input.sessionId}`,
        );
      }
    }

    const initialMode = extractRequestedMode(input.meta, this.defaultMode);
    const env = buildSdkEnv(this.baseEnv, this.secrets.env);
    const mcpServers = convertMcpServers(
      input.mcpServers,
      this.secrets.mcpServers,
    );
    const inputQueue = new AsyncPushQueue<SDKUserMessage>();

    const baseCanUseTool = this.createCanUseToolFn({
      sessionId: input.sessionId,
      client: input.client,
    });

    let sessionRef: SessionRecord | undefined;
    const canUseTool: CanUseTool = (toolName, toolInput, toolOptions) => {
      const turnSignal = sessionRef?.activeTurn?.abortController.signal;
      const signal = turnSignal
        ? AbortSignal.any([toolOptions.signal, turnSignal])
        : toolOptions.signal;
      return baseCanUseTool(toolName, toolInput, {
        ...toolOptions,
        signal,
      });
    };

    const queryOptions = this.buildQueryOptions({
      sessionId: input.sessionId,
      resume: input.resume,
      cwd: input.cwd,
      mode: initialMode,
      canUseTool,
      env,
      additionalDirectories: input.additionalDirectories,
      mcpServers,
    });

    const sdkQuery = this.queryFn({
      prompt: inputQueue,
      options: queryOptions,
    });

    const session: SessionRecord = {
      id: input.sessionId,
      cwd: input.cwd,
      ...(input.additionalDirectories && input.additionalDirectories.length > 0
        ? { additionalDirectories: [...input.additionalDirectories] }
        : {}),
      ...(mcpServers ? { mcpServers } : {}),
      ...(input.mcpServers ? { acpMcpServers: input.mcpServers } : {}),
      canUseTool,
      client: input.client,
      query: sdkQuery,
      inputQueue,
      env,
      mappingState: createMappingState(),
      currentMode: initialMode,
      openedWithDangerousSkip: requiresDangerousSkipFlag(initialMode),
      models: [],
      currentModel: undefined,
      modelExplicitlySet: false,
      activeTurn: null,
      pendingReopenMode: null,
      closed: false,
      dead: false,
    };
    sessionRef = session;

    this.sessions.set(session.id, session);
    void this.pumpQueryOutput(session, sdkQuery);
    await this.loadInitialSupportedModels(session);

    return session;
  }

  private async loadInitialSupportedModels(
    session: SessionRecord,
  ): Promise<void> {
    const targetQuery = session.query;
    if (typeof targetQuery.supportedModels !== "function") {
      return;
    }

    const modelsPromise = targetQuery
      .supportedModels()
      .then((models) => ({ settled: true as const, models }))
      .catch(() => ({ settled: true as const, models: [] as ModelInfo[] }));

    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeoutPromise = new Promise<{ readonly settled: false }>(
      (resolve) => {
        timer = setTimeout(
          () => resolve({ settled: false }),
          this.supportedModelsTimeoutMs,
        );
        timer.unref?.();
      },
    );

    const raceResult = await Promise.race([modelsPromise, timeoutPromise]);
    if (timer !== undefined) {
      clearTimeout(timer);
    }

    if (raceResult.settled) {
      if (
        !session.closed &&
        !session.dead &&
        session.query === targetQuery &&
        raceResult.models.length > 0
      ) {
        session.models = raceResult.models;
        session.currentModel ??= raceResult.models[0].value;
      }
      return;
    }

    // Wait in the background; once models arrive on an open session, emit config_option_update.
    void modelsPromise.then(async ({ models }) => {
      if (
        session.closed ||
        session.dead ||
        session.query !== targetQuery ||
        models.length === 0
      ) {
        return;
      }
      session.models = models;
      session.currentModel ??= models[0].value;
      try {
        await session.client.notify("session/update", {
          sessionId: session.id,
          update: {
            sessionUpdate: "config_option_update",
            configOptions: buildConfigOptions(session),
          },
        });
      } catch {
        // Ignore notification failures if the connection has already closed.
      }
    });
  }

  private async pumpQueryOutput(
    session: SessionRecord,
    sdkQuery: SdkQuery,
  ): Promise<void> {
    let threw = false;
    let exitError: unknown = undefined;
    try {
      for await (const sdkMessage of sdkQuery) {
        if (session.closed || session.query !== sdkQuery) {
          return;
        }

        let diskCommands = undefined;
        if (sdkMessage.type === "system" && sdkMessage.subtype === "init") {
          if (
            !session.modelExplicitlySet &&
            typeof sdkMessage.model === "string" &&
            sdkMessage.model.length > 0
          ) {
            session.currentModel ??= sdkMessage.model;
          }
          diskCommands = await this.discoverSkillsFn({
            cwd: session.cwd,
            configDir: session.env.CLAUDE_CONFIG_DIR,
            additionalDirectories: session.additionalDirectories,
          }).catch(() => []);
        }

        const notifications = mapSdkMessageToNotifications(
          session.id,
          sdkMessage,
          session.mappingState,
          diskCommands ? { diskCommands } : undefined,
        );

        for (const notification of notifications) {
          if (session.closed || session.query !== sdkQuery) {
            return;
          }
          await session.client.notify("session/update", notification);
        }

        const usageLimit = this.extractUsageLimitFn(session.id, sdkMessage);
        if (usageLimit && !session.closed && session.query === sdkQuery) {
          const resetKey = usageLimit.resetsAt ?? "__null__";
          const announced = session.activeTurn?.announcedUsageLimitResets;
          let shouldNotify = true;
          if (announced) {
            const hasNonNull = Array.from(announced).some(
              (k) => k !== "__null__",
            );
            if (
              announced.has(resetKey) ||
              (usageLimit.resetsAt === null && hasNonNull)
            ) {
              shouldNotify = false;
            } else {
              announced.add(resetKey);
            }
          }
          if (shouldNotify) {
            await session.client.notify("_vitruvian/usageLimit", usageLimit);
          }
        }

        if (
          sdkMessage.type === "result" &&
          !isUnsolicitedResult(sdkMessage) &&
          session.activeTurn &&
          !session.closed &&
          session.query === sdkQuery
        ) {
          const turn = session.activeTurn;
          session.activeTurn = null;
          const outcome = classifySdkResult(
            sdkMessage,
            session.mappingState,
            turn.cancelled,
          );
          if (outcome.kind === "stop") {
            turn.resolve({ stopReason: outcome.stopReason });
          } else {
            turn.reject(outcome.error);
          }
        }
      }
    } catch (error) {
      threw = true;
      exitError = error;
    } finally {
      if (!session.closed && session.query === sdkQuery) {
        session.dead = true;
        session.inputQueue.close();
        if (session.activeTurn) {
          const turn = session.activeTurn;
          session.activeTurn = null;
          if (turn.cancelled) {
            turn.resolve({ stopReason: "cancelled" });
          } else {
            turn.abortController.abort();
            if (threw) {
              turn.reject(toRpcError(exitError));
            } else {
              turn.reject(
                new RequestError(
                  -32603,
                  "Claude SDK query ended before producing a result",
                ),
              );
            }
          }
        }
      }
    }
  }
}

export function createClaudeHelperApp(options: ClaudeHelperAgentOptions): {
  readonly app: AgentApp;
  readonly helper: ClaudeHelperAgent;
} {
  const helper = new ClaudeHelperAgent(options);
  const app = agent({ name: "vitruvian-claude-helper" })
    .onRequest("initialize", (ctx) => helper.initialize(ctx.params))
    .onRequest("_vitruvian/secrets", parseSecretsParams, (ctx) =>
      helper.setSecrets(ctx.params),
    )
    .onRequest("session/new", (ctx) =>
      helper.newSession(ctx.params, ctx.client),
    )
    .onRequest("session/resume", (ctx) =>
      helper.resumeSession(ctx.params, ctx.client),
    )
    .onRequest("session/prompt", (ctx) => helper.prompt(ctx.params, ctx.client))
    .onNotification("session/cancel", (ctx) => helper.cancel(ctx.params))
    .onRequest("session/set_mode", (ctx) =>
      helper.setMode(ctx.params, ctx.client),
    )
    .onRequest("session/set_config_option", (ctx) =>
      helper.setConfigOption(ctx.params, ctx.client),
    )
    .onRequest("session/close", (ctx) => helper.closeSession(ctx.params))
    .onRequest("_vitruvian/fork", parseVitruvianForkParams, (ctx) =>
      helper.fork(ctx.params),
    )
    .onRequest("_vitruvian/mcpStatus", parseVitruvianMcpStatusParams, (ctx) =>
      helper.mcpStatus(ctx.params),
    );

  return { app, helper };
}
