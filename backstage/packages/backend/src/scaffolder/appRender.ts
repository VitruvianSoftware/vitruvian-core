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

import { accessSync, constants } from "fs";
import { readFile, readdir, realpath, stat, writeFile } from "fs/promises";
import * as path from "path";

import type { LoggerService } from "@backstage/backend-plugin-api";
import {
  createTemplateAction,
  executeShellCommand,
} from "@backstage/plugin-scaffolder-node";

/**
 * `vitruvian:app:render` — stamp one application into an already-fetched target
 * repository by running THAT repository's own initializer engine.
 *
 * WHY THE ENGINE AND NOT A TEMPLATE
 * ---------------------------------
 * ADR-026: the initializer engine ships verbatim into every repo stamped from
 * aspect-workflows-template, so the templates that produce an application are a
 * property of the TARGET repo, not of Backstage. This action therefore owns no
 * templates at all. It validates, shells out to `aspect render-app` with the
 * workspace as cwd (the engine probes `current_dir()` to find its own mount
 * point), and then makes the result catalog-complete. Upgrading a starter is a
 * PR in the target repo; Backstage never needs redeploying for it.
 *
 * WHY cwd MATTERS
 * ---------------
 * `tools/initializer/tasks.axl::_base` resolves the engine root from
 * `ctx.std.env.current_dir()`, and `_host_module` walks up from `--out` for the
 * nearest go.mod to derive the Go import prefix, package path and the host-OCI
 * probe. Both answers are wrong (or fatal) if the command runs anywhere but the
 * workspace root.
 */

/** Action id, referenced from scaffolder templates. */
export const APP_RENDER_ACTION_ID = "vitruvian:app:render";

/**
 * The vendored Aspect CLI vintage the runtime image ships (backstage/Dockerfile).
 * Named in the missing-binary failure so the operator is pointed at the image
 * rather than left guessing.
 */
export const REQUIRED_ASPECT_VINTAGE = "2026.26.25";

/** Repo-root file the target repository must have to be a stamping target. */
export const INITIALIZER_CONFIG_REL = "tools/initializer/config.json";

/** Engine entry point MODULE.aspect must register with the Aspect CLI. */
export const INITIALIZER_TASKS_REL = "tools/initializer/tasks.axl";

/** Repo-root file that must register the engine's tasks with the Aspect CLI. */
export const MODULE_ASPECT_REL = "MODULE.aspect";

/** Repo-root catalog file whose Location this action keeps complete. */
export const ROOT_CATALOG_REL = "catalog-info.yaml";

/** `metadata.name` of the Location listing the per-app catalog files. */
export const CATALOG_LOCATION_NAME = "vitruvian-core-apps";

/**
 * snake_case, as the engine defines it: lowercase alphanumeric words joined by
 * single underscores. gazelle names Go targets after the directory, so a name
 * outside this shape produces a BUILD file gazelle immediately rewrites.
 */
export const APP_NAME_PATTERN = /^[a-z][a-z0-9]*(_[a-z0-9]+)*$/;

/** The onboarding pattern a target repository has to follow first. */
const ONBOARDING_HINT =
  "Onboard the repository first — copy the engine tree from " +
  "aspect-workflows-template into tools/initializer/ and register its tasks in " +
  "MODULE.aspect, as VitruvianSoftware/vitruvian-core#1815 did.";

export type AppRenderInput = {
  name: string;
  language: string;
  targetPath?: string;
};

export type AppRenderResult = {
  /** Workspace-relative directory the application was rendered into. */
  appPath: string;
  /** Workspace-relative path of the application's own catalog-info.yaml. */
  catalogInfoPath: string;
  /** Workspace-relative paths of every file the engine wrote. */
  renderedFiles: string[];
  /** Whether the root catalog-info.yaml gained a Location target. */
  catalogUpdated: boolean;
};

/** Injection seam so tests can drive the real binary or a stub. */
export type ShellRunner = typeof executeShellCommand;

