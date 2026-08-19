# Application Initializer P0 — Composition Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `aspect-workflows-template` an application-composition core — a validated
metadata contract, a `render-app` task that renders one application subtree for a
language + concern selection, a base Go application template, and two self-checking test
tasks — so every later frontend (Backstage, HTTP service, CLI) is a transport over one
engine.

**Architecture:** All work is in the **`aspect-workflows-template`** repo, branch base
`platform-v2.0`. A new `app.axl` library holds the application-side contract loading and
validation; `dev.axl` gains three tasks (`render-app`, `check-metadata`, `check-renders`)
registered through `MODULE.aspect`. Application templates live at `template/app/<language>/`
and are excluded from repo stamping by a single `rules` entry. Nothing in the existing
repo-stamping path (`render-preset`, `template/`, the 28 presets, `deliver.yaml`) changes
behaviour.

**Tech Stack:** AXL (Starlark dialect) executed by the Aspect CLI; minijinja for template
expansion via `ctx.template.jinja2`; JSON for the contract; Go 1.x + `rules_go` for the
first application template; GitHub Actions for CI wiring.

## Global Constraints

- **Repo:** `VitruvianSoftware/aspect-workflows-template`, base branch **`platform-v2.0`**
  (not `main`). Every PR targets `platform-v2.0`.
- **Spec:** `docs/superpowers/specs/2026-08-18-universal-initializer-design.md` in
  `vitruvian-core`. ADR numbers referenced below are from its §11.
- **Starlark limits:** no recursion, no `while`. Use a bounded `for _ in range(N)` worklist,
  exactly as `render.axl:_walk` does.
- **Available AXL primitives** (the complete set this repo uses — do not invent others):
  `ctx.std.fs.{read_to_string, write, copy, exists, create_dir_all, remove_dir_all,
  read_dir, set_permissions}`, `ctx.std.io.stdout.write`, `ctx.std.env.current_dir()`,
  `ctx.std.process.command`, `ctx.template.jinja2(content, data = {...})`, `json.decode`,
  `fail(msg)`, `task(kind=, summary=, implementation=, args={})`, `args.string(...)`.
- **`ctx.std.fs.read_dir(path)`** returns entries with `.path` (basename) and `.is_dir`.
- **Glob relativity:** `rules` / `no_render` / `executable` globs are matched against paths
  relative to whichever `template_dir` was passed to `render()`. The `app` section carries
  its **own** three arrays for this reason (ADR-024).
- **Do not modify** `render.axl`'s existing public functions, `render_preset`, the 28
  presets, or anything under `template/` outside `template/app/`. Repo stamping is a
  separate product (spec §1) and must be provably unaffected.
- **Naming:** tasks are kebab-case (`render-app`), AXL symbols snake_case, matching
  `render.axl`/`dev.axl`.
- **Commit style:** conventional commits; body explains *why*, not just what.

---

### Task 1: Application metadata contract + `check-metadata`

Adds the `app` section to `template-config.json` and an `app.axl` library that loads and
validates it, exposed as `aspect check-metadata` (tier 1 of spec §10). Validation is the
system's first check of any kind — today nothing validates anything.

**Files:**
- Create: `app.axl`
- Modify: `template-config.json` (add top-level `"app"` key)
- Modify: `dev.axl` (add `check_metadata` task)
- Modify: `MODULE.aspect` (register the task)

**Interfaces:**
- Consumes: `load_config(ctx, repo_dir)` from `render.axl` (returns the parsed
  `template-config.json` dict).
- Produces:
  - `app_config(config) -> dict` — returns `config["app"]`, failing if absent.
  - `validate_app_config(config) -> list[str]` — returns a list of human-readable problem
    strings; empty list means valid. Pure function of the config, no `ctx`, so it is
    directly testable.
  - `resolve_concerns(app, language, concerns) -> list[str]` — expands the requested
    concern list under `requires` closure, sorted, failing on unknown names or a language
    that does not declare the concern in `appliesTo`.
  - `app_flags(app, language, concerns, http_framework, deploy_target, db_provider) -> dict`
    — the flag dict handed to `render()`.

- [ ] **Step 1: Write the failing check task**

Create `app.axl` with only the validator (the contract itself comes in Step 3, so the task
fails first):

