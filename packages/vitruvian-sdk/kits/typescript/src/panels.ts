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

// A tool that draws: its panels, what the person did in one, how a handler
// answers, and a page written as the blocks it holds. The Swift kit's
// Panels.swift, in TypeScript.

import {
  type ButtonStyle,
  type FieldKind,
  type JSONValue,
  type TextStyle,
  type UIBlock,
  type UIChipOption,
  type UIChoiceOption,
  type UIEventKind,
  type UIEventResult,
  type UIListRow,
  type UIText,
  type UITree,
} from "./generated/messages.js";
import type { App } from "./tool.js";

/** What the person did in one of the tool's panels, as a handler sees it. */
export class PanelEvent {
  /** The block's id, as the page gave it. Absent for a web page's call. */
  readonly block: string | undefined;
  readonly kind: UIEventKind;
  readonly value: JSONValue | undefined;

  constructor(block: string | undefined, kind: UIEventKind, value?: JSONValue) {
    this.block = block;
    this.kind = kind;
    this.value = value;
  }

  /** For a tap on a row of a list: the row's id. */
  get row(): string | undefined {
    return this.kind === "tap" && typeof this.value === "string"
      ? this.value
      : undefined;
  }

  /**
   * For `submit` and `change`: the field's text. For the `change` of a
   * `choice`: the picked option's value.
   */
  get text(): string | undefined {
    return (this.kind === "submit" || this.kind === "change") &&
      typeof this.value === "string"
      ? this.value
      : undefined;
  }

  /** For `toggle`: the switch's new state. */
  get isOn(): boolean | undefined {
    return this.kind === "toggle" && typeof this.value === "boolean"
      ? this.value
      : undefined;
  }

  /**
   * For the `change` of `chips`: the values of every option now on, in the
   * options' order, and none when the last was turned off.
   */
  get values(): string[] | undefined {
    const value = this.value;
    return this.kind === "change" &&
      Array.isArray(value) &&
      value.every((item) => typeof item === "string")
      ? (value as string[])
      : undefined;
  }
}

/**
 * How a handler answers what the person did: the next page, the page as it
 * is, one of the tool's window panels to open by its id, or what a web
 * panel's `window.vitruvian.call` gets back. On an app that has
 * `Feature.openSettings`, `open` may name the tool's settings panel, and the
 * app opens Settings on the tool's detail.
 */
export type PanelAnswer =
  { page: UITree } | { keep: true } | { open: string } | { reply: JSONValue };

/** The answer as the wire carries it. */
export function resultOf(answer: PanelAnswer): UIEventResult {
  if ("page" in answer) return { tree: answer.page };
  if ("open" in answer) return { open: answer.open };
  if ("reply" in answer) return { reply: answer.reply };
  return { keep: true };
}

/** Gives the first page when the person opens the panel; a web panel gives none. */
export type PanelOpened = (app: App, panel: Panel) => UITree | undefined;
/** Answers what the person did. */
export type PanelActed = (
  app: App,
  panel: Panel,
  event: PanelEvent,
) => PanelAnswer;
/**
 * A web panel's call of a method of the tool's own, one whose name starts
 * with `tool/`: the method, its params, and the reply.
 */
export type PanelCalled = (
  app: App,
  method: string,
  params: JSONValue | undefined,
) => JSONValue;

/** What `Tool.panel` takes. */
export interface PanelHandlers {
  onOpen: PanelOpened;
  onEvent?: PanelActed;
}

/** What `Panel.badge` takes. With neither, the badge goes. */
export interface Badge {
  /** A whole number from 0; 0 is no count. */
  count?: number;
  /** A dot, when there is no count. */
  dot?: boolean;
}

/** The kit's side of a tool, as a panel needs it. */
export interface PanelLink {
  readonly app: App;
  note(method: string, params: object): boolean;
}

/**
 * One of the tool's panels, as the manifest declares it. Made by
 * `tool.panel(id, { onOpen, onEvent })`. Use it from the thread that runs
 * the tool, as everything of a `Tool`.
 */
export class Panel {
  /** The id the manifest gives it. */
  readonly id: string;
  /**
   * For a web panel: what its page's calls of the tool's own methods
   * answer. With none, such a call is answered as a method not found. A
   * call of a request the app does, such as `notify/hud`, is passed to the
   * app as the tool's own, with no handler.
   */
  onCall?: PanelCalled;

  /** @internal */
  readonly onOpen: PanelOpened;
  /** @internal */
  readonly onEvent: PanelActed;
  private open = false;
  private readonly link: PanelLink;

  /** @internal */
  constructor(id: string, link: PanelLink, handlers: PanelHandlers) {
    this.id = id;
    this.link = link;
    this.onOpen = handlers.onOpen;
    this.onEvent = handlers.onEvent ?? (() => ({ keep: true }));
  }

