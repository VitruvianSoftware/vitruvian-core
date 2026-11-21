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

import { readdir, readFile, realpath, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

export interface AvailableSlashCommand {
  readonly name: string;
  readonly description: string;
  readonly input?: {
    readonly hint: string;
  };
}

export interface DiscoverSkillsOptions {
  readonly cwd: string;
  readonly configDir?: string;
  readonly homeDir?: string;
  readonly additionalDirectories?: readonly string[];
  readonly env?: NodeJS.ProcessEnv;
  readonly platform?: NodeJS.Platform;
  readonly includeManagedSettings?: boolean;
}

export type SkillFrontmatter =
  | { readonly kind: "missing" }
  | { readonly kind: "malformed" }
  | {
      readonly kind: "parsed";
      readonly name?: string;
      readonly description?: string;
      readonly argumentHint?: string;
      readonly userInvocationOnly?: boolean;
      readonly userInvocable?: boolean;
    };

type SkillOverrideValue = "on" | "name-only" | "user-invocable-only" | "off";

interface SkillOverride {
  readonly enabled: boolean;
  readonly userInvocationOnly: boolean;
}

interface SkillRoot {
  readonly kind: "skills" | "commands";
  readonly directory: string;
  readonly prefix?: string;
}

interface InstalledPluginRecord {
  readonly scope: "user" | "project" | "local" | "managed";
  readonly installPath: string;
  readonly projectPath?: string;
}

const FRONTMATTER_PATTERN = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/;
const VALID_OVERRIDE_VALUES: ReadonlySet<string> = new Set([
  "on",
  "name-only",
  "user-invocable-only",
  "off",
]);
const SKILL_MENTION_NAME_PATTERN = /^[a-zA-Z0-9][a-zA-Z0-9:_-]*$/;

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function expandHomePath(rawPath: string, homeDir: string): string {
  if (rawPath === "~") {
    return homeDir;
  }
  if (rawPath.startsWith("~/") || rawPath.startsWith("~\\")) {
    return path.join(homeDir, rawPath.slice(2));
  }
  return rawPath;
}

/** Parses YAML 1.1 booleans accepted by Claude Code (T3 `ClaudeSkills.ts:37-57`). */
function parseFrontmatterBoolean(value: unknown): boolean | undefined {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") {
    return value === 1 ? true : value === 0 ? false : undefined;
  }
  if (typeof value !== "string") return undefined;
  switch (value.trim().toLowerCase()) {
    case "true":
    case "yes":
    case "on":
    case "y":
    case "1":
      return true;
    case "false":
    case "no":
    case "off":
    case "n":
    case "0":
      return false;
    default:
      return undefined;
  }
}

function unquoteYamlScalar(raw: string): string | null {
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return "";
  }
  if (trimmed.startsWith('"')) {
    if (trimmed.length < 2 || !trimmed.endsWith('"')) {
      return null;
    }
    try {
      const parsed = JSON.parse(trimmed);
      return typeof parsed === "string" ? parsed : String(parsed);
    } catch {
      return trimmed.slice(1, -1);
    }
  }
  if (trimmed.startsWith("'")) {
    if (trimmed.length < 2 || !trimmed.endsWith("'")) {
      return null;
    }
    return trimmed.slice(1, -1).replace(/''/g, "'");
  }
  // Strip inline YAML comment (` # ...`) outside quotes.
  const withoutComment = trimmed.replace(/[ \t]+#.*$/, "").trim();
  return withoutComment;
}

/**
 * Parses YAML frontmatter from a SKILL.md or command markdown file without external YAML deps.
 * Mirrors T3 `parseSkillFrontmatter` (`ClaudeSkills.ts:59-105`) including unquoted `: ` values.
 */