export type RenderApplicationOptions = AppRenderInput & {
  /** Root of the already-fetched target repository. */
  workspacePath: string;
  logger: LoggerService;
  /** True when the scaffolder is doing a dry run (`ctx.isDryRun`). */
  dryRun?: boolean;
  /** Defaults to {@link executeShellCommand}. */
  exec?: ShellRunner;
};

/**
 * Normalise and contain the caller-supplied target path.
 *
 * `targetPath` reaches us from a template's form input, so it is untrusted:
 * anything that escapes the workspace would let a template write outside the
 * repository it is supposed to be stamping.
 */
export function normaliseTargetPath(name: string, targetPath?: string): string {
  const raw = (targetPath ?? "").trim() || `apps/${name}`;
  if (path.isAbsolute(raw)) {
    throw new Error(
      `targetPath must be relative to the repository root; got the absolute path ${raw}`,
    );
  }
  const normalised = path
    .normalize(raw)
    .replace(/\\/g, "/")
    .replace(/^(\.\/)+/, "")
    .replace(/\/+$/, "");
  if (normalised === "" || normalised === ".") {
    throw new Error(
      "targetPath must name a directory inside the repository, not its root",
    );
  }
  if (normalised.split("/").includes("..")) {
    throw new Error(
      `targetPath must stay inside the repository; got ${raw}, which escapes it`,
    );
  }
  return normalised;
}

/**
 * Validate the application name BEFORE the engine does. The engine's own
 * refusal talks about `--out` and gazelle internals, which is the wrong
 * vocabulary for someone who filled in a form field.
 */
export function assertValidAppName(name: string): void {
  if (!APP_NAME_PATTERN.test(name)) {
    throw new Error(
      `application name ${JSON.stringify(name)} is not snake_case: use lowercase ` +
        "letters and digits joined by single underscores (for example " +
        "`order_service`). The name becomes the directory and the Bazel target " +
        "names, so it is not free-form.",
    );
  }
}

/**
 * The engine refuses a `--out` whose basename is not the application name. It
 * is right to, but by then the operator has already waited for a repo clone.
 */
export function assertPathMatchesName(name: string, targetPath: string): void {
  const base = path.posix.basename(targetPath);
  if (base !== name) {
    throw new Error(
      `targetPath must end in a directory named after the application: ` +
        `${targetPath} ends in ${JSON.stringify(base)} but the application is ` +
        `${JSON.stringify(name)}. Use ${path.posix.join(path.posix.dirname(targetPath), name)}.`,
    );
  }
}

const exists = async (target: string): Promise<boolean> => {
  try {
    await stat(target);
    return true;
  } catch {
    return false;
  }
};

/**
 * Does MODULE.aspect actually register the engine's `render_app` task?
 *
 * The file existing is not enough: a repo can carry a MODULE.aspect from the
 * scaffold and never have wired the initializer, and in that case
 * `aspect render-app` fails with "unknown task", which reads like a broken
 * Backstage rather than an un-onboarded repo.
 */
export function registersRenderApp(moduleAspect: string): boolean {
  return moduleAspect
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("#"))
    .some(
      (line) => line.includes("use_task(") && /["']render_app["']/.test(line),
    );
}

/**
 * Assert the workspace is a repository this action can stamp into, naming the
 * onboarding pattern when it is not.
 */
export async function assertStampingTarget(
  workspacePath: string,
): Promise<void> {
  const configPath = path.join(workspacePath, INITIALIZER_CONFIG_REL);
  if (!(await exists(configPath))) {
    throw new Error(
      `the target repository is not an initializer stamping target: ` +
        `${INITIALIZER_CONFIG_REL} is missing. ${ONBOARDING_HINT}`,
    );
  }

  const moduleAspectPath = path.join(workspacePath, MODULE_ASPECT_REL);
  if (!(await exists(moduleAspectPath))) {
    throw new Error(
      `the target repository ships ${INITIALIZER_CONFIG_REL} but has no ` +
        `${MODULE_ASPECT_REL}, so the Aspect CLI does not know about the ` +
        `engine's tasks. ${ONBOARDING_HINT}`,
    );
  }

  const moduleAspect = await readFile(moduleAspectPath, "utf8");
  if (!registersRenderApp(moduleAspect)) {
    throw new Error(
      `${MODULE_ASPECT_REL} does not register the initializer's render_app ` +
        `task (expected a use_task("${INITIALIZER_TASKS_REL}", "render_app") ` +
        `line). ${ONBOARDING_HINT}`,
    );
  }
}

