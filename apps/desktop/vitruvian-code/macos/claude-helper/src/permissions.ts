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

import {
  RequestError,
  type AgentContext,
  type CreateElicitationRequest,
  type CreateElicitationResponse,
  type ElicitationPropertySchema,
  type EnumOption,
  type PermissionOption,
  type RequestPermissionRequest,
  type RequestPermissionResponse,
} from "@agentclientprotocol/sdk";
import type {
  CanUseTool,
  PermissionResult,
  PermissionUpdate,
} from "@anthropic-ai/claude-agent-sdk";

import {
  extractToolCallLocations,
  formatToolCallTitle,
  mapToolKind,
} from "./mapping.js";

export const ALLOW_ONCE_OPTION_ID = "allow_once";
export const ALLOW_ALWAYS_OPTION_ID = "allow_always";
export const REJECT_ONCE_OPTION_ID = "reject_once";

export const REJECTED_MESSAGE = "The user rejected this.";
export const CANCELLED_MESSAGE = "The user cancelled this request.";
export const DECLINED_QUESTION_MESSAGE = "The user declined to answer.";

export interface PermissionHandlerOptions {
  readonly sessionId: string;
  readonly client: AgentContext;
}

export interface AskUserQuestionOption {
  readonly label: string;
  readonly description?: string;
}