```python
"""Application-side contract: loading, validation, and flag construction.

Repo stamping (render-preset, template/) composes a whole monorepo. Application
stamping composes ONE application inside an existing monorepo -- a different
product (see the design spec, section 1), so it gets its own section of
template-config.json and its own rules/no_render/executable arrays. Globs are
matched relative to whichever template_dir render() is given, which is why the
two cannot share one array.
"""

APP_KEY = "app"

def app_config(config):
    """Return the `app` section, failing loudly if the contract is missing."""
    if APP_KEY not in config:
        fail("template-config.json has no {!r} section; the application initializer cannot run".format(APP_KEY))
    return config[APP_KEY]

def _require_keys(where, obj, keys, problems):
    for k in keys:
        if k not in obj:
            problems.append("{}: missing required key {!r}".format(where, k))

def validate_app_config(config):
    """Return a list of problems with the `app` section. Empty means valid.

    Pure: takes the parsed config, returns strings. No ctx, no filesystem, so it
    is callable from a check task and from any future consumer.
    """
    problems = []
    if APP_KEY not in config:
        return ["template-config.json has no {!r} section".format(APP_KEY)]
    app = config[APP_KEY]

    _require_keys("app", app, ["languages", "concerns", "deploy_targets", "presets", "rules", "no_render", "executable"], problems)
    if problems:
        return problems

    languages = app["languages"]
    concerns = app["concerns"]

    # Every concern's requires must name a real concern, and appliesTo a real language.
    for name in sorted(concerns.keys()):
        spec = concerns[name]
        for req in spec.get("requires", []):
            if req not in concerns:
                problems.append("concern {!r}: requires unknown concern {!r}".format(name, req))
        for lang in spec.get("appliesTo", []):
            if lang not in languages:
                problems.append("concern {!r}: appliesTo unknown language {!r}".format(name, lang))

    # The requires graph must be acyclic. Starlark has no recursion, so resolve by
    # repeated relaxation: a concern is "settled" once all its requires are settled.
    settled = {}
    for _ in range(100):
        progressed = False
        for name in sorted(concerns.keys()):
            if name in settled:
                continue
            reqs = [r for r in concerns[name].get("requires", []) if r in concerns]
            if all([r in settled for r in reqs]):
                settled[name] = True
                progressed = True
        if not progressed:
            break
    for name in sorted(concerns.keys()):
        if name not in settled:
            problems.append("concern {!r}: requires graph is cyclic or unresolvable".format(name))

    # Each language must point at a template directory.
    for name in sorted(languages.keys()):
        _require_keys("language {!r}".format(name), languages[name], ["label", "template_dir"], problems)

    # Deploy targets: the default provider must be one of the offered providers.
    for name in sorted(app["deploy_targets"].keys()):
        target = app["deploy_targets"][name]
        _require_keys("deploy_target {!r}".format(name), target, ["label", "db_providers", "default_db_provider"], problems)
        if "db_providers" in target and "default_db_provider" in target:
            if target["default_db_provider"] not in target["db_providers"]:
                problems.append("deploy_target {!r}: default_db_provider {!r} is not in db_providers {}".format(
                    name, target["default_db_provider"], target["db_providers"]))

    # Presets must name a real language and real concerns, closed under requires.
    for name in sorted(app["presets"].keys()):
        preset = app["presets"][name]
        _require_keys("preset {!r}".format(name), preset, ["language", "concerns"], problems)
        if "language" in preset and preset["language"] not in languages:
            problems.append("preset {!r}: unknown language {!r}".format(name, preset["language"]))
        for c in preset.get("concerns", []):
            if c not in concerns:
                problems.append("preset {!r}: unknown concern {!r}".format(name, c))
                continue
            for req in concerns[c].get("requires", []):
                if req not in preset["concerns"]:
                    problems.append("preset {!r}: concern {!r} requires {!r}, which the preset omits".format(name, c, req))

    return problems
```

Add the task to `dev.axl` — append the load line to the existing one at the top and the
task at the bottom:

```python
load("./app.axl", "validate_app_config")
```

```python
def _check_metadata_impl(ctx):
    repo_dir = ctx.std.env.current_dir()
    config = load_config(ctx, repo_dir)
    problems = validate_app_config(config)
    if problems:
        ctx.std.io.stdout.write("check-metadata: {} problem(s)\n".format(len(problems)))
        for p in problems:
            ctx.std.io.stdout.write("  - {}\n".format(p))
        fail("application metadata contract is invalid")
    ctx.std.io.stdout.write("check-metadata: OK\n")
    return 0

check_metadata = task(
    kind = "check-metadata",
    summary = "Validate the application metadata contract in template-config.json",
    implementation = _check_metadata_impl,
    args = {},
)
```

Register it in `MODULE.aspect`:

```python
use_task("dev.axl", "render_preset")
use_task("dev.axl", "check_metadata")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `aspect check-metadata`
Expected: FAIL — `template-config.json has no 'app' section` then
`application metadata contract is invalid`. This proves the check runs and that the
contract really is absent, rather than the check silently passing on nothing.

- [ ] **Step 3: Add the `app` section to `template-config.json`**

Insert as a new top-level key (sibling of `flags`, `presets`, `rules`, `no_render`,
`executable`). Concerns are **declared** here in full — P2 implements their templates, but
the contract is the thing every frontend reads, and retrofitting it later is the expensive
version of this change (ADR-023).

```json
  "app": {
    "languages": {
      "go": { "label": "Go", "wave": 1, "template_dir": "app/go" }
    },
    "concerns": {
      "svc_config":      { "label": "Typed configuration", "requires": [],               "appliesTo": ["go"] },
      "svc_logging":     { "label": "Structured logging",  "requires": ["svc_config"],   "appliesTo": ["go"] },
      "svc_http":        { "label": "HTTP service",        "requires": ["svc_config"],   "appliesTo": ["go"] },
      "svc_otel":        { "label": "OpenTelemetry",       "requires": ["svc_logging"],  "appliesTo": ["go"] },
      "svc_db_postgres": { "label": "Postgres",            "requires": ["svc_config"],   "appliesTo": ["go"] },
      "svc_deploy":      { "label": "Deploy to cluster",   "requires": ["svc_http"],     "appliesTo": ["go"] }
    },
    "deploy_targets": {
      "homelab":  { "label": "Homelab ArgoCD", "db_providers": ["cnpg"],             "default_db_provider": "cnpg" },
      "cloudrun": { "label": "Cloud Run",      "db_providers": ["cloudsql", "neon"], "default_db_provider": "cloudsql" }
    },
    "http_frameworks": {
      "go": { "options": ["chi", "gin", "nethttp"], "default": "chi" }
    },
    "presets": {
      "go-minimal": { "language": "go", "concerns": [] }
    },
    "rules": [],
    "no_render": [],
    "executable": []
  }