export function parseSkillFrontmatter(contents: string): SkillFrontmatter {
  const match = FRONTMATTER_PATTERN.exec(contents);
  if (!match) {
    // Detect unclosed opening fence `---` as malformed.
    if (/^---\r?\n/.test(contents)) {
      return { kind: "malformed" };
    }
    return { kind: "missing" };
  }

  const frontmatter = match[1] ?? "";
  const lines = frontmatter.split(/\r?\n/);
  const record: Record<string, string> = {};

  let idx = 0;
  while (idx < lines.length) {
    const line = lines[idx];
    if (line.trim().length === 0 || /^\s*#/.test(line)) {
      idx += 1;
      continue;
    }
    if (/^\t/.test(line)) {
      return { kind: "malformed" };
    }
    if (/^[ \t]+/.test(line)) {
      // Unexpected indented line outside a block scalar or nested mapping -> malformed.
      return { kind: "malformed" };
    }

    const kvMatch = /^([A-Za-z0-9_-]+)[ \t]*:(.*)$/.exec(line);
    if (!kvMatch) {
      return { kind: "malformed" };
    }

    const key = kvMatch[1];
    const rest = kvMatch[2].trim();

    if (rest === "|" || rest === "|-" || rest === ">" || rest === ">-") {
      const folded = rest.startsWith(">");
      const blockLines: string[] = [];
      let blockIndent: number | null = null;
      idx += 1;
      while (idx < lines.length) {
        const nextLine = lines[idx];
        if (nextLine.trim().length === 0) {
          blockLines.push("");
          idx += 1;
          continue;
        }
        const indentMatch = /^( +)/.exec(nextLine);
        if (!indentMatch) {
          break;
        }
        const indent = indentMatch[1].length;
        if (blockIndent === null) {
          blockIndent = indent;
        } else if (indent < blockIndent) {
          break;
        }
        blockLines.push(nextLine.slice(blockIndent));
        idx += 1;
      }
      while (
        blockLines.length > 0 &&
        blockLines[blockLines.length - 1] === ""
      ) {
        blockLines.pop();
      }
      record[key] = (
        folded ? blockLines.join(" ") : blockLines.join("\n")
      ).trim();
      continue;
    }

    if (rest.length === 0) {
      // Nested mapping or array value for another field (e.g. `metadata:`); consume indented lines.
      let nextIdx = idx + 1;
      while (nextIdx < lines.length) {
        const nextLine = lines[nextIdx];
        if (nextLine.trim().length === 0 || /^[ \t]+/.test(nextLine)) {
          nextIdx += 1;
          continue;
        }
        break;
      }
      record[key] = "";
      idx = nextIdx;
      continue;
    }

    if (
      (rest.startsWith("[") && !rest.endsWith("]")) ||
      (rest.startsWith("{") && !rest.endsWith("}"))
    ) {
      return { kind: "malformed" };
    }

    const scalar = unquoteYamlScalar(rest);
    if (scalar === null) {
      return { kind: "malformed" };
    }
    record[key] = scalar;
    idx += 1;
  }

  const name = (record.name ?? "").trim();
  const description = (record.description ?? "").trim();
  const argumentHint = (record["argument-hint"] ?? "").trim();

  return {
    kind: "parsed",
    ...(name.length > 0 ? { name } : {}),
    ...(description.length > 0 ? { description } : {}),
    ...(argumentHint.length > 0 ? { argumentHint } : {}),
    ...(parseFrontmatterBoolean(record["disable-model-invocation"]) === true
      ? { userInvocationOnly: true }
      : {}),
    ...(parseFrontmatterBoolean(record["user-invocable"]) === false
      ? { userInvocable: false }
      : {}),
  };
}