  /** True while the app has it open: from `ui/open` to `ui/close`. */
  get isOpen(): boolean {
    return this.open;
  }

  /** @internal */
  setOpen(open: boolean): void {
    this.open = open;
  }

  /**
   * Sends a new page for the panel, unprompted: `ui/render`. False, and
   * nothing is sent, when the panel is not open. The app draws at most four
   * pages a second for a panel; send fewer.
   */
  render(tree: UITree): boolean {
    if (!this.open) return false;
    return this.link.note("ui/render", { panel: this.id, tree });
  }

  /**
   * Puts a count, or a dot, beside the tool's page in the island's Explore gallery:
   * `ui/badge`. With neither, the badge goes. Needs `notify` in `uses`.
   * Throws a `Refusal` when the app refuses it.
   */
  badge(badge: Badge = {}): void {
    this.link.app.ui.badge(
      without({ count: badge.count, dot: badge.dot ? true : undefined }),
    );
  }
}

/** The bridge's call, as `ui/event`'s value carries it for `bridge`. */
export interface BridgeCall {
  method: string;
  params?: JSONValue;
}

/** A method of the tool's own, which a web page may call: its name starts with this. */
export const TOOLS_OWN = "tool/";

export function bridgeCallOf(
  value: JSONValue | undefined,
): BridgeCall | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    return undefined;
  const method = value["method"];
  if (typeof method !== "string") return undefined;
  const params = value["params"];
  return params === undefined ? { method } : { method, params };
}

// MARK: - Writing a page

/** The object less its undefined fields, so that a page has no `undefined` in it. */
function without<T extends object>(fields: T): T {
  const out: { [key: string]: unknown } = {};
  for (const [key, value] of Object.entries(fields)) {
    if (value !== undefined) out[key] = value;
  }
  return out as T;
}

/** Words. `style` is `body` when left out; `lines` is the most lines they take. */
export function text(
  text: UIText,
  options: { style?: TextStyle; lines?: number } = {},
): UIBlock {
  return without({
    type: "text",
    text,
    style: options.style,
    lines: options.lines,
  });
}

/**
 * A heading, of two lines at most. With `section: true` it starts a section
 * of the page, which the app may list for the person to jump to; one without
 * is a sub-heading. An app without `Feature.sections` draws a plain heading,
 * and the conformance script's older app fails a page that sends it one, so
 * ask `app.supports(Feature.sections)` first.
 */
export function heading(
  text: UIText,
  options: { section?: boolean } = {},
): UIBlock {
  return without({ type: "heading", text, section: options.section });
}

/** A row. With an `id` it can be tapped. */
export function row(
  title: UIText,
  options: {
    id?: string;
    subtitle?: UIText;
    icon?: string;
    trailing?: UIText;
  } = {},
): UIBlock {
  return without({
    type: "row",
    id: options.id,
    title,
    subtitle: options.subtitle,
    icon: options.icon,
    trailing: options.trailing,
  });
}

/** A button. Pressing it is the event `tap`. */
export function button(
  id: string,
  title: UIText,
  options: { style?: ButtonStyle; enabled?: boolean } = {},
): UIBlock {
  return without({
    type: "button",
    id,
    title,
    style: options.style,
    enabled: options.enabled,
  });
}

/**
 * A switch. Turning it is the event `toggle`, with its new state. `help` is
 * a line or two under it that says what it does; an app without
 * `Feature.sections` leaves it out, so send that app a `text` after the
 * switch instead.
 */
export function toggle(
  id: string,
  title: UIText,
  isOn: boolean,
  options: { enabled?: boolean; help?: UIText } = {},
): UIBlock {
  return without({
    type: "toggle",
    id,
    title,
    value: isOn,
    enabled: options.enabled,
    help: options.help,
  });
}

/**
 * A field to type in. Return is the event `submit`; leaving it changed is the
 * event `change`. `help` is as a switch's.
 */
export function field(
  id: string,
  options: {
    title?: UIText;
    value?: string;
    placeholder?: UIText;
    kind?: FieldKind;
    help?: UIText;
  } = {},
): UIBlock {
  return without({
    type: "field",
    id,
    title: options.title,
    value: options.value,
    placeholder: options.placeholder,
    kind: options.kind,
    help: options.help,
  });
}

/** Rows, drawn together. Tapping one is the event `tap`, with the row's id. */
export function list(id: string, rows: UIListRow[]): UIBlock {
  return { type: "list", id, rows };
}

/** How far something has got: `value` from 0 to 1, or none when nobody knows. */
export function progress(
  options: { value?: number; label?: UIText } = {},
): UIBlock {
  return without({
    type: "progress",
    value: options.value,
    label: options.label,
  });
}

/** A picture: a path inside the tool's folder, or a `data:` PNG or JPEG. */
export function image(
  source: string,
  options: { alt?: UIText; height?: number } = {},
): UIBlock {
  return without({
    type: "image",
    source,
    alt: options.alt,
    height: options.height,
  });
}