/**
 * Resolve where the render will REALLY write, and refuse anything outside the
 * workspace.
 *
 * A lexical check (path.resolve + startsWith) is not enough. `targetPath` is
 * joined onto a repository this action just fetched, and a repository can commit
 * a symlink: with `link -> /tmp/outside` in the tree, `link/order_service`
 * resolves lexically to `<workspace>/link/order_service` — inside the workspace
 * by every string test — while the engine's unconditional
 * `remove_dir_all(--out)` lands in /tmp/outside. So both sides are realpath'd
 * before they are compared.
 *
 * The intermediate directories usually do not exist yet, and realpath fails on a
 * path that is not there, so this walks up to the deepest EXISTING ancestor,
 * realpaths that, and re-joins the segments below it. Those segments cannot
 * themselves be symlinks — they do not exist.
 *
 * Returns the real absolute output path, which is what the engine is then given.
 */
export async function resolveContainedOutput(
  workspacePath: string,
  targetPath: string,
): Promise<string> {
  const realWs = await realpath(workspacePath);

  let existing = path.resolve(workspacePath, targetPath);
  const below: string[] = [];
  while (!(await exists(existing))) {
    const parent = path.dirname(existing);
    if (parent === existing) break; // filesystem root; nothing more to walk
    below.unshift(path.basename(existing));
    existing = parent;
  }

  const realOut = path.join(await realpath(existing), ...below);
  if (realOut !== realWs && !realOut.startsWith(realWs + path.sep)) {
    throw new Error(
      `targetPath ${targetPath} escapes the target repository: it really ` +
        `resolves to ${realOut}, which is outside ${realWs} — a symlink in the ` +
        "fetched repository points out of it. Refusing: the initializer engine " +
        "clears --out before rendering, so this would delete files outside the " +
        "repository.",
    );
  }
  return realOut;
}

/**
 * Locate the `aspect` binary on PATH without spawning anything.
 *
 * Spawning to find out would conflate "not installed" with "installed but the
 * render failed", and the two need very different messages.
 */
export function findAspectBinary(
  pathEnv: string | undefined = process.env.PATH,
): string | undefined {
  for (const dir of (pathEnv ?? "").split(path.delimiter)) {
    if (!dir) continue;
    const candidate = path.join(dir, "aspect");
    try {
      accessSync(candidate, constants.X_OK);
      return candidate;
    } catch {
      // Next PATH entry.
    }
  }
  return undefined;
}

/**
 * Locate the per-app Location's `targets:` list, or explain what is missing.
 *
 * Shared by the early shape check and the append itself so the two can never
 * disagree about what "a usable root catalog" means.
 */