/** Strips line/block comments and trailing commas from lenient JSON settings files. */
function parseLenientJson(contents: string): unknown {
  let stripped = "";
  let inString = false;
  let escaped = false;
  let i = 0;

  while (i < contents.length) {
    const ch = contents[i];
    const next = contents[i + 1];

    if (inString) {
      stripped += ch;
      if (escaped) {
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      i += 1;
      continue;
    }

    if (ch === '"') {
      inString = true;
      stripped += ch;
      i += 1;
      continue;
    }

    if (ch === "/" && next === "/") {
      i += 2;
      while (i < contents.length && contents[i] !== "\n") {
        i += 1;
      }
      continue;
    }

    if (ch === "/" && next === "*") {
      i += 2;
      while (
        i < contents.length &&
        !(contents[i] === "*" && contents[i + 1] === "/")
      ) {
        i += 1;
      }
      i += 2;
      continue;
    }

    stripped += ch;
    i += 1;
  }

  // Remove trailing commas outside strings before `}` or `]`.
  let withoutTrailingCommas = "";
  inString = false;
  escaped = false;
  for (let j = 0; j < stripped.length; j += 1) {
    const ch = stripped[j];
    if (inString) {
      withoutTrailingCommas += ch;
      if (escaped) {
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }
    if (ch === '"') {
      inString = true;
      withoutTrailingCommas += ch;
      continue;
    }
    if (ch === ",") {
      let lookahead = j + 1;
      while (lookahead < stripped.length && /\s/.test(stripped[lookahead])) {
        lookahead += 1;
      }
      if (stripped[lookahead] === "}" || stripped[lookahead] === "]") {
        continue;
      }
    }
    withoutTrailingCommas += ch;
  }

  return JSON.parse(withoutTrailingCommas);
}

async function pathExists(targetPath: string): Promise<boolean> {
  try {
    await stat(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function readTextIfExists(filePath: string): Promise<string | undefined> {
  try {
    return await readFile(filePath, "utf8");
  } catch {
    return undefined;
  }
}

async function safeRealpath(targetPath: string): Promise<string | undefined> {
  try {
    return await realpath(targetPath);
  } catch {
    return undefined;
  }
}

async function findRepositoryRoot(cwd: string): Promise<string | undefined> {
  let current = path.resolve(cwd);
  while (true) {
    if (await pathExists(path.join(current, ".git"))) {
      return current;
    }
    const parent = path.dirname(current);
    if (parent === current) {
      return undefined;
    }
    current = parent;
  }
}

async function findPluginRepositoryRoot(
  cwd: string,
): Promise<string | undefined> {
  const root = await findRepositoryRoot(cwd);
  if (!root) {
    return undefined;
  }
  const gitFile = (await readTextIfExists(path.join(root, ".git"))) ?? "";
  if (!gitFile.trim().startsWith("gitdir:")) {
    return root;
  }
  const gitDirectory = path.resolve(root, gitFile.trim().slice(7).trim());
  const commonFile =
    (await readTextIfExists(path.join(gitDirectory, "commondir"))) ?? "";
  const worktreeFile =
    (await readTextIfExists(path.join(gitDirectory, "gitdir"))) ?? "";
  if (!commonFile.trim() || !worktreeFile.trim()) {
    return root;
  }
  const commonDirectory = path.resolve(gitDirectory, commonFile.trim());
  const backlinkPath = await safeRealpath(
    path.resolve(gitDirectory, worktreeFile.trim()),
  );
  const worktreeGitPath = await safeRealpath(path.join(root, ".git"));
  if (
    path.dirname(gitDirectory) !== path.join(commonDirectory, "worktrees") ||
    backlinkPath === undefined ||
    backlinkPath !== worktreeGitPath
  ) {
    return root;
  }
  return path.basename(commonDirectory) === ".git"
    ? path.dirname(commonDirectory)
    : commonDirectory;
}

function claudeManagedSettingsPath(
  platform: NodeJS.Platform,
  env: NodeJS.ProcessEnv,
): string | undefined {
  if (platform === "darwin") {
    return "/Library/Application Support/ClaudeCode/managed-settings.json";
  }
  if (platform === "win32") {
    const programData = env.PROGRAMDATA?.trim();
    return programData
      ? path.join(programData, "ClaudeCode", "managed-settings.json")
      : undefined;
  }
  return "/etc/claude-code/managed-settings.json";
}

function parseSkillOverride(value: SkillOverrideValue): SkillOverride {
  switch (value) {
    case "off":
      return { enabled: false, userInvocationOnly: false };
    case "user-invocable-only":
      return { enabled: true, userInvocationOnly: true };
    case "on":
    case "name-only":
      return { enabled: true, userInvocationOnly: false };
  }
}

function parseSkillOverrideMap(
  rawOverrides: unknown,
): ReadonlyMap<string, SkillOverride> | undefined {
  if (!isPlainRecord(rawOverrides)) {
    return undefined;
  }
  const entries = new Map<string, SkillOverride>();
  for (const [name, value] of Object.entries(rawOverrides)) {
    // T3 `ClaudeSkills.ts:206-211`: one unknown override value drops every override in that file.
    if (typeof value !== "string" || !VALID_OVERRIDE_VALUES.has(value)) {
      return undefined;
    }
    entries.set(name, parseSkillOverride(value as SkillOverrideValue));
  }
  return entries;
}

async function readSkillSettings(input: {
  readonly configDirPath: string;
  readonly cwd: string;
  readonly platform: NodeJS.Platform;
  readonly env: NodeJS.ProcessEnv;
  readonly includeManagedSettings: boolean;
}): Promise<{
  readonly skillOverrides: Map<string, SkillOverride>;
  readonly enabledPlugins: Map<string, boolean>;
}> {
  const overridesByName = new Map<string, SkillOverride>();
  const enabledPlugins = new Map<string, boolean>();
  const repositoryRoot = await findRepositoryRoot(input.cwd);
  const root =
    repositoryRoot !== undefined && repositoryRoot !== input.cwd
      ? repositoryRoot
      : undefined;
  const managedPath = input.includeManagedSettings
    ? claudeManagedSettingsPath(input.platform, input.env)
    : undefined;

  const settingsPaths = [
    path.join(input.configDirPath, "settings.json"),
    path.join(input.cwd, ".claude", "settings.json"),
    path.join(input.cwd, ".claude", "settings.local.json"),
    ...(root ? [path.join(root, ".claude", "settings.local.json")] : []),
    ...(managedPath ? [managedPath] : []),
  ];

  for (const settingsPath of settingsPaths) {
    const contents = await readTextIfExists(settingsPath);
    if (contents === undefined) {
      continue;
    }
    let parsed: unknown;
    try {
      parsed = parseLenientJson(contents);
    } catch {
      continue;
    }
    if (!isPlainRecord(parsed)) {
      continue;
    }

    if (parsed.skillOverrides !== undefined) {
      const fileOverrides = parseSkillOverrideMap(parsed.skillOverrides);
      if (!fileOverrides) {
        continue;
      }
      for (const [name, override] of fileOverrides) {
        overridesByName.set(name, override);
      }
    }

    if (isPlainRecord(parsed.enabledPlugins)) {
      for (const [key, enabled] of Object.entries(parsed.enabledPlugins)) {
        if (typeof enabled === "boolean") {
          enabledPlugins.set(key, enabled);
        } else {
          enabledPlugins.delete(key);
        }
      }
    }
  }

  return { skillOverrides: overridesByName, enabledPlugins };
}

function isInsideDirectory(directory: string, candidate: string): boolean {
  const relative = path.relative(directory, candidate);
  return (
    relative !== ".." &&
    !relative.startsWith(`..${path.sep}`) &&
    !path.isAbsolute(relative)
  );
}

function decodeInstalledPluginRecord(
  raw: unknown,
): InstalledPluginRecord | undefined {
  if (!isPlainRecord(raw)) {
    return undefined;
  }
  if (
    raw.scope !== "user" &&
    raw.scope !== "project" &&
    raw.scope !== "local" &&
    raw.scope !== "managed"
  ) {
    return undefined;
  }
  if (
    typeof raw.installPath !== "string" ||
    raw.installPath.trim().length === 0
  ) {
    return undefined;
  }
  if (
    raw.projectPath !== undefined &&
    (typeof raw.projectPath !== "string" || raw.projectPath.trim().length === 0)
  ) {
    return undefined;
  }
  return {
    scope: raw.scope,
    installPath: raw.installPath,
    ...(raw.projectPath !== undefined ? { projectPath: raw.projectPath } : {}),
  };
}

/** Discovers enabled plugin skill directories (T3 `ClaudeSkills.ts:314-415`). */
async function discoverPluginSkillRoots(input: {
  readonly configDirPath: string;
  readonly cwd: string;
  readonly homeDir: string;
  readonly enabledPlugins: ReadonlyMap<string, boolean>;
  readonly env: NodeJS.ProcessEnv;
}): Promise<SkillRoot[]> {
  const pluginEnvDir = input.env.CLAUDE_CODE_PLUGIN_CACHE_DIR;
  const pluginsPath = pluginEnvDir
    ? path.resolve(input.cwd, expandHomePath(pluginEnvDir, input.homeDir))
    : path.join(input.configDirPath, "plugins");

  const installedRaw = await readTextIfExists(
    path.join(pluginsPath, "installed_plugins.json"),
  );
  if (installedRaw === undefined) {
    return [];
  }

  let installedParsed: unknown;
  try {
    installedParsed = JSON.parse(installedRaw);
  } catch {
    return [];
  }
  if (
    !isPlainRecord(installedParsed) ||
    !isPlainRecord(installedParsed.plugins)
  ) {
    return [];
  }

  const workspace = (await safeRealpath(input.cwd)) ?? path.resolve(input.cwd);
  const projectRepoRoots = new Map<string, string | undefined>();
  const repositoryRoot = await findPluginRepositoryRoot(workspace);
  const roots: SkillRoot[] = [];

  for (const key of Object.keys(installedParsed.plugins).sort()) {
    if (input.enabledPlugins.get(key) !== true) {
      continue;
    }
    const rawEntries = installedParsed.plugins[key];
    if (!Array.isArray(rawEntries)) {
      continue;
    }

    const applicable: InstalledPluginRecord[] = [];
    for (const rawEntry of rawEntries) {
      const record = decodeInstalledPluginRecord(rawEntry);
      if (!record) {
        continue;
      }
      if (record.scope === "user" || record.scope === "managed") {
        applicable.push(record);
        continue;
      }
      if (!record.projectPath) {
        continue;
      }
      const projectPath = path.resolve(record.projectPath);
      if (projectPath === workspace) {
        applicable.push(record);
        continue;
      }
      if (!repositoryRoot) {
        continue;
      }
      if (!projectRepoRoots.has(projectPath)) {
        projectRepoRoots.set(
          projectPath,
          await findPluginRepositoryRoot(projectPath),
        );
      }
      if (projectRepoRoots.get(projectPath) === repositoryRoot) {
        applicable.push(record);
      }
    }

    let install: InstalledPluginRecord | undefined;
    for (const candidate of applicable) {
      if (await pathExists(path.resolve(input.cwd, candidate.installPath))) {
        install = candidate;
        break;
      }
    }
    install ??= applicable[0];
    if (!install) {
      continue;
    }

    const installPath = path.resolve(input.cwd, install.installPath);
    const manifestRaw = await readTextIfExists(
      path.join(installPath, ".claude-plugin", "plugin.json"),
    );
    let manifestName: string | undefined;
    let declaredSkills: string[] = [];
    if (manifestRaw !== undefined) {
      try {
        const manifest = JSON.parse(manifestRaw);
        if (isPlainRecord(manifest)) {
          if (
            typeof manifest.name === "string" &&
            manifest.name.trim().length > 0
          ) {
            manifestName = manifest.name.trim();
          }
          if (typeof manifest.skills === "string") {
            declaredSkills = [manifest.skills];
          } else if (Array.isArray(manifest.skills)) {
            declaredSkills = manifest.skills.filter(
              (s): s is string => typeof s === "string",
            );
          }
        }
      } catch {
        // Ignore malformed manifest; fall back to plugin key prefix.
      }
    }

    const prefix = manifestName ?? key.split("@")[0];
    if (!prefix) {
      continue;
    }

    const defaultDir = path.join(installPath, "skills");
    const hasDefaultDir = await pathExists(defaultDir);
    if (hasDefaultDir) {
      roots.push({ kind: "skills", directory: defaultDir, prefix });
    }
    if (declaredSkills.length === 0 && !hasDefaultDir) {
      if (await pathExists(path.join(installPath, "SKILL.md"))) {
        roots.push({ kind: "skills", directory: installPath, prefix });
      }
    }

    const canonicalInstallPath = await safeRealpath(installPath);
    for (const relative of declaredSkills) {
      const directory = path.resolve(installPath, relative);
      if (
        !isInsideDirectory(installPath, directory) ||
        canonicalInstallPath === undefined
      ) {
        continue;
      }
      const canonicalDir = await safeRealpath(directory);
      if (
        canonicalDir !== undefined &&
        isInsideDirectory(canonicalInstallPath, canonicalDir)
      ) {
        roots.push({ kind: "skills", directory, prefix });
      }
    }
  }

  return roots;
}

/**
 * Lists `.md` files under `directory`. Symlinks are followed only while they
 * stay inside the root (as Claude Code's own loader rejects roots that escape
 * through a symlink), and each real directory is visited once, so a symlink
 * loop can't recurse without end.
 */
async function listMarkdownFilesRecursive(
  directory: string,
  prefix = "",
  canonicalRoot?: string,
  visitedDirs?: Set<string>,
): Promise<
  Array<{ readonly relativePath: string; readonly fullPath: string }>
> {
  const rootReal = canonicalRoot ?? (await safeRealpath(directory));
  if (!rootReal) {
    return [];
  }
  const dirReal = await safeRealpath(directory);
  if (
    !dirReal ||
    (dirReal !== rootReal && !isInsideDirectory(rootReal, dirReal))
  ) {
    return [];
  }
  const seen = visitedDirs ?? new Set<string>();
  if (seen.has(dirReal)) {
    return [];
  }
  seen.add(dirReal);

  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch {
    return [];
  }

  const results: Array<{
    readonly relativePath: string;
    readonly fullPath: string;
  }> = [];
  const sorted = [...entries].sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of sorted) {
    const fullPath = path.join(directory, entry.name);
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      results.push(
        ...(await listMarkdownFilesRecursive(fullPath, rel, rootReal, seen)),
      );
    } else if (entry.isFile() && entry.name.endsWith(".md")) {
      results.push({ relativePath: rel, fullPath });
    } else if (entry.isSymbolicLink()) {
      try {
        const targetReal = await safeRealpath(fullPath);
        if (
          !targetReal ||
          (targetReal !== rootReal && !isInsideDirectory(rootReal, targetReal))
        ) {
          continue;
        }
        const info = await stat(fullPath);
        if (info.isDirectory()) {
          results.push(
            ...(await listMarkdownFilesRecursive(
              fullPath,
              rel,
              rootReal,
              seen,
            )),
          );
        } else if (info.isFile() && entry.name.endsWith(".md")) {
          results.push({ relativePath: rel, fullPath });
        }
      } catch {
        // Ignore broken symlinks.
      }
    }
  }
  return results;
}

function sanitizeCommandName(rawName: string): string {
  return rawName.trim().replace(/^\/+/, "");
}

function buildCommandEntry(
  name: string,
  frontmatter: SkillFrontmatter,
): AvailableSlashCommand {
  const description =
    frontmatter.kind === "parsed" && frontmatter.description
      ? frontmatter.description
      : "";
  const hint =
    frontmatter.kind === "parsed" ? frontmatter.argumentHint : undefined;
  return {
    name,
    description,
    ...(hint ? { input: { hint } } : {}),
  };
}

function resolveClaudeConfigDirPath(input: {
  readonly cwd: string;
  readonly configDir?: string;
  readonly homeDir: string;
  readonly env: NodeJS.ProcessEnv;
}): string {
  const explicit = input.configDir?.trim() ?? "";
  if (explicit.length > 0) {
    return path.resolve(input.cwd, expandHomePath(explicit, input.homeDir));
  }
  const envDir = input.env.CLAUDE_CONFIG_DIR?.trim() ?? "";
  if (envDir.length > 0) {
    return path.resolve(input.cwd, expandHomePath(envDir, input.homeDir));
  }
  return path.join(input.homeDir, ".claude");
}

/**
 * Discovers user, project, additional-directory, and enabled plugin skills/commands on disk.
 * Follows T3 `ClaudeSkills.ts:506-607` (first name wins, user > project > plugins).
 */
export async function discoverClaudeSkills(
  options: DiscoverSkillsOptions,
): Promise<AvailableSlashCommand[]> {
  const env = options.env ?? process.env;
  const homeDir = options.homeDir ?? os.homedir();
  const platform = options.platform ?? process.platform;
  const cwd = path.resolve(options.cwd);
  const configDirPath = resolveClaudeConfigDirPath({
    cwd,
    configDir: options.configDir,
    homeDir,
    env,
  });
  const includeManagedSettings =
    options.includeManagedSettings ??
    (options.configDir === undefined && options.homeDir === undefined);

  const { skillOverrides, enabledPlugins } = await readSkillSettings({
    configDirPath,
    cwd,
    platform,
    env,
    includeManagedSettings,
  });

  const extraDirs = (options.additionalDirectories ?? [])
    .map((dir) => dir.trim())
    .filter((dir) => dir.length > 0)
    .map((dir) => path.resolve(cwd, expandHomePath(dir, homeDir)));

  const roots: SkillRoot[] = [
    { kind: "skills", directory: path.join(configDirPath, "skills") },
    { kind: "commands", directory: path.join(configDirPath, "commands") },
    { kind: "skills", directory: path.join(cwd, ".claude", "skills") },
    { kind: "commands", directory: path.join(cwd, ".claude", "commands") },
    ...extraDirs.flatMap((dir): SkillRoot[] => [
      { kind: "skills", directory: path.join(dir, ".claude", "skills") },
      { kind: "commands", directory: path.join(dir, ".claude", "commands") },
    ]),
    ...(await discoverPluginSkillRoots({
      configDirPath,
      cwd,
      homeDir,
      enabledPlugins,
      env,
    })),
  ];

  const commandsByName = new Map<string, AvailableSlashCommand>();

  for (const root of roots) {
    if (root.kind === "commands") {
      const files = await listMarkdownFilesRecursive(root.directory);
      for (const file of files) {
        const contents = await readTextIfExists(file.fullPath);
        if (contents === undefined) {
          continue;
        }
        const frontmatter = parseSkillFrontmatter(contents);
        if (frontmatter.kind === "malformed") {
          continue;
        }
        const rawName = file.relativePath
          .replace(/\.md$/i, "")
          .split("/")
          .filter((part) => part.length > 0)
          .join(":");
        const name = sanitizeCommandName(rawName);
        if (name.length === 0 || commandsByName.has(name)) {
          continue;
        }
        if (
          frontmatter.kind === "parsed" &&
          frontmatter.userInvocable === false
        ) {
          continue;
        }
        const override = skillOverrides.get(name);
        if (override && !override.enabled) {
          continue;
        }
        commandsByName.set(name, buildCommandEntry(name, frontmatter));
      }
      continue;
    }

    const singleSkill =
      root.prefix !== undefined &&
      (await pathExists(path.join(root.directory, "SKILL.md")));

    let dirEntries: string[];
    if (singleSkill) {
      dirEntries = [path.basename(root.directory)];
    } else {
      try {
        dirEntries = (await readdir(root.directory)).sort();
      } catch {
        dirEntries = [];
      }
    }

    const canonicalSkillRoot = await safeRealpath(root.directory);
    if (!canonicalSkillRoot) {
      continue;
    }

    for (const entry of dirEntries) {
      const skillPath = singleSkill
        ? path.join(root.directory, "SKILL.md")
        : path.join(root.directory, entry, "SKILL.md");
      // A SKILL.md reached through a symlink must stay inside its root.
      const canonicalSkillPath = await safeRealpath(skillPath);
      if (
        !canonicalSkillPath ||
        !isInsideDirectory(canonicalSkillRoot, canonicalSkillPath)
      ) {
        continue;
      }
      const contents = await readTextIfExists(skillPath);
      if (contents === undefined) {
        continue;
      }
      const frontmatter = parseSkillFrontmatter(contents);
      if (frontmatter.kind === "malformed") {
        continue;
      }
      const directoryName = entry.trim();
      if (directoryName.length === 0) {
        continue;
      }

      let name = sanitizeCommandName(directoryName);
      if (root.prefix) {
        const declaredName =
          singleSkill && frontmatter.kind === "parsed" ? frontmatter.name : "";
        const unprefixed = declaredName?.startsWith(`${root.prefix}:`)
          ? declaredName.slice(root.prefix.length + 1)
          : declaredName;
        name = sanitizeCommandName(
          `${root.prefix}:${(unprefixed || entry).replace(/[^a-zA-Z0-9_-]/g, "-")}`,
        );
        if (!SKILL_MENTION_NAME_PATTERN.test(name)) {
          continue;
        }
      }

      if (name.length === 0 || commandsByName.has(name)) {
        continue;
      }
      if (
        frontmatter.kind === "parsed" &&
        frontmatter.userInvocable === false
      ) {
        continue;
      }
      const override = root.prefix ? undefined : skillOverrides.get(name);
      if (override && !override.enabled) {
        continue;
      }

      commandsByName.set(name, buildCommandEntry(name, frontmatter));
    }
  }

  return Array.from(commandsByName.values()).sort((left, right) =>
    left.name.localeCompare(right.name),
  );
}

/**
 * Merges SDK init slash commands with disk-discovered skills/commands.
 * Strips leading `/`, deduplicates case-insensitively (T3 `ClaudeProvider.ts:370-407`).
 */
export function mergeAvailableCommands(
  sdkCommands: readonly string[],
  diskCommands: readonly AvailableSlashCommand[],
): AvailableSlashCommand[] {
  const byKey = new Map<string, AvailableSlashCommand>();

  for (const rawName of sdkCommands) {
    const clean = sanitizeCommandName(rawName);
    if (clean.length === 0) {
      continue;
    }
    const key = clean.toLowerCase();
    if (!byKey.has(key)) {
      byKey.set(key, {
        name: clean,
        description: "",
      });
    }
  }

  for (const cmd of diskCommands) {
    const clean = sanitizeCommandName(cmd.name);
    if (clean.length === 0) {
      continue;
    }
    const key = clean.toLowerCase();
    const existing = byKey.get(key);
    if (!existing) {
      byKey.set(key, {
        name: clean,
        description: cmd.description,
        ...(cmd.input ? { input: { hint: cmd.input.hint } } : {}),
      });
      continue;
    }

    const description = existing.description || cmd.description || "";
    const hint = existing.input?.hint || cmd.input?.hint;
    byKey.set(key, {
      name: existing.name,
      description,
      ...(hint ? { input: { hint } } : {}),
    });
  }

  return Array.from(byKey.values());
}