/** A line between blocks. */
export function divider(): UIBlock {
  return { type: "divider" };
}

/** A link the app opens through its `open` service. */
export function link(title: UIText, url: string): UIBlock {
  return { type: "link", title, url };
}

/** Room between blocks, in points; 8 when left out. */
export function spacer(size?: number): UIBlock {
  return without({ type: "spacer", size });
}

/**
 * A pop-up menu: one of a fixed list of options, each `{ value, title }`.
 * `value` is the selected option's. Picking one is the event `change`, read
 * with `event.text`.
 *
 * An app before 3.48 does not know this kind and draws `fallback`, which
 * nobody can change. So ask `app.supports(Feature.choice)` first, and send
 * a `field` to an app without it. With no `fallback` given, one is written:
 * the title, a colon and the selected option's title. `help` is as a
 * switch's.
 */
export function choice(
  id: string,
  value: string,
  options: UIChoiceOption[],
  more: {
    title?: UIText;
    enabled?: boolean;
    fallback?: UIText;
    help?: UIText;
  } = {},
): UIBlock {
  return without({
    type: "choice" as const,
    id,
    title: more.title,
    value,
    options,
    enabled: more.enabled,
    help: more.help,
    fallback: more.fallback ?? saidPlainly(more.title, value, options),
  });
}

/**
 * Chips: a fixed list of options, each `{ value, title, on }`, any number of
 * them on at once. Turning one is the event `change`, read with
 * `event.values`: the values of every option then on. An option with
 * `enabled: false` is dimmed, and its `reason` says why.
 *
 * An app without `Feature.chips` does not know this kind and draws
 * `fallback`, which nobody can change. So ask `app.supports(Feature.chips)`
 * first, and send a `toggle` for each option to an app without it. With no
 * `fallback` given, one is written: the title, a colon and the titles of the
 * options that are on. `help` is as a switch's.
 */
export function chips(
  id: string,
  options: UIChipOption[],
  more: {
    title?: UIText;
    enabled?: boolean;
    help?: UIText;
    fallback?: UIText;
  } = {},
): UIBlock {
  return without({
    type: "chips" as const,
    id,
    title: more.title,
    options,
    enabled: more.enabled,
    help: more.help,
    fallback:
      more.fallback ??
      listedPlainly(
        more.title,
        options.filter((option) => option.on).map((option) => option.title),
      ),
  });
}

/** A text in a language: its own entry, else English; a string whatever the language. */
function words(text: UIText, language: string): string {
  return typeof text === "string" ? text : (text[language] ?? text["en"] ?? "");
}

/** The languages any of these texts has, in order. */
function languagesOf(texts: UIText[]): string[] {
  return [
    ...new Set(
      texts.flatMap((text) =>
        typeof text === "string" ? [] : Object.keys(text),
      ),
    ),
  ].sort();
}

/**
 * What chips say, as words: the title, a colon and the titles of the
 * options that are on, or those titles alone, in every language any of them
 * has. A dash stands for none.
 */
function listedPlainly(title: UIText | undefined, on: UIText[]): UIText {
  const said = (language: string): string => {
    const titles =
      on.length === 0
        ? "\u2014"
        : on.map((text) => words(text, language)).join(", ");
    return title === undefined
      ? titles
      : `${words(title, language)}: ${titles}`;
  };
  const languages = languagesOf(title === undefined ? on : [title, ...on]);
  if (languages.length === 0) return said("en");
  const all: { [language: string]: string } = {};
  for (const language of languages) all[language] = said(language);
  return all;
}

/**
 * What a choice says, as words: the title, a colon and the selected
 * option's title, or that title alone, in every language either has. A
 * value that is no option's is written as it is.
 */
function saidPlainly(
  title: UIText | undefined,
  value: string,
  options: UIChoiceOption[],
): UIText {
  const selected: UIText =
    options.find((option) => option.value === value)?.title ?? value;
  if (title === undefined) return selected;
  const languages = languagesOf([title, selected]);
  if (languages.length === 0)
    return `${words(title, "en")}: ${words(selected, "en")}`;
  const said: { [language: string]: string } = {};
  for (const language of languages)
    said[language] = `${words(title, language)}: ${words(selected, language)}`;
  return said;
}

/**
 * A page as the blocks it holds, one under the other. A block that is
 * `false`, `null` or `undefined` is left out, so a page may be written with
 * `count > 9 && text("That is a lot")`:
 *
 *     tree([
 *       heading("Counter"),
 *       text(`Pressed ${count} times`),
 *       button("add", "Add one", { style: "prominent" }),
 *       count > 9 && text("That is a lot", { style: "caption" }),
 *     ])
 */
export function tree(blocks: (UIBlock | false | null | undefined)[]): UITree {
  return {
    blocks: blocks.filter((block): block is UIBlock => Boolean(block)),
  };
}