export function locateAppTargets(lines: string[]): {
  targetsIdx: number;
  end: number;
} {
  const nameIdx = lines.findIndex(
    (line) => line.trim() === `name: ${CATALOG_LOCATION_NAME}`,
  );
  if (nameIdx < 0) {
    throw new Error(
      `${ROOT_CATALOG_REL} has no Location named ${CATALOG_LOCATION_NAME}, so ` +
        "there is nowhere to record the new application. Add one (a Location " +
        "whose spec.targets lists each app's catalog-info.yaml) and re-run.",
    );
  }

  let targetsIdx = -1;
  for (let i = nameIdx + 1; i < lines.length; i++) {
    if (lines[i].trimEnd() === "---") break;
    if (lines[i] === "  targets:") {
      targetsIdx = i;
      break;
    }
  }
  if (targetsIdx < 0) {
    throw new Error(
      `the ${CATALOG_LOCATION_NAME} Location in ${ROOT_CATALOG_REL} has no ` +
        "`  targets:` list to append to.",
    );
  }

  // The list ends at the first line that is neither an item nor an indented
  // comment.
  let end = targetsIdx + 1;
  while (end < lines.length && /^ {2,}(- |#)/.test(lines[end])) end++;

  return { targetsIdx, end };
}

/**
 * The target a list line refers to, indentation and a leading `./` removed, or
 * undefined if the line is not a list item.
 *
 * Idempotency must not key on the exact bytes this action emits: a target
 * already written by hand as `  - apps/x/catalog-info.yaml` (two-space indent,
 * no `./`) is the SAME entry, and matching only the canonical spelling would
 * append a duplicate. The canonical spelling is still what gets written.
 */
export function catalogTargetOf(line: string): string | undefined {
  const match = /^\s+-\s+(\S.*?)\s*$/.exec(line);
  if (!match) return undefined;
  return match[1].replace(/^\.\//, "");
}

/**
 * Insert `targetPath`'s catalog file into the root catalog's per-app Location.
 *
 * ADR-019 disclose-and-include: the stamping PR has to be catalog-complete, or
 * the new component simply never appears in Backstage and someone has to notice
 * and open a second PR. Idempotent across spellings — see {@link catalogTargetOf}.
 */
export function appendCatalogTarget(
  content: string,
  targetPath: string,
): { content: string; changed: boolean } {
  const wanted = `${targetPath}/catalog-info.yaml`;
  const lines = content.split("\n");

  const { targetsIdx, end } = locateAppTargets(lines);

  // Scoped to this Location's own list: an identically-named path under a
  // different Location is a different statement, and is none of our business.
  for (let i = targetsIdx + 1; i < end; i++) {
    if (catalogTargetOf(lines[i]) === wanted) {
      return { content, changed: false };
    }
  }

  // Match the list's OWN indentation rather than assuming four spaces: a
  // two-space list would read a four-space item as a nested sequence, which is
  // valid YAML meaning something else entirely.
  const dash = /^(\s+)- /;
  let indent = "    ";
  for (let i = targetsIdx + 1; i < end; i++) {
    const match = dash.exec(lines[i]);
    if (match) {
      indent = match[1];
      break;
    }
  }
  const entry = `${indent}- ./${targetPath}/catalog-info.yaml`;

  // Keep the leading (uncommented) run sorted, which is how the file is
  // maintained by hand; a trailing commented group — "Platform infrastructure
  // we operate" — is deliberately left alone.
  let insertAt = targetsIdx + 1;
  for (let i = targetsIdx + 1; i < end; i++) {
    if (!lines[i].startsWith(`${indent}- `)) break;
    if (lines[i] > entry) {
      insertAt = i;
      break;
    }
    insertAt = i + 1;
  }

  lines.splice(insertAt, 0, entry);
  return { content: lines.join("\n"), changed: true };
}

/**
 * Fail-early counterpart to {@link appendCatalogTarget}: prove the root catalog
 * has somewhere to record the app BEFORE the engine runs.
 *
 * Without this, a malformed catalog is only discovered after a full render, so
 * the operator waits out a clone and a render to be told about a YAML shape
 * problem. The append itself stays authoritative; this only front-runs it.
 * A repository with no root catalog at all is not an error — that is warned
 * about after the render, as before.
 */
export async function assertCatalogAppendable(
  workspacePath: string,
): Promise<void> {
  const catalogPath = path.join(workspacePath, ROOT_CATALOG_REL);
  if (!(await exists(catalogPath))) return;
  locateAppTargets((await readFile(catalogPath, "utf8")).split("\n"));
}

/** Every file under `dir`, as paths relative to `root`, sorted. */
async function listFiles(root: string, dir: string): Promise<string[]> {
  const out: string[] = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...(await listFiles(root, abs)));
    } else {
      out.push(path.relative(root, abs));
    }
  }
  return out.sort();
}

/**
 * The action's whole behaviour, free of any scaffolder types so it can be
 * driven directly by tests (including against the real `aspect` binary).
 */