```

- [ ] **Step 4: Run it to verify it passes**

Run: `aspect check-metadata`
Expected: PASS — `check-metadata: OK`

- [ ] **Step 5: Falsify the validator — prove each rule can fail**

Do not trust a validator that has only ever seen valid input. Make each mutation, run
`aspect check-metadata`, confirm the specific message, then revert:

| Mutation | Expected message |
|---|---|
| `svc_http.requires` → `["svc_nonexistent"]` | `requires unknown concern 'svc_nonexistent'` |
| `svc_config.requires` → `["svc_http"]` (cycle with svc_http) | `requires graph is cyclic or unresolvable` |
| `svc_http.appliesTo` → `["rust"]` | `appliesTo unknown language 'rust'` |
| `cloudrun.default_db_provider` → `"cnpg"` | `default_db_provider 'cnpg' is not in db_providers` |
| `go-minimal.concerns` → `["svc_http"]` | `concern 'svc_http' requires 'svc_config', which the preset omits` |

All five must fail, and `aspect check-metadata` must return to OK after the last revert.

- [ ] **Step 6: Commit**

```bash
git add app.axl dev.axl MODULE.aspect template-config.json
git commit -m "feat(app): add the application metadata contract and validate it

The template repo has never validated anything: render-preset fails on an
unknown preset NAME, but no flag combination, requires-chain or provider
mapping is checked, and the 28 presets are known-good only because CI builds
them. The application initializer cannot work that way -- every frontend
(Backstage form, HTTP service, CLI) must enforce the same rules, so the rules
have to live in one place and be executable.

app.axl adds validate_app_config as a PURE function of the parsed config, so
the same code answers 'is this valid' for a check task and for a request
arriving from any transport. aspect check-metadata is tier 1 of the spec's
testing model.

The contract declares all six concerns, both deploy targets and the per-target
database providers now, even though P2 implements their templates. Provider is
an enumeration keyed by deploy target rather than a boolean (ADR-023), and
retrofitting a dimension into a boolean later is the expensive version of that
change.

Falsified rather than assumed: each of the five validation rules was broken in
turn and the specific message confirmed, then reverted."
```

---

### Task 2: Base Go application template + repo-stamping exclusion

Creates `template/app/go/` and the single `rules` entry that keeps it out of every stamped
monorepo. The exclusion is load-bearing: `is_included` includes any path matched by no
rule, so without it all 26 starter repos silently gain an `app/` directory (ADR-024).

**Files:**
- Create: `template/app/go/BUILD.bazel`
- Create: `template/app/go/main.go`
- Create: `template/app/go/main_test.go`
- Create: `template/app/go/catalog-info.yaml`
- Create: `template/app/go/README.md`
- Modify: `template-config.json` (one entry in the top-level `rules`; populate `app.rules`)

**Interfaces:**
- Consumes: nothing from Task 1 at runtime; the `app.languages.go.template_dir` value
  (`app/go`) declared in Task 1 must match this directory.
- Produces: the tree `render-app` (Task 3) renders. Jinja variables available to these
  files are exactly those `render.axl:render()` injects: `project_snake`, `project_kebab`,
  `project_pascal`, `project_name`, plus every key of the flags dict.

- [ ] **Step 1: Write the failing test — prove the exclusion is needed**

There is no app tree yet, so first demonstrate the leak the rule prevents. Create the
directory with one file and render an existing preset:

```bash
mkdir -p template/app/go && echo "package main" > template/app/go/main.go
aspect render-preset --preset=go --out=/tmp/leak-check --name=my_project
ls /tmp/leak-check/app 2>/dev/null && echo "LEAKED: app/ appears in a stamped monorepo"
```

Expected: `LEAKED: app/ appears in a stamped monorepo`. This is the failure the rule fixes;
seeing it once is what proves the rule is doing work.

- [ ] **Step 2: Add the exclusion rule**

In `template-config.json`, append to the **top-level** `rules` array:

```json
    { "flag": "app_template", "globs": ["app/**"] }
```

`app_template` is declared by no preset. `_predicate_true` reads flags with
`flags.get(name, False)` (`render.axl:45`), so an undeclared flag is false everywhere and
the path is excluded from every render — with zero edits to the 28 presets.

- [ ] **Step 3: Run the render again to verify the leak is closed**

```bash
rm -rf /tmp/leak-check
aspect render-preset --preset=go --out=/tmp/leak-check --name=my_project
ls /tmp/leak-check/app 2>/dev/null && echo "STILL LEAKING" || echo "OK: app/ excluded from repo stamping"
```

Expected: `OK: app/ excluded from repo stamping`

- [ ] **Step 4: Write the application template files**

`template/app/go/main.go` — a runnable program, not a library stub, so the rendered
application does something observable on day one:

```go
// Package main is the {{ project_name }} application entrypoint.
package main

import (
	"fmt"
	"os"
)