export interface ParsedAskUserQuestion {
  readonly id: string;
  readonly header: string;
  readonly question: string;
  readonly options: readonly AskUserQuestionOption[];
  readonly multiSelect: boolean;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * The rules an "always allow" answer adds, as T3 Code builds them for its
 * "Always allow this session" (`ClaudeAdapterV2.ts:3834-3852`): the SDK's
 * suggestions with every destination set to `session`, so nothing is written
 * to the user's settings files, or a rule for the tool itself when the SDK
 * gave none. `setMode` suggestions are dropped so mode changes come only from
 * the app. That part is stricter than T3 on purpose: T3 drops them only under
 * a managed permission ceiling (`ClaudeAdapterV2.ts:3808-3819`), but here the
 * app's chosen mode is always the ceiling.
 */
export function toSessionPermissionUpdates(
  toolName: string,
  suggestions?: readonly PermissionUpdate[],
): PermissionUpdate[] {
  const updates = (Array.isArray(suggestions) ? suggestions : [])
    .filter((suggestion) => suggestion.type !== "setMode")
    .map((suggestion): PermissionUpdate => ({
      ...suggestion,
      destination: "session",
    }));
  if (updates.length > 0) {
    return updates;
  }
  return [
    {
      type: "addRules",
      rules: [{ toolName }],
      behavior: "allow",
      destination: "session",
    },
  ];
}

/** Builds ACP permission options. "Always allow this session" is always offered, as in T3 Code. */
export function buildPermissionOptions(): PermissionOption[] {
  const options: PermissionOption[] = [
    {
      optionId: ALLOW_ONCE_OPTION_ID,
      name: "Allow",
      kind: "allow_once",
    },
    {
      optionId: ALLOW_ALWAYS_OPTION_ID,
      name: "Always allow this session",
      kind: "allow_always",
    },
  ];
  options.push({
    optionId: REJECT_ONCE_OPTION_ID,
    name: "Reject",
    kind: "reject_once",
  });
  return options;
}

/** Builds an ACP `session/request_permission` request from an SDK `canUseTool` invocation (T3 `ClaudeAdapterV2.ts:10819-10840`). */
export function buildPermissionRequest(
  sessionId: string,
  toolName: string,
  toolInput: Record<string, unknown>,
  options: {
    readonly toolUseID?: string;
    readonly blockedPath?: string;
    readonly suggestions?: readonly PermissionUpdate[];
  },
): RequestPermissionRequest {
  const locations =
    extractToolCallLocations(toolInput) ??
    (typeof options.blockedPath === "string" &&
    options.blockedPath.trim().length > 0
      ? [{ path: options.blockedPath }]
      : undefined);

  return {
    sessionId,
    toolCall: {
      toolCallId: options.toolUseID || "tool_unknown",
      title: formatToolCallTitle(toolName, toolInput),
      kind: mapToolKind(toolName),
      status: "pending",
      rawInput: toolInput,
      ...(locations ? { locations } : {}),
    },
    options: buildPermissionOptions(),
  };
}

/** Maps an ACP `session/request_permission` response back to an SDK `PermissionResult` (T3 `ClaudeAdapterV2.ts:3791-3832`). */
export function mapPermissionResponse(
  response: RequestPermissionResponse,
  toolInput: Record<string, unknown>,
  options: {
    readonly toolName: string;
    readonly suggestions?: readonly PermissionUpdate[];
    readonly toolUseID?: string;
  },
): PermissionResult {
  const toolUseIdField = options.toolUseID
    ? { toolUseID: options.toolUseID }
    : {};

  // Anything but a well-formed answer denies: never allow by default.
  if (!isPlainRecord(response) || !isPlainRecord(response.outcome)) {
    return { behavior: "deny", message: REJECTED_MESSAGE, ...toolUseIdField };
  }

  if (response.outcome.outcome === "cancelled") {
    return {
      behavior: "deny",
      message: CANCELLED_MESSAGE,
      interrupt: true,
      ...toolUseIdField,
    };
  }

  if (response.outcome.outcome !== "selected") {
    return { behavior: "deny", message: REJECTED_MESSAGE, ...toolUseIdField };
  }

  const { optionId } = response.outcome;
  if (optionId === ALLOW_ONCE_OPTION_ID) {
    return {
      behavior: "allow",
      updatedInput: toolInput,
      ...toolUseIdField,
    };
  }

  if (optionId === ALLOW_ALWAYS_OPTION_ID) {
    return {
      behavior: "allow",
      updatedInput: toolInput,
      updatedPermissions: toSessionPermissionUpdates(
        options.toolName,
        options.suggestions,
      ),
      ...toolUseIdField,
    };
  }

  return {
    behavior: "deny",
    message: REJECTED_MESSAGE,
    ...toolUseIdField,
  };
}

/** Parses SDK `AskUserQuestion` input into stable form fields (T3 `ClaudeAdapterV2.ts:4674-4722`). */
export function parseAskUserQuestions(
  toolInput: Record<string, unknown>,
): ParsedAskUserQuestion[] {
  const rawQuestions = toolInput.questions;
  if (!Array.isArray(rawQuestions)) {
    return [];
  }

  const parsed: ParsedAskUserQuestion[] = [];
  for (const item of rawQuestions) {
    if (!isPlainRecord(item)) {
      continue;
    }
    const question =
      typeof item.question === "string" ? item.question.trim() : "";
    if (question.length === 0) {
      continue;
    }
    const idx = parsed.length;
    const rawHeader = typeof item.header === "string" ? item.header.trim() : "";
    const header = rawHeader.length > 0 ? rawHeader : `Question ${idx + 1}`;
    const rawOptions = Array.isArray(item.options) ? item.options : [];
    const options: AskUserQuestionOption[] = [];

    for (const rawOpt of rawOptions) {
      if (!isPlainRecord(rawOpt)) {
        continue;
      }
      const label = typeof rawOpt.label === "string" ? rawOpt.label.trim() : "";
      if (label.length === 0) {
        continue;
      }
      const description =
        typeof rawOpt.description === "string" ? rawOpt.description.trim() : "";
      options.push({
        label,
        ...(description.length > 0 ? { description } : {}),
      });
    }

    parsed.push({
      id: `q_${idx}`,
      header,
      question,
      options,
      multiSelect: item.multiSelect === true,
    });
  }

  return parsed;
}

function toEnumOptions(
  options: readonly AskUserQuestionOption[],
): EnumOption[] {
  return options.map((opt) => ({
    const: opt.label,
    title: opt.label,
    ...(opt.description ? { description: opt.description } : {}),
  }));
}

/** Builds a form-mode ACP `elicitation/create` request for `AskUserQuestion` (T3 `ClaudeAdapterV2.ts:10688-10700`). */
export function buildElicitationRequest(
  sessionId: string,
  questions: readonly ParsedAskUserQuestion[],
  toolUseID?: string,
): CreateElicitationRequest {
  const properties: Record<string, ElicitationPropertySchema> = {};

  for (const q of questions) {
    const enumOptions = toEnumOptions(q.options);
    if (q.multiSelect) {
      properties[q.id] = {
        type: "array",
        title: q.header,
        description: q.question,
        items: {
          anyOf: enumOptions,
        },
      };
    } else {
      properties[q.id] = {
        type: "string",
        title: q.header,
        description: q.question,
        ...(enumOptions.length > 0 ? { oneOf: enumOptions } : {}),
      };
    }
  }

  return {
    sessionId,
    ...(toolUseID ? { toolCallId: toolUseID } : {}),
    mode: "form",
    message:
      questions.length === 1
        ? "Please answer the following question to continue."
        : "Please answer the following questions to continue.",
    requestedSchema: {
      type: "object",
      properties,
      required: questions.map((q) => q.id),
    },
  };
}

/** Formats ACP elicitation form content back into SDK `AskUserQuestion.answers` (T3 `ClaudeAdapterV2.ts:4724-4737`). */
export function buildAskUserQuestionAnswers(
  questions: readonly ParsedAskUserQuestion[],
  content: Record<string, unknown> | null | undefined,
): Record<string, string> {
  const answers: Record<string, string> = {};
  if (!content) {
    return answers;
  }

  for (const q of questions) {
    const rawValue =
      q.id in content
        ? content[q.id]
        : q.question in content
          ? content[q.question]
          : undefined;
    if (rawValue === undefined || rawValue === null) {
      continue;
    }
    if (Array.isArray(rawValue)) {
      answers[q.question] = rawValue
        .filter((item): item is string => typeof item === "string")
        .join(", ");
    } else if (typeof rawValue === "string") {
      answers[q.question] = rawValue;
    } else {
      answers[q.question] = String(rawValue);
    }
  }

  return answers;
}

/** Maps an ACP `elicitation/create` response back to an SDK `PermissionResult` (T3 `ClaudeAdapterV2.ts:10743-10756`). */
export function mapElicitationResponse(
  response: CreateElicitationResponse,
  toolInput: Record<string, unknown>,
  questions: readonly ParsedAskUserQuestion[],
  toolUseID?: string,
): PermissionResult {
  const toolUseIdField = toolUseID ? { toolUseID } : {};

  if (!isPlainRecord(response)) {
    return { behavior: "deny", message: REJECTED_MESSAGE, ...toolUseIdField };
  }

  if (response.action === "accept") {
    // An accept must answer every question with one of its own options;
    // anything else denies rather than letting the tool run on empty answers.
    if (!isPlainRecord(response.content)) {
      return {
        behavior: "deny",
        message: "The answer to the question was missing.",
        ...toolUseIdField,
      };
    }
    const content = response.content;
    for (const question of questions) {
      const value =
        question.id in content
          ? content[question.id]
          : question.question in content
            ? content[question.question]
            : undefined;
      const labels =
        question.options.length > 0
          ? new Set(question.options.map((option) => option.label))
          : null;
      const validOne = (item: unknown): boolean =>
        typeof item === "string" && (labels === null || labels.has(item));
      const ok = question.multiSelect
        ? Array.isArray(value) && value.every(validOne)
        : validOne(value);
      if (!ok) {
        return {
          behavior: "deny",
          message: `The answer to "${question.header || question.question}" was not one of its options.`,
          ...toolUseIdField,
        };
      }
    }
    return {
      behavior: "allow",
      updatedInput: {
        ...toolInput,
        answers: buildAskUserQuestionAnswers(questions, content),
      },
      ...toolUseIdField,
    };
  }

  if (response.action === "decline") {
    return {
      behavior: "deny",
      message: DECLINED_QUESTION_MESSAGE,
      ...toolUseIdField,
    };
  }

  return {
    behavior: "deny",
    message: CANCELLED_MESSAGE,
    interrupt: true,
    ...toolUseIdField,
  };
}

type AbortRaceResult<T> =
  { readonly aborted: false; readonly value: T } | { readonly aborted: true };

async function raceWithAbort<T>(
  promise: Promise<T>,
  signal: AbortSignal,
): Promise<AbortRaceResult<T>> {
  if (signal.aborted) {
    void promise.catch(() => undefined);
    return { aborted: true };
  }

  let onAbort: (() => void) | undefined;
  const abortPromise = new Promise<{ readonly aborted: true }>((resolve) => {
    onAbort = () => resolve({ aborted: true });
    signal.addEventListener("abort", onAbort, { once: true });
  });

  try {
    const result = await Promise.race([
      promise.then((value) => ({ aborted: false as const, value })),
      abortPromise,
    ]);
    if (result.aborted) {
      void promise.catch(() => undefined);
    }
    return result;
  } finally {
    if (onAbort) {
      signal.removeEventListener("abort", onAbort);
    }
  }
}

function cancelledPermissionResult(toolUseID?: string): PermissionResult {
  return {
    behavior: "deny",
    message: CANCELLED_MESSAGE,
    interrupt: true,
    ...(toolUseID ? { toolUseID } : {}),
  };
}

/** Creates the SDK `canUseTool` callback forwarding approvals and questions over ACP (T3 `ClaudeAdapterV2.ts:10632-10895`). */
export function createCanUseToolHandler(
  options: PermissionHandlerOptions,
): CanUseTool {
  return async (
    toolName,
    toolInput,
    toolOptions,
  ): Promise<PermissionResult> => {
    const { signal, toolUseID, blockedPath, suggestions } = toolOptions;
    if (signal.aborted) {
      return cancelledPermissionResult(toolUseID);
    }

    try {
      // As T3 Code does (ClaudeAdapterV2.ts ~10758-10775): the plan is
      // captured from the transcript and leaving plan mode is the app's call,
      // never Claude's.
      if (toolName === "ExitPlanMode") {
        return {
          behavior: "deny",
          message:
            "The client captured your proposed plan. Stop here and wait for the user's feedback or implementation request in a later turn.",
          ...(toolUseID ? { toolUseID } : {}),
        };
      }

      if (toolName === "AskUserQuestion") {
        const questions = parseAskUserQuestions(toolInput);
        if (questions.length === 0) {
          return {
            behavior: "deny",
            message: "AskUserQuestion contained no valid questions.",
            ...(toolUseID ? { toolUseID } : {}),
          };
        }

        const request = buildElicitationRequest(
          options.sessionId,
          questions,
          toolUseID,
        );
        const race = await raceWithAbort(
          options.client.request("elicitation/create", request, {
            cancellationSignal: signal,
            stopWaitingOnCancel: true,
          }),
          signal,
        );
        if (race.aborted) {
          return cancelledPermissionResult(toolUseID);
        }
        return mapElicitationResponse(
          race.value,
          toolInput,
          questions,
          toolUseID,
        );
      }

      const request = buildPermissionRequest(
        options.sessionId,
        toolName,
        toolInput,
        { toolUseID, blockedPath, suggestions },
      );
      const race = await raceWithAbort(
        options.client.request("session/request_permission", request, {
          cancellationSignal: signal,
          stopWaitingOnCancel: true,
        }),
        signal,
      );
      if (race.aborted) {
        return cancelledPermissionResult(toolUseID);
      }
      return mapPermissionResponse(race.value, toolInput, {
        toolName,
        suggestions,
        toolUseID,
      });
    } catch (error) {
      if (
        signal.aborted ||
        (error instanceof RequestError && error.code === -32800)
      ) {
        return cancelledPermissionResult(toolUseID);
      }
      const message = error instanceof Error ? error.message : String(error);
      return {
        behavior: "deny",
        message: message || REJECTED_MESSAGE,
        ...(toolUseID ? { toolUseID } : {}),
      };
    }
  };
}
