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
import { readFile, readdir, stat, writeFile } from "fs/promises";
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
 * Insert `targetPath`'s catalog file into the root catalog's per-app Location.
 *
 * ADR-019 disclose-and-include: the stamping PR has to be catalog-complete, or
 * the new component simply never appears in Backstage and someone has to notice
 * and open a second PR. Idempotent by construction — the exact line is matched
 * first, so re-running the action (a retried task, a template that renders twice)
 * cannot duplicate it.
 */
export function appendCatalogTarget(
  content: string,
  targetPath: string,
): { content: string; changed: boolean } {
  const entry = `    - ./${targetPath}/catalog-info.yaml`;
  const lines = content.split("\n");
  if (lines.includes(entry)) {
    return { content, changed: false };
  }

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
  // comment. Keep the leading (uncommented) run sorted, which is how the file
  // is maintained by hand; a trailing commented group — "Platform
  // infrastructure we operate" — is deliberately left alone.
  let end = targetsIdx + 1;
  while (end < lines.length && /^ {4}(- |#)/.test(lines[end])) end++;

  let insertAt = targetsIdx + 1;
  for (let i = targetsIdx + 1; i < end; i++) {
    if (!lines[i].startsWith("    - ")) break;
    if (lines[i] > entry) {
      insertAt = i;
      break;
    }
    insertAt = i + 1;
  }

  lines.splice(insertAt, 0, entry);
  return { content: lines.join("\n"), changed: true };
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

  const outAbs = path.resolve(workspacePath, targetPath);
  // Belt-and-braces containment: normaliseTargetPath already rejects `..`, but
  // this is the check that actually protects the filesystem, so it is made
  // against the resolved path rather than against the string it came from.
  if (!outAbs.startsWith(path.resolve(workspacePath) + path.sep)) {
    throw new Error(
      `targetPath must stay inside the repository; ${targetPath} resolves to ${outAbs}`,
    );
  }

  await assertStampingTarget(workspacePath);

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
    command: "aspect",
    args,
    logger,
    options: { cwd: workspacePath },
  });

  const renderedFiles = await listFiles(workspacePath, outAbs);
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
    catalogInfoPath: path.posix.join(targetPath, "catalog-info.yaml"),
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