export async function renderApplication(
  options: RenderApplicationOptions,
): Promise<AppRenderResult> {
  const {
    workspacePath,
    name,
    language,
    logger,
    dryRun = false,
    exec = executeShellCommand,
  } = options;

  const targetPath = normaliseTargetPath(name, options.targetPath);
  assertValidAppName(name);
  assertPathMatchesName(name, targetPath);

  // Lexical containment first: it needs no filesystem and gives the clearest
  // message for the `..` case. It is NOT sufficient on its own — see
  // resolveContainedOutput below, which is the check that actually protects the
  // filesystem and needs the workspace to be on disk.
  if (
    !path
      .resolve(workspacePath, targetPath)
      .startsWith(path.resolve(workspacePath) + path.sep)
  ) {
    throw new Error(
      `targetPath must stay inside the repository; ${targetPath} resolves to ` +
        path.resolve(workspacePath, targetPath),
    );
  }

  await assertStampingTarget(workspacePath);
  // Fail early on a root catalog with nowhere to record the app, rather than
  // after a full render.
  await assertCatalogAppendable(workspacePath);

  // Now that the workspace is known to exist and to be a stamping target,
  // resolve where the render will REALLY land — this is what defeats a symlink
  // committed in the fetched repository, which every lexical check passes.
  const outAbs = await resolveContainedOutput(workspacePath, targetPath);

  // REFUSE rather than overwrite. `render_app` clears `--out` before rendering
  // (tasks.axl: remove_dir_all(out_abs)), so stamping onto an existing app
  // would delete it and the resulting PR would read as a mass deletion.
  if (await exists(outAbs)) {
    throw new Error(
      `${targetPath} already exists in the target repository; stamping over an ` +
        "existing application is not supported. The initializer engine clears " +
        "--out before rendering, so this would delete the application that is " +
        "there. Pick a different name, or change the existing application by " +
        "hand.",
    );
  }

  const aspectBin = findAspectBinary();
  if (!aspectBin) {
    throw new Error(
      "the `aspect` CLI is not on PATH, so the target repository's own " +
        "initializer engine cannot be run. The Backstage runtime image vendors " +
        `it (aspect ${REQUIRED_ASPECT_VINTAGE}, see backstage/Dockerfile); a ` +
        "backend running outside that image must install the same vintage.",
    );
  }

  const args = [
    "render-app",
    "--language",
    language,
    "--name",
    name,
    "--out",
    outAbs,
  ];

  logger.info(
    `${APP_RENDER_ACTION_ID}: running the target repository's own initializer ` +
      `engine: ${aspectBin} ${args.join(" ")} (cwd ${workspacePath})` +
      (dryRun ? " [dry run]" : ""),
  );

  // Streamed, not buffered: the scaffolder UI shows a step as stalled when it
  // goes quiet for a minute, and a cold engine run can.
  //
  // Deliberately NOT wrapped in ctx.checkpoint. A checkpoint replays its
  // recorded RESULT on a retry, and the render's result is files on disk in a
  // workspace that a retry has already thrown away — so the second run would
  // "succeed" into an empty directory. The render is cheap and idempotent; the
  // refusal above is what makes re-running safe.
  await exec({
    // The RESOLVED path, so the command that runs is the one the log named.
    command: aspectBin,
    args,
    logger,
    options: { cwd: workspacePath },
  });

  // A zero exit with nothing on disk is not success. It happens when the image's
  // engine and the repo's engine disagree — a task that parses, runs, and writes
  // somewhere else. Surfacing readdir's raw ENOENT would send the operator
  // looking for a filesystem problem instead.
  // Listed relative to `outAbs` and re-prefixed with `targetPath`, NOT relative
  // to `workspacePath`: `outAbs` has been realpath'd and the workspace may not
  // be (macOS hands out /var/... for /private/var/...), so relativising one
  // against the other would emit `../../..` paths.
  let renderedFiles: string[] = [];
  try {
    renderedFiles = (await listFiles(outAbs, outAbs)).map((file) =>
      path.posix.join(targetPath, file.split(path.sep).join("/")),
    );
  } catch {
    renderedFiles = [];
  }
  if (renderedFiles.length === 0) {
    throw new Error(
      `the initializer engine reported success but produced no files at ` +
        `${targetPath}. The repository's engine (${INITIALIZER_TASKS_REL}) and ` +
        `the vendored CLI (aspect ${REQUIRED_ASPECT_VINTAGE}) may not be ` +
        "compatible — check that `aspect render-app` works in that repository.",
    );
  }

  // catalogInfoPath is a promise this action makes to the template's later
  // catalog:register step; if the starter did not render one, that step fails
  // far from the cause.
  const catalogInfoPath = path.posix.join(targetPath, "catalog-info.yaml");
  if (!renderedFiles.includes(catalogInfoPath)) {
    throw new Error(
      `the ${language} starter rendered ${renderedFiles.length} file(s) into ` +
        `${targetPath} but no catalog-info.yaml, so the new component cannot be ` +
        "registered with the catalog. The starter's template directory in the " +
        "target repository needs one.",
    );
  }

  logger.info(
    `${APP_RENDER_ACTION_ID}: rendered ${renderedFiles.length} file(s) into ${targetPath}:\n` +
      renderedFiles.map((f) => `  ${f}`).join("\n"),
  );

  const catalogPath = path.join(workspacePath, ROOT_CATALOG_REL);
  let catalogUpdated = false;
  if (await exists(catalogPath)) {
    const before = await readFile(catalogPath, "utf8");
    const { content, changed } = appendCatalogTarget(before, targetPath);
    if (changed) {
      await writeFile(catalogPath, content, "utf8");
      catalogUpdated = true;
      // Disclose: this action edits a file the operator did not name, and the
      // PR diff will show it.
      logger.info(
        `${APP_RENDER_ACTION_ID}: edited ${ROOT_CATALOG_REL} — added ` +
          `"./${targetPath}/catalog-info.yaml" to the ${CATALOG_LOCATION_NAME} ` +
          "Location so the new component is discovered by the catalog.",
      );
    } else {
      logger.info(
        `${APP_RENDER_ACTION_ID}: ${ROOT_CATALOG_REL} already lists ` +
          `"./${targetPath}/catalog-info.yaml"; left unchanged.`,
      );
    }
  } else {
    logger.warn(
      `${APP_RENDER_ACTION_ID}: the target repository has no ${ROOT_CATALOG_REL}, ` +
        "so the new application was not registered with the catalog. Add the " +
        "component by hand, or add a root catalog Location to the repository.",
    );
  }

  return {
    appPath: targetPath,
    catalogInfoPath,
    renderedFiles,
    catalogUpdated,
  };
}