func main() {
	if err := run(os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(out *os.File) error {
	_, err := fmt.Fprintf(out, "{{ project_name }} started\n")
	return err
}
```

`template/app/go/main_test.go`:

```go
package main

import (
	"os"
	"strings"
	"testing"
)

func TestRunWritesStartupLine(t *testing.T) {
	f, err := os.CreateTemp(t.TempDir(), "out")
	if err != nil {
		t.Fatalf("CreateTemp: %v", err)
	}
	if err := run(f); err != nil {
		t.Fatalf("run: %v", err)
	}
	b, err := os.ReadFile(f.Name())
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if !strings.Contains(string(b), "started") {
		t.Errorf("run() wrote %q, want it to contain %q", string(b), "started")
	}
}
```

`template/app/go/BUILD.bazel` — **no `# gazelle:ignore`**, unlike `template/hello/go`.
That sample is hand-curated and opts out; a stamped application is real code that gazelle
must manage, and Task 5's fixed-point check depends on these targets being exactly what
gazelle generates:

```python
load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "{{ project_kebab }}_lib",
    srcs = ["main.go"],
    importpath = "example.com/{{ project_snake }}/app/{{ project_kebab }}",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "{{ project_kebab }}",
    embed = [":{{ project_kebab }}_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "{{ project_kebab }}_test",
    srcs = ["main_test.go"],
    embed = [":{{ project_kebab }}_lib"],
)
```

`template/app/go/catalog-info.yaml` — every application in `vitruvian-core` carries one,
and `catalog:register` in the Backstage flow (P1) needs it to exist:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: {{ project_kebab }}
  description: {{ project_name }}, stamped by the application initializer
spec:
  type: service
  lifecycle: experimental
  owner: platform-team
```

`template/app/go/README.md`:

```markdown
# {{ project_name }}

Stamped by the application initializer.

    bazel run //app/{{ project_kebab }}
    bazel test //app/{{ project_kebab }}:all
```

- [ ] **Step 5: Declare the app-side arrays**

Set `app.rules`, `app.no_render` and `app.executable` in `template-config.json`. These
globs are relative to `template/app/<language>/`, not to `template/` — the reason the app
section has its own arrays at all:

```json
    "rules": [],
    "no_render": [],
    "executable": []
```

They stay empty in P0: the base Go template has no conditional files and nothing to copy
verbatim. Task 4's smoke check asserts they are *present and valid*, so P2 can populate
them without touching the schema.

- [ ] **Step 6: Verify repo stamping is still byte-identical**

The whole product must be provably unaffected (spec §1). Render a preset before and after
this branch's changes and diff:

```bash
git stash
aspect render-preset --preset=backstage-go --out=/tmp/before --name=my_project
git stash pop
aspect render-preset --preset=backstage-go --out=/tmp/after --name=my_project
diff -r /tmp/before /tmp/after && echo "OK: repo stamping unchanged"
```

Expected: `OK: repo stamping unchanged` with no diff output.

- [ ] **Step 7: Commit**

```bash
git add template/app/go template-config.json
git commit -m "feat(app): add the base Go application template, excluded from repo stamping

template/app/go/ is the first application template -- the thing render-app
renders and the thing every frontend ultimately produces. It lives under
template/ rather than in a sibling tree (ADR-024) so one renderer walks one
tree, which also makes deriving hello/<lang> from it later a path question
rather than a cross-tree sync.

The one-line rules entry is load-bearing, not tidiness. is_included includes
any path matched by NO rule, so without it every one of the 26 starter repos
silently gains an app/ directory -- a failure that would surface as mysterious
files in published repos rather than as an error. Verified by reproducing the
leak first, then closing it. The flag it gates on is declared by no preset, and
_predicate_true reads flags with .get(name, False), so nothing else changed.

Unlike template/hello/go this BUILD.bazel does NOT carry gazelle:ignore. The
hello sample is hand-curated and opts out; a stamped application is real code
gazelle must manage, and the fixed-point assertion depends on these targets
being exactly what gazelle generates.

Repo stamping proven unaffected by rendering backstage-go before and after and
diffing the trees."
```

---

### Task 3: `render-app` task

The engine entry point every frontend calls: validate a selection, then render one
language's application subtree.

**Files:**
- Modify: `app.axl` (add `resolve_concerns`, `app_flags`)
- Modify: `dev.axl` (add the `render_app` task)
- Modify: `MODULE.aspect` (register it)

**Interfaces:**
- Consumes: `app_config`, `validate_app_config` (Task 1); `load_config` and
  `render(ctx, config, template_dir, out_dir, project_snake, flags)` from `render.axl`;
  the `template/app/go/` tree (Task 2).
- Produces: `aspect render-app --language <l> --concerns <csv> --name <n> --out <dir>
  [--deploy-target <t>] [--db-provider <p>] [--http-framework <f>]`, writing the rendered
  application into `<out>` and printing one line per rendered file count.

- [ ] **Step 1: Write the failing test**

Add to `app.axl`:

```python
def resolve_concerns(app, language, concerns):
    """Expand `concerns` under the requires closure. Fails on anything unknown.

    Returns a sorted list. Starlark has no recursion, so the closure is computed
    by bounded relaxation -- the same shape render.axl:_walk uses for its walk.
    """
    known = app["concerns"]
    if language not in app["languages"]:
        fail("unknown language {!r}; known: {}".format(language, ", ".join(sorted(app["languages"].keys()))))
    selected = {}
    for c in concerns:
        if c not in known:
            fail("unknown concern {!r}; known: {}".format(c, ", ".join(sorted(known.keys()))))
        selected[c] = True
    for _ in range(100):
        added = False
        for c in sorted(selected.keys()):
            for req in known[c].get("requires", []):
                if req not in selected:
                    selected[req] = True
                    added = True
        if not added:
            break
    for c in sorted(selected.keys()):
        applies = known[c].get("appliesTo", [])
        if applies and language not in applies:
            fail("concern {!r} does not apply to language {!r}".format(c, language))
    return sorted(selected.keys())

def app_flags(app, language, concerns, http_framework, deploy_target, db_provider):
    """Build the flag dict handed to render(). Every concern is a boolean; the
    enumerated dimensions (framework, target, provider) are passed as their own
    keys so templates can branch on the chosen value."""
    flags = {}
    for c in sorted(app["concerns"].keys()):
        flags[c] = c in concerns
    flags[language] = True
    flags["http_framework"] = http_framework
    flags["deploy_target"] = deploy_target
    flags["db_provider"] = db_provider
    return flags
```

Add to `dev.axl` — extend the existing `app.axl` load line and append the task:

```python
load("./app.axl", "app_config", "app_flags", "resolve_concerns", "validate_app_config")
```

```python
def _render_app_impl(ctx):
    repo_dir = ctx.std.env.current_dir()
    config = load_config(ctx, repo_dir)

    problems = validate_app_config(config)
    if problems:
        for p in problems:
            ctx.std.io.stdout.write("  - {}\n".format(p))
        fail("application metadata contract is invalid; run `aspect check-metadata`")
    app = app_config(config)

    language = ctx.args.language
    requested = [c for c in ctx.args.concerns.split(",") if c]
    concerns = resolve_concerns(app, language, requested)

    target_name = ctx.args.deploy_target
    if target_name not in app["deploy_targets"]:
        fail("unknown deploy target {!r}; known: {}".format(target_name, ", ".join(sorted(app["deploy_targets"].keys()))))
    target = app["deploy_targets"][target_name]

    db_provider = ctx.args.db_provider
    if db_provider == "":
        db_provider = target["default_db_provider"]
    if db_provider not in target["db_providers"]:
        fail("db provider {!r} is not available on deploy target {!r}; available: {}".format(
            db_provider, target_name, ", ".join(target["db_providers"])))

    framework = ctx.args.http_framework
    fw = app.get("http_frameworks", {}).get(language)
    if fw:
        if framework == "":
            framework = fw["default"]
        if framework not in fw["options"]:
            fail("http framework {!r} is not available for {!r}; available: {}".format(
                framework, language, ", ".join(fw["options"])))

    flags = app_flags(app, language, concerns, framework, target_name, db_provider)

    # The app section carries its own rules/no_render/executable because globs are
    # matched relative to the template_dir passed below, not to template/.
    app_render_config = {
        "rules": app["rules"],
        "no_render": app["no_render"],
        "executable": app["executable"],
    }
    template_dir = repo_dir + "/template/" + app["languages"][language]["template_dir"]

    out = ctx.args.out
    if ctx.std.fs.exists(out):
        ctx.std.fs.remove_dir_all(out)
    ctx.std.fs.create_dir_all(out)

    written = render(ctx, app_render_config, template_dir, out, ctx.args.name, flags)
    ctx.std.io.stdout.write("rendered {} app {!r} [{}] -> {} ({} files)\n".format(
        language, ctx.args.name, ", ".join(concerns) if concerns else "no concerns", out, len(written)))
    return 0

render_app = task(
    kind = "render-app",
    summary = "Render one application into an output directory",
    implementation = _render_app_impl,
    args = {
        "language": args.string(required = True, description = "Language (see template-config.json app.languages)"),
        "name": args.string(required = True, description = "Application name (snake_case)"),
        "out": args.string(required = True, description = "Output directory (cleared if it exists)"),
        "concerns": args.string(default = "", description = "Comma-separated concerns; requires are added automatically"),
        "deploy_target": args.string(default = "homelab", description = "Deploy target (see app.deploy_targets)"),
        "db_provider": args.string(default = "", description = "Database provider; defaults to the target's default"),
        "http_framework": args.string(default = "", description = "HTTP framework; defaults to the language's default"),
    },
)
```

Register in `MODULE.aspect`:

```python
use_task("dev.axl", "render_app")
```

- [ ] **Step 2: Run it to verify the happy path renders**

Run:
```bash
aspect render-app --language=go --name=payments --out=/tmp/app-out
```
Expected: `rendered go app 'payments' [no concerns] -> /tmp/app-out (5 files)` and
`/tmp/app-out` containing `main.go`, `main_test.go`, `BUILD.bazel`, `catalog-info.yaml`,
`README.md` with `payments` substituted — not `{{ project_name }}`.

Verify substitution actually happened rather than assuming it:
```bash
grep -r "{{" /tmp/app-out && echo "FAIL: unrendered Jinja remains" || echo "OK: fully rendered"
grep -q "payments" /tmp/app-out/BUILD.bazel && echo "OK: name substituted"
```

- [ ] **Step 3: Verify every rejection path**

Each must fail with the named message. A validator that has only ever seen valid input
has not been tested:

```bash
aspect render-app --language=rust --name=x --out=/tmp/x          # unknown language 'rust'
aspect render-app --language=go --name=x --out=/tmp/x --concerns=svc_bogus   # unknown concern
aspect render-app --language=go --name=x --out=/tmp/x --deploy-target=fly    # unknown deploy target
aspect render-app --language=go --name=x --out=/tmp/x --deploy-target=homelab --db-provider=neon
                                                                 # neon is not available on homelab
aspect render-app --language=go --name=x --out=/tmp/x --http-framework=echo  # not an option for go
```

- [ ] **Step 4: Verify the requires closure adds what was not asked for**

```bash
aspect render-app --language=go --name=x --out=/tmp/x --concerns=svc_otel
```
Expected: the summary line lists `svc_config, svc_logging, svc_otel` — `svc_otel` requires
`svc_logging`, which requires `svc_config`. Asking for one concern and receiving three is
the closure working; if the line shows only `svc_otel`, `resolve_concerns` is broken.

- [ ] **Step 5: Commit**

```bash
git add app.axl dev.axl MODULE.aspect
git commit -m "feat(app): add render-app, the engine entry point every frontend calls

render-preset resolves a NAME to a fixed flag dict; render-app resolves a
SELECTION -- language, concerns, deploy target, database provider, HTTP
framework -- and is the first thing in this repo that refuses invalid input
rather than rendering it silently. That matters because three transports
(Backstage form, HTTP service, CLI) will all reach this code, and a form can
never be trusted to have enforced the rules.

Concerns are closed under requires before rendering, so asking for svc_otel
yields svc_config + svc_logging + svc_otel. Users select intent; the contract
supplies the dependencies.

The enumerated dimensions are passed to templates as their chosen VALUE
(http_framework, deploy_target, db_provider) rather than as booleans, because
providers are keyed by target and more will be added (ADR-023).

render-preset, template/ and the 28 presets are untouched: repo stamping keeps
its own path."
```

---

### Task 4: `check-renders` — tier 2 render smoke

Renders a sampled set of valid selections and asserts each output is clean. Cheap: pure
templating, no bazel, no network.

**Files:**
- Modify: `app.axl` (add `sample_selections`)
- Modify: `dev.axl` (add the `check_renders` task)
- Modify: `MODULE.aspect` (register it)

**Interfaces:**
- Consumes: `app_config`, `resolve_concerns`, `app_flags` (Tasks 1 and 3); `render` from
  `render.axl`.
- Produces: `aspect check-renders [--out-dir <dir>]`, exit non-zero on any problem.

- [ ] **Step 1: Write the failing check**

Add to `app.axl`:

```python
def sample_selections(app):
    """Return the selections tier 2 renders: every declared preset, plus every
    single concern and every concern PAIR for each language.

    Pairs, not the full power set: template conditionals couple pairwise
    ({% if oci and go %} and friends), so pairwise coverage hits the
    interactions that exist while staying linear enough to run on every push.
    """
    out = []
    for name in sorted(app["presets"].keys()):
        p = app["presets"][name]
        out.append((p["language"], p["concerns"], "preset:" + name))
    for lang in sorted(app["languages"].keys()):
        applicable = [c for c in sorted(app["concerns"].keys())
                      if not app["concerns"][c].get("appliesTo") or lang in app["concerns"][c]["appliesTo"]]
        for i in range(len(applicable)):
            out.append((lang, [applicable[i]], "single:" + applicable[i]))
            for j in range(i + 1, len(applicable)):
                out.append((lang, [applicable[i], applicable[j]], "pair:" + applicable[i] + "+" + applicable[j]))
    return out
```

Add to `dev.axl`:

```python
def _check_renders_impl(ctx):
    repo_dir = ctx.std.env.current_dir()
    config = load_config(ctx, repo_dir)
    problems = validate_app_config(config)
    if problems:
        for p in problems:
            ctx.std.io.stdout.write("  - {}\n".format(p))
        fail("application metadata contract is invalid; run `aspect check-metadata`")
    app = app_config(config)

    app_render_config = {"rules": app["rules"], "no_render": app["no_render"], "executable": app["executable"]}
    base_out = ctx.args.out_dir
    if ctx.std.fs.exists(base_out):
        ctx.std.fs.remove_dir_all(base_out)

    failures = []
    checked = 0
    for sel in sample_selections(app):
        language = sel[0]
        concerns = resolve_concerns(app, language, sel[1])
        label = sel[2]
        target = app["deploy_targets"]["homelab"]
        fw = app.get("http_frameworks", {}).get(language)
        flags = app_flags(app, language, concerns,
                          fw["default"] if fw else "",
                          "homelab", target["default_db_provider"])
        out = base_out + "/" + language + "-" + str(checked)
        ctx.std.fs.create_dir_all(out)
        template_dir = repo_dir + "/template/" + app["languages"][language]["template_dir"]
        written = render(ctx, app_render_config, template_dir, out, "smoke_app", flags)

        if not written:
            failures.append("{} [{}]: rendered zero files".format(label, language))
        for rel in written:
            content = ctx.std.fs.read_to_string(out + "/" + rel)
            if "{{" in content or "{%" in content:
                failures.append("{} [{}]: {} still contains unrendered Jinja".format(label, language, rel))
            if "smoke_app" not in content and rel == "BUILD.bazel":
                failures.append("{} [{}]: BUILD.bazel never substituted the project name".format(label, language))
        checked += 1

    ctx.std.io.stdout.write("check-renders: {} selection(s) rendered\n".format(checked))
    if failures:
        for f in failures:
            ctx.std.io.stdout.write("  - {}\n".format(f))
        fail("{} render problem(s)".format(len(failures)))
    ctx.std.io.stdout.write("check-renders: OK\n")
    return 0

check_renders = task(
    kind = "check-renders",
    summary = "Render sampled valid selections and assert each output is clean",
    implementation = _check_renders_impl,
    args = {
        "out_dir": args.string(default = "/tmp/aspect-check-renders", description = "Scratch directory for rendered output"),
    },
)
```

Register in `MODULE.aspect`:

```python
use_task("dev.axl", "check_renders")
```

- [ ] **Step 2: Run it to verify it passes**

Run: `aspect check-renders`
Expected: `check-renders: 22 selection(s) rendered` then `check-renders: OK`
(1 preset + 6 singles + 15 pairs for Go's six concerns).

- [ ] **Step 3: Falsify — prove the check catches a real defect**

Introduce an unrendered-Jinja bug and confirm the check fails, then revert:

```bash
printf '\n// {%% if svc_http %%}\n' >> template/app/go/main.go
aspect check-renders          # expect: "still contains unrendered Jinja"? -> NO, see below
```

`{% if %}` **is** valid Jinja and will be consumed, so this must instead be a malformed
tag, which is what actually escapes into output:

```bash
git checkout template/app/go/main.go
printf '\n// {{ project_nonexistent_variable }}\n' >> template/app/go/main.go
aspect check-renders
```

Expected: minijinja renders an undefined variable as empty, so the file is clean — which
tells you the guard's real value is catching **malformed** tags, not typos. Use one:

```bash
git checkout template/app/go/main.go
printf '\n// {{ broken\n' >> template/app/go/main.go
aspect check-renders
```
Expected: FAIL with `still contains unrendered Jinja` naming `main.go`.
Then: `git checkout template/app/go/main.go` and re-run to confirm OK.

- [ ] **Step 4: Commit**

```bash
git add app.axl dev.axl MODULE.aspect
git commit -m "feat(app): add check-renders, tier 2 of the testing model

The valid selection space is exponential and CI cannot build it, so the
warranty is tiered: presets get full builds, everything else gets a cheap
render smoke. This is that smoke -- every preset, every single concern, and
every concern PAIR, rendered and inspected. Pairs rather than the full power
set because template conditionals couple pairwise, so pairwise hits the
interactions that actually exist while staying linear.

It needs no bazel and no network, which is what lets it run on every push
rather than nightly. Today it covers 22 selections for one language; it scales
with the contract rather than needing new cases written per concern.

Falsified rather than assumed: an unrendered Jinja tag was introduced and the
check caught it by filename. Worth recording what that exercise showed --
minijinja renders an UNDEFINED variable as empty, so this guard catches
malformed tags, not typo'd names. Catching those needs a different check."
```

---

### Task 5: CI wiring + gazelle fixed-point proof

Runs both checks on every push, and proves the highest-value property in the program: a
stamped application's BUILD file is exactly what gazelle would generate, so the first PR
into a real monorepo does not fail the stale-BUILD gate.

**Files:**
- Modify: `.github/workflows/ci.yaml`
- Create: `docs/application-initializer.md`

**Interfaces:**
- Consumes: `aspect check-metadata`, `aspect check-renders`, `aspect render-app` (Tasks
  1, 3, 4).
- Produces: a CI job named `app-contract` that gates the branch.

- [ ] **Step 1: Verify the fixed point by hand first**

Before automating it, prove the property holds. Render a monorepo, stamp an app into it,
run gazelle, and check nothing changes:

```bash
aspect render-preset --preset=go --out=/tmp/mono --name=my_project
aspect render-app --language=go --name=payments --out=/tmp/mono/app/payments
cd /tmp/mono && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm base
aspect gazelle
git diff --exit-code && echo "OK: gazelle fixed point" || echo "FAIL: gazelle rewrote the BUILD file"
```

If it fails, the diff is the answer: update `template/app/go/BUILD.bazel` to match what
gazelle produced, then re-run until clean. **Do not add `# gazelle:ignore` to make this
pass** — that would hide exactly the breakage this check exists to catch.

- [ ] **Step 2: Add the CI job**

Append to `.github/workflows/ci.yaml` a job that runs independently of the preset matrix
(it needs no bazel, so it finishes in seconds rather than waiting on a build):

```yaml
  # The application-composition contract and its render smoke. Deliberately
  # separate from the preset matrix: these need no bazel toolchain, so they
  # return a verdict in seconds and fail fast on a bad contract before the
  # expensive per-preset builds start.
  app-contract:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Aspect CLI
        uses: aspect-build/setup-aspect@v1
      - name: Validate the application metadata contract
        run: aspect check-metadata
      - name: Render sampled selections and inspect the output
        run: aspect check-renders
      - name: Prove a stamped application is a gazelle fixed point
        run: |
          set -euo pipefail
          aspect render-preset --preset=go --out="$RUNNER_TEMP/mono" --name=my_project
          aspect render-app --language=go --name=payments --out="$RUNNER_TEMP/mono/app/payments"
          cd "$RUNNER_TEMP/mono"
          git init -q
          git add -A
          git -c user.email=ci@aspect.build -c user.name=CI commit -qm "rendered"
          aspect gazelle
          git diff --exit-code
```

- [ ] **Step 3: Verify the job fails when the property breaks**

Deliberately break the BUILD file's target name so gazelle rewrites it, push, and confirm
the job goes red — a green-only check proves nothing:

```bash
sed -i '' 's/{{ project_kebab }}_lib/wrong_name_lib/' template/app/go/BUILD.bazel
git add -A && git commit -m "temp: break the fixed point" && git push
# confirm the app-contract job fails on `git diff --exit-code`
git revert --no-edit HEAD && git push
```

- [ ] **Step 4: Write the operator documentation**

Create `docs/application-initializer.md`:

```markdown
# Application initializer

Repo stamping (`aspect render-preset`) creates a new Bazel monorepo. Application
stamping (`aspect render-app`) creates one application **inside** an existing
monorepo. They are different products; see the design spec in `vitruvian-core`
at `docs/superpowers/specs/2026-08-18-universal-initializer-design.md`.

## Stamping an application

    aspect render-app --language=go --name=payments --out=./app/payments

Optional: `--concerns` (comma-separated; dependencies are added automatically),
`--deploy-target` (`homelab` or `cloudrun`), `--db-provider`, `--http-framework`.

## The contract

`template-config.json`'s `app` section declares the languages, concerns and
their `requires` chains, deploy targets and their database providers, and the
presets. Every frontend reads it. Change it and run:

    aspect check-metadata     # the contract is internally consistent
    aspect check-renders      # sampled selections render cleanly

## Adding a language

1. Create `template/app/<language>/`.
2. Add it to `app.languages` with `template_dir` set to `app/<language>`.
3. Add the language to `appliesTo` on each concern it supports.
4. Run both checks; add a preset so the language gets a full build in CI.

Application templates are excluded from repo stamping by the
`{"flag": "app_template", "globs": ["app/**"]}` rule. That rule is
load-bearing: `is_included` includes any path matched by no rule, so removing
it puts `app/` into all 26 published starter repos.
```

- [ ] **Step 5: Commit and open the PR**

```bash
git add .github/workflows/ci.yaml docs/application-initializer.md
git commit -m "ci(app): gate on the contract, the render smoke, and the gazelle fixed point

Three checks, cheapest first. check-metadata and check-renders need no bazel,
so they return a verdict in seconds and fail fast on a bad contract before the
expensive per-preset builds start.

The third is the one that matters most. A stamped application's BUILD file must
be exactly what gazelle generates, because the target monorepo already gates on
stale BUILD files -- if it is not a fixed point, every stamping PR arrives red
and the initializer is unusable no matter how good the rendering is. The job
renders a monorepo, stamps an app into it, runs gazelle, and fails on any diff.

Verified by breaking it: renaming a target made gazelle rewrite the file and
the job went red, which is the only way to know the check is wired to anything.
Note for future maintainers -- do NOT silence this with gazelle:ignore the way
template/hello/go does. That sample is hand-curated and opts out deliberately;
a stamped application is real code gazelle must manage, and the ignore comment
would hide precisely the breakage this check exists to catch."

git push -u origin feat/app-composition-core
gh pr create --repo VitruvianSoftware/aspect-workflows-template --base platform-v2.0 \
  --title "feat(app): application composition core (initializer P0)" \
  --body "Implements P0 of the application initializer design spec: metadata contract, render-app, the base Go application template, and tiers 1-2 of the testing model. Repo stamping is untouched and proven so by diffing a rendered preset before and after."
```

---

## Self-Review

**Spec coverage (P0 scope):**

| Spec requirement | Task |
|---|---|
| App metadata contract (§5.1), provider dimension keyed by target (ADR-023) | Task 1 |
| Validation as the shared enforcement point (§5.2) | Tasks 1, 3 |
| `render-app` with an arbitrary selection (§5.2) | Task 3 |
| App templates at `template/app/<language>/` (§6.1, ADR-024) | Task 2 |
| Exclusion rule so repo stamping is unaffected (§6.1) | Task 2 |
| App-side `rules`/`no_render`/`executable` (§6.1) | Tasks 1, 2 |
| Base Go application template (§13 P0) | Task 2 |
| Tier 1 — metadata self-consistency (§10) | Task 1 |
| Tier 2 — pairwise render smoke (§10) | Task 4 |
| Gazelle fixed point (§6.3) | Task 5 |
| AXL check-tasks as the harness (ADR-025) | Tasks 1, 4, 5 |

Out of P0 by design: concern templates (P2), Backstage frontend (P1), deploy bundles (P3),
HTTP service (P4), CLI (P5).

**Type consistency:** `validate_app_config(config) -> list[str]`, `app_config(config) ->
dict`, `resolve_concerns(app, language, concerns) -> list[str]`, `app_flags(app, language,
concerns, http_framework, deploy_target, db_provider) -> dict`, `sample_selections(app) ->
list[tuple]` — each defined once and called with matching arity in every later task.
`render()` is called with the existing signature
`(ctx, config, template_dir, out_dir, project_snake, flags)` in Tasks 3 and 4.

**Known risk, stated rather than hidden:** the exact `template/app/go/BUILD.bazel` target
shape is a prediction of gazelle's output, not a verified fact — it cannot be verified
without running gazelle in a rendered monorepo. Task 5 Step 1 is where that prediction is
tested, and the instruction there is to take gazelle's output as truth and update the
template, never to silence the check.