/**
 * The scaffolder action wrapper. Deliberately thin: everything worth testing
 * lives in {@link renderApplication}.
 */
export const createAppRenderAction = () =>
  createTemplateAction({
    id: APP_RENDER_ACTION_ID,
    description:
      "Stamp a new application into the fetched repository by running that " +
      "repository's own initializer engine (aspect render-app), then add it to " +
      "the root catalog Location.",
    // Rendering happens inside the scaffolder's throwaway workspace, so a dry
    // run does the real work and simply never gets published.
    supportsDryRun: true,
    schema: {
      input: {
        name: (z) =>
          z
            .string()
            .describe("Application name in snake_case, e.g. order_service"),
        language: (z) =>
          z
            .string()
            .describe(
              "Language key from the target repo's tools/initializer/config.json",
            ),
        targetPath: (z) =>
          z
            .string()
            .optional()
            .describe(
              "Directory to stamp into, relative to the repo root; its basename " +
                "must equal the application name. Defaults to apps/<name>.",
            ),
      },
      output: {
        appPath: (z) => z.string(),
        catalogInfoPath: (z) => z.string(),
      },
    },
    async handler(ctx) {
      const result = await renderApplication({
        workspacePath: ctx.workspacePath,
        name: ctx.input.name,
        language: ctx.input.language,
        targetPath: ctx.input.targetPath,
        logger: ctx.logger,
        dryRun: ctx.isDryRun,
      });
      ctx.output("appPath", result.appPath);
      ctx.output("catalogInfoPath", result.catalogInfoPath);
    },
  });
