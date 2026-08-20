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

// orchestrate — the delivery orchestrator's DECIDE stage (spec
// docs/superpowers/specs/2026-08-19-delivery-orchestrator-design.md §4.2).
//
// It answers exactly one question, once per push, for every delivery unit in
// the repo: "does this diff affect you?" — and writes the answer to
// delivery-manifest.json plus $GITHUB_OUTPUT. It does not deploy anything, and
// in Phase 0 nothing consumes its verdicts (shadow mode): the legacy per-app
// workflows keep delivering while this binary accumulates the real-world
// detection data Phase 1 will be validated against.
//
// Three stages, in order:
//
//  1. DISCOVER — `bazel query` the "delivery" tag, `bazel build` the matched
//     units, read their metadata JSON out of bazel-bin. The graph IS the
//     registry (§4.1): there is no list of apps to forget to update.
//  2. DECIDE — shell out to tools/ci/deploy-affected.sh, once per unit. That
//     script is the repo's proven decision engine (#498, #503, #1351) and this
//     binary deliberately does NOT reimplement any of it: the orchestrator's
//     whole job is to fan the existing engine out over the declared units and
//     collect the answers. Graph mode vs PATH-ONLY mode is selected exactly as
//     the script documents (DEPLOY_TARGETS set vs unset).
//  3. EMIT — the manifest, the GITHUB_OUTPUTs, and a human summary table.
//
// FAIL-OPEN INVARIANT, inherited verbatim from deploy-affected.sh:33-35 and
// restated by the spec (§4.2, §5): every uncertainty — unresolvable base,
// forced push, query failure, build failure, unparsable metadata, engine
// non-zero — marks EVERY unit affected and stamps computed_by="fail-open" with
// a reason. The orchestrator can only ever over-deliver, never silently
// under-deliver.
//
// AND IT EXITS 0 ANYWAY. A detection problem must never redden CI: a red
// orchestrate job in shadow mode teaches the team to ignore it, and in Phase 1
// it would block the delivery it is supposed to fan out. The loudness lives
// where it can be acted on instead — computed_by/reason in the manifest, a
// ::warning:: annotation in the run UI, and the summary table. This mirrors
// deploy-affected.sh's own `emit ... degraded` treatment of a broken fast path
// (#503). The single exception is an unwritable --out: then there is no
// manifest to be loud in, so that is a genuine exit 1.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"strings"
	"text/tabwriter"
)

const (
	// schemaVersion is the manifest's "schema" field (spec §4.2). Bump only
	// with a consumer migration; delivery() writes its own independent
	// "schema" for the unit metadata (tools/delivery/defs.bzl).
	schemaVersion = 1

	// computed_by values. "graph"/"paths" are per-unit engine verdicts;
	// "fail-open" is the spec's loud uncertainty marker and, at the top
	// level, overrides everything below it.
	computedByGraph    = "graph"
	computedByPaths    = "paths"
	computedByFailOpen = "fail-open"

	defaultManifestName = "delivery-manifest.json"

	// deployAffectedRel is THE decision engine. Never reimplement it here —
	// its fail-open reasoning, release-please guard, global-impact allowlist
	// and TD plumbing are load-bearing and separately tested by
	// tools/ci/deploy-affected_test.sh.
	deployAffectedRel = "tools/ci/deploy-affected.sh"

	// deliveryQuery discovers the universe.
	//
	// WHY plain `query` and not `cquery`, even though the spec's prose says
	// cquery: query does not configure anything, so it cannot trip the
	// macOS-toolchain analysis landmine that forces every //... sweep in this
	// repo to carve out //nexus-agent/macos/... . The metadata is a
	// write_file output with no configuration-dependent content, so there is
	// nothing cquery would tell us that query does not.
	//
	// WHY the //nexus-agent/macos/... exclusion survives anyway: loading that
	// subtree costs real time on every orchestrate run for zero possible
	// hits (it declares no delivery units and, being an Apple-toolchain
	// subtree, is the one package set this repo's sweeps always exclude).
	// Keeping the carve-out keeps orchestrate's cost proportional to what it
	// can actually find.
	deliveryQuery = `attr(tags, "\bdelivery\b", (//... except //nexus-agent/macos/...))`

	// unitTargetSuffix / metaTargetSuffix encode the delivery() macro's
	// naming contract (tools/delivery/defs.bzl): the tagged filegroup is
	// "<name>.delivery_unit" and it wraps the generated "<name>.delivery.json".
	// Deriving the metadata path from the label keeps discovery to a single
	// bazel query; a target that is tagged "delivery" but does not follow the
	// convention simply yields a missing file, which is a fail-open — the
	// safe direction.
	unitTargetSuffix = ".delivery_unit"
	metaFileSuffix   = ".delivery.json"
)

// unitMeta mirrors the JSON emitted by delivery() in tools/delivery/defs.bzl.
// Field names are that macro's, not ours — it is the schema owner.
type unitMeta struct {
	Schema            int      `json:"schema"`
	Name              string   `json:"name"`
	Kind              string   `json:"kind"`
	Run               string   `json:"run"`
	Build             string   `json:"build"`
	Environments      []string `json:"environments"`
	GithubEnvironment string   `json:"github_environment"`
	Promotion         string   `json:"promotion"`
	Companions        []string `json:"companions"`
	ExtraPaths        []string `json:"extra_paths"`
	ExcludePaths      []string `json:"exclude_paths"`
	Preflight         string   `json:"preflight"`
	Package           string   `json:"package"`
}

// manifestUnit is one row of the manifest (spec §4.2).
//
// "computed_by" is an addition to the spec's per-unit shape: the spec puts
// computed_by only at the top level, but a mixed manifest (one graph-mode unit,
// one path-only unit) cannot be described by a single top-level value, and the
// per-unit provenance is exactly what Phase 0's shadow A/B needs to compare
// against today's per-workflow gates.
type manifestUnit struct {
	Name              string   `json:"name"`
	Affected          bool     `json:"affected"`
	ComputedBy        string   `json:"computed_by"`
	Reason            string   `json:"reason"`
	Environments      []string `json:"environments"`
	Kind              string   `json:"kind"`
	GithubEnvironment string   `json:"github_environment"`
	Run               string   `json:"run"`
}

// manifest is delivery-manifest.json (spec §4.2).
//
// "reason" is an addition to the spec's top-level shape, carrying the
// fail-open cause. Without it, computed_by:"fail-open" tells a reader THAT
// detection failed but not why — and "why" is the entire point of failing
// loudly rather than silently over-delivering.
type manifest struct {
	Schema     int            `json:"schema"`
	Commit     string         `json:"commit"`
	Before     string         `json:"before"`
	ComputedBy string         `json:"computed_by"`
	Reason     string         `json:"reason,omitempty"`
	Units      []manifestUnit `json:"units"`
}

// config is everything orchestrate() reads from the outside world. Keeping it
// a struct (rather than reaching for os.Getenv/os.Getwd inline) is what makes
// the hermetic tests possible: they point repoRoot at a scratch git repo and
// bazel at a fake, while still driving the REAL deploy-affected.sh.
type config struct {
	repoRoot string            // cwd for git and for the engine
	script   string            // absolute path to deploy-affected.sh
	bazel    string            // bazel binary (or a stub, in tests)
	out      string            // manifest destination
	env      map[string]string // the orchestrator's own environment
	stdout   io.Writer
}

// ---------------------------------------------------------------------------
// discovery
// ---------------------------------------------------------------------------

// discover returns the declared delivery units.
//
// A non-nil error means "go fail-open"; the returned units are still the best
// list we have, so callers can mark them all affected. When a unit's metadata
// cannot be read or parsed we substitute a placeholder derived from its label
// rather than dropping it — dropping a unit is the one outcome the fail-open
// invariant forbids, because a unit absent from the manifest reads as "not
// affected" to every downstream consumer.
func discover(cfg config) ([]unitMeta, error) {
	out, err := bazelRun(cfg, "query", deliveryQuery, "--output=label")
	if err != nil {
		return nil, fmt.Errorf("bazel query for delivery units failed: %w", err)
	}
	labels := nonEmptyLines(out)
	if len(labels) == 0 {
		// An empty universe is a legitimate state (nothing declared yet), not
		// an uncertainty: there is no unit we could be wrong about.
		return nil, nil
	}

	// A placeholder carries the unit's NAME and nothing else. Its "run" stays
	// empty on purpose: the only label we have here is the tagged filegroup's,
	// and putting that in the manifest's "run" field would hand a consumer a
	// plausible-looking target that delivers nothing. The label is not lost —
	// it is named in the fail-open reason attached to the row.
	placeholders := make([]unitMeta, 0, len(labels))
	for _, l := range labels {
		placeholders = append(placeholders, unitMeta{Name: unitNameFromLabel(l)})
	}

	if _, err := bazelRun(cfg, append([]string{"build"}, labels...)...); err != nil {
		return placeholders, fmt.Errorf("bazel build of delivery metadata failed: %w", err)
	}
	binOut, err := bazelRun(cfg, "info", "bazel-bin")
	if err != nil {
		return placeholders, fmt.Errorf("bazel info bazel-bin failed: %w", err)
	}
	binDir := strings.TrimSpace(binOut)

	units := make([]unitMeta, 0, len(labels))
	var firstErr error
	for i, l := range labels {
		rel, err := metadataRelPath(l)
		if err == nil {
			var raw []byte
			raw, err = os.ReadFile(filepath.Join(binDir, rel))
			if err == nil {
				var m unitMeta
				if err = json.Unmarshal(raw, &m); err == nil && m.Name != "" {
					units = append(units, m)
					continue
				}
				if err == nil {
					err = fmt.Errorf("metadata has no \"name\"")
				}
			}
		}
		if firstErr == nil {
			firstErr = fmt.Errorf("delivery metadata for %s unreadable: %w", l, err)
		}
		units = append(units, placeholders[i])
	}
	return units, firstErr
}

// metadataRelPath maps a delivery-unit label to its metadata file's path
// relative to bazel-bin: //pkg/sub:x.delivery_unit -> pkg/sub/x.delivery.json.
func metadataRelPath(label string) (string, error) {
	l := strings.TrimPrefix(strings.TrimPrefix(strings.TrimPrefix(label, "@@"), "@"), "//")
	if l == "" {
		return "", fmt.Errorf("label %q is not a main-repo label", label)
	}
	pkg, target, ok := strings.Cut(l, ":")
	if !ok {
		// //foo/bar is shorthand for //foo/bar:bar.
		pkg, target = l, path.Base(l)
	}
	if target == "" {
		return "", fmt.Errorf("label %q has an empty target name", label)
	}
	file := strings.TrimSuffix(target, unitTargetSuffix) + metaFileSuffix
	return path.Join(pkg, file), nil
}

// unitNameFromLabel recovers the delivery() name from its filegroup label, for
// the placeholder used when the metadata itself cannot be read.
func unitNameFromLabel(label string) string {
	_, target, ok := strings.Cut(label, ":")
	if !ok {
		target = path.Base(label)
	}
	return strings.TrimSuffix(target, unitTargetSuffix)
}

// ---------------------------------------------------------------------------
// decision
// ---------------------------------------------------------------------------

// engineVerdict is the line deploy-affected.sh prints for every outcome
// (deploy-affected.sh:76). We take the boolean from $GITHUB_OUTPUT — that is
// the script's contractual output — and only the human reason from this line.
var engineVerdict = regexp.MustCompile(`(?m)^deploy-affected: affected=(true|false) \((.*)\)$`)

// decide runs the engine once for one unit and returns its verdict.
//
// Mode selection follows deploy-affected.sh's own documented contract: a unit
// with no Bazel-graph-tracked build artifact (build == "") runs in PATH-ONLY
// MODE with DEPLOY_TARGETS UNSET — not empty-but-set, because the script tests
// `[ -z "${DEPLOY_TARGETS}" ]` and an inherited stray value would silently
// switch the unit into graph mode.
func decide(cfg config, base string, u unitMeta) (affected bool, mode, reason string, err error) {
	extra := map[string]string{
		"BEFORE_REV":  base,
		"FORCED_PUSH": cfg.env["FORCED_PUSH"],
		// The declaration owns the path regexes now (spec §4.2 step 2): they
		// moved out of workflow YAML into delivery(extra_paths/exclude_paths)
		// so they live next to the code they describe. The script anchors and
		// wraps them itself ("^(<regex>)"), so a plain "|" join is the whole
		// translation.
		"EXTRA_PATH_REGEX":   strings.Join(u.ExtraPaths, "|"),
		"EXCLUDE_PATH_REGEX": strings.Join(u.ExcludePaths, "|"),
	}
	mode = computedByPaths
	if u.Build != "" {
		mode = computedByGraph
		// The graph universe is the union of what must be built and what
		// performs the delivery; TD attributes the diff against exactly these
		// (deploy-affected.sh:178-185).
		extra["DEPLOY_TARGETS"] = strings.TrimSpace(u.Build + " " + u.Run)
	}

	// A private $GITHUB_OUTPUT per unit: the script appends "affected=..." to
	// it, and we must not let unit N's line be read as unit N+1's, nor leak
	// these into the orchestrator's own real $GITHUB_OUTPUT.
	tmp, err := os.MkdirTemp("", "delivery-orchestrate-")
	if err != nil {
		return true, mode, "", fmt.Errorf("cannot create a temp dir for the engine's GITHUB_OUTPUT: %w", err)
	}
	defer os.RemoveAll(tmp)
	outPath := filepath.Join(tmp, "github_output")
	if err := os.WriteFile(outPath, nil, 0o644); err != nil {
		return true, mode, "", fmt.Errorf("cannot seed the engine's GITHUB_OUTPUT: %w", err)
	}
	extra["GITHUB_OUTPUT"] = outPath

	cmd := exec.Command("bash", cfg.script)
	cmd.Dir = cfg.repoRoot
	cmd.Env = engineEnv(cfg, extra)
	var combined bytes.Buffer
	cmd.Stdout = &combined
	cmd.Stderr = &combined
	runErr := cmd.Run()

	// The engine's own log is the artifact Phase 0 exists to collect: it is
	// what today's per-app gates print, so a shadow run is directly
	// A/B-comparable against the live workflow's log for the same commit.
	fmt.Fprintf(cfg.stdout, "---- deploy-affected.sh: %s (%s mode) ----\n", u.Name, mode)
	for _, line := range strings.Split(strings.TrimRight(combined.String(), "\n"), "\n") {
		fmt.Fprintf(cfg.stdout, "  %s\n", line)
	}

	if m := engineVerdict.FindStringSubmatch(combined.String()); m != nil {
		reason = m[2]
	}
	if runErr != nil {
		return true, mode, reason, fmt.Errorf("deploy-affected.sh for unit %q exited non-zero: %w", u.Name, runErr)
	}

	raw, err := os.ReadFile(outPath)
	if err != nil {
		return true, mode, reason, fmt.Errorf("cannot read the engine's GITHUB_OUTPUT for unit %q: %w", u.Name, err)
	}
	verdict := ""
	for _, line := range nonEmptyLines(string(raw)) {
		if v, ok := strings.CutPrefix(line, "affected="); ok {
			verdict = strings.TrimSpace(v)
		}
	}
	switch verdict {
	case "true":
		return true, mode, reason, nil
	case "false":
		return false, mode, reason, nil
	default:
		return true, mode, reason, fmt.Errorf("deploy-affected.sh for unit %q emitted no affected= line", u.Name)
	}
}

// ---------------------------------------------------------------------------
// orchestration
// ---------------------------------------------------------------------------

func orchestrate(cfg config) int {
	m := manifest{Schema: schemaVersion, Units: []manifestUnit{}}
	m.Commit = gitOutput(cfg, "rev-parse", "HEAD")

	// --- 1. the diff base. Anything untrustworthy is a whole-manifest
	//        fail-open, decided BEFORE the engine runs.
	//
	// deploy-affected.sh would fail open on these by itself, but only per
	// unit and only as an "affected=true" we could not distinguish from a
	// genuine hit. Resolving the base here is what lets the manifest say
	// computed_by:"fail-open" instead of silently claiming a real verdict.
	//
	// BASE_REF is a fallback, not a peer: the durable base is BEFORE_REV
	// (tools/ci/resolve-deploy-base.sh, #1351), and deploy-affected.sh knows
	// only that name — so whichever we pick is handed to it as BEFORE_REV.
	base := firstNonEmpty(cfg.env["BEFORE_REV"], cfg.env["BASE_REF"])
	m.Before = base

	failOpen := ""
	switch {
	case cfg.env["FORCED_PUSH"] == "true":
		failOpen = "forced push -- no trustworthy diff base"
	case base == "":
		failOpen = "neither BEFORE_REV nor BASE_REF is set -- no diff base to compute against"
	case gitOutput(cfg, "rev-parse", "--verify", "--quiet", base+"^{commit}") == "":
		failOpen = fmt.Sprintf("base %q does not resolve to a commit", base)
	}

	// --- 2. the universe.
	units, err := discover(cfg)
	if err != nil && failOpen == "" {
		failOpen = err.Error()
	}

	// --- 3. the verdicts.
	if failOpen == "" {
		graphSeen := false
		for _, u := range units {
			affected, mode, reason, derr := decide(cfg, base, u)
			if derr != nil {
				// One unit's engine failure invalidates the whole manifest:
				// we cannot tell a broken engine from a correct "false", and
				// a wrong "false" is the #498 bug this machinery exists to
				// prevent. Fail the manifest open, not just this row.
				failOpen = derr.Error()
				break
			}
			if mode == computedByGraph {
				graphSeen = true
			}
			m.Units = append(m.Units, newManifestUnit(u, affected, mode, reason))
		}
		if failOpen == "" {
			m.ComputedBy = computedByPaths
			if graphSeen {
				m.ComputedBy = computedByGraph
			}
		}
	}

	if failOpen != "" {
		// Rebuild every row from scratch: rows decided before the failure are
		// no longer trustworthy either (the failure may have been the reason
		// their diff looked empty).
		m.ComputedBy = computedByFailOpen
		m.Reason = failOpen
		m.Units = m.Units[:0]
		for _, u := range units {
			m.Units = append(m.Units, newManifestUnit(u, true, computedByFailOpen, failOpen))
		}
		// The run UI's copy of the reason. Phase 0 is shadow, so this warning
		// is the ONLY thing a human will notice — it has to carry the cause.
		fmt.Fprintf(cfg.stdout,
			"::warning title=delivery-orchestrator-fail-open::delivery detection failed OPEN -- every unit marked affected (%s)\n",
			failOpen)
		// A fail-open manifest may also be SHORT: if discovery itself failed
		// there are no units to list. Consumers must therefore treat
		// computed_by=="fail-open" as authoritative over the units array and
		// read a missing unit as affected.
	}

	if err := writeManifest(cfg, m); err != nil {
		fmt.Fprintf(cfg.stdout, "::error title=delivery-orchestrator::%v\n", err)
		return 1
	}
	if err := writeGitHubOutputs(cfg, m); err != nil {
		// Losing the job outputs degrades Phase 1's fan-out but the manifest
		// artifact still exists, so this stays a warning-and-continue.
		fmt.Fprintf(cfg.stdout, "::warning title=delivery-orchestrator::%v\n", err)
	}
	printSummary(cfg, m)
	return 0
}

func newManifestUnit(u unitMeta, affected bool, mode, reason string) manifestUnit {
	return manifestUnit{
		Name:         u.Name,
		Affected:     affected,
		ComputedBy:   mode,
		Reason:       reason,
		Environments: u.Environments,
		Kind:         u.Kind,
		// The DECLARED pattern, "{env}" intact — not a substituted value.
		// Which rung of the ladder a given event targets is the generator's
		// decision (spec §4.3: push runs the first env, later envs promote on
		// a release event), and the orchestrator has no event input in Phase
		// 0. Emitting the pattern is lossless; substituting environments[0]
		// would discard the other rungs.
		GithubEnvironment: u.GithubEnvironment,
		Run:               u.Run,
	}
}

// ---------------------------------------------------------------------------
// emission
// ---------------------------------------------------------------------------

func writeManifest(cfg config, m manifest) error {
	raw, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return fmt.Errorf("cannot marshal the manifest: %w", err)
	}
	raw = append(raw, '\n')
	if err := os.WriteFile(cfg.out, raw, 0o644); err != nil {
		return fmt.Errorf("cannot write the manifest to %s: %w", cfg.out, err)
	}
	fmt.Fprintf(cfg.stdout, "delivery-orchestrate: wrote %s\n", cfg.out)
	return nil
}

// writeGitHubOutputs appends the job outputs the generated workflow consumes.
//
//	manifest=<compact json>                one line; GHA's key=value form has
//	                                       no multi-line escape, and compact
//	                                       JSON never contains a newline.
//	affected_<unit>=true|false             the convenience form for a job-level
//	                                       `if:` that cannot reach into JSON.
func writeGitHubOutputs(cfg config, m manifest) error {
	p := cfg.env["GITHUB_OUTPUT"]
	if p == "" {
		return nil
	}
	compact, err := json.Marshal(m)
	if err != nil {
		return fmt.Errorf("cannot marshal the compact manifest: %w", err)
	}
	var b strings.Builder
	fmt.Fprintf(&b, "manifest=%s\n", compact)
	for _, u := range m.Units {
		fmt.Fprintf(&b, "affected_%s=%t\n", outputVarName(u.Name), u.Affected)
	}
	f, err := os.OpenFile(p, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return fmt.Errorf("cannot open GITHUB_OUTPUT %s: %w", p, err)
	}
	defer f.Close()
	if _, err := f.WriteString(b.String()); err != nil {
		return fmt.Errorf("cannot append to GITHUB_OUTPUT %s: %w", p, err)
	}
	return nil
}

// outputVarName turns a unit name into a GHA output key. Unit names are
// kebab-case by convention ("oauth-user-inspector"); anything outside
// [A-Za-z0-9_] is folded to "_" as well, because an output key that GHA
// silently rejects would look exactly like "not affected" downstream.
var notOutputSafe = regexp.MustCompile(`[^A-Za-z0-9_]`)

func outputVarName(name string) string {
	return notOutputSafe.ReplaceAllString(name, "_")
}

func printSummary(cfg config, m manifest) {
	fmt.Fprintf(cfg.stdout, "\ndelivery-orchestrate: %d unit(s), computed_by=%s\n", len(m.Units), m.ComputedBy)
	if m.Reason != "" {
		fmt.Fprintf(cfg.stdout, "  reason: %s\n", m.Reason)
	}
	w := tabwriter.NewWriter(cfg.stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "  UNIT\tAFFECTED\tBY\tWHY")
	for _, u := range m.Units {
		fmt.Fprintf(w, "  %s\t%t\t%s\t%s\n", u.Name, u.Affected, u.ComputedBy, u.Reason)
	}
	w.Flush()
}

// ---------------------------------------------------------------------------
// process plumbing
// ---------------------------------------------------------------------------

// engineEnv builds deploy-affected.sh's environment from an explicit
// allowlist plus the per-unit values.
//
// WHY an allowlist rather than os.Environ()+overrides: PATH-ONLY MODE is
// selected by DEPLOY_TARGETS being UNSET, so the orchestrator has to be able
// to guarantee its absence — which it cannot do by inheriting an arbitrary
// environment. Everything the script and its td-lib.sh actually document
// needing is listed here.
var engineEnvAllowlist = []string{
	"PATH", "HOME", "USER", "TMPDIR", "LANG", "LC_ALL",
	"BUILDBUDDY_API_KEY",  // graph mode: TD's remote-cache auth
	"TD_BIN",              // td-lib.sh's documented test hook
	"GITHUB_STEP_SUMMARY", // where the script writes its degraded-gate notice
	// git isolation knobs, so a hermetic caller can keep the user's global
	// git config out of the engine's `git diff`.
	"GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "GIT_CONFIG_NOSYSTEM",
}

func engineEnv(cfg config, extra map[string]string) []string {
	env := make([]string, 0, len(engineEnvAllowlist)+len(extra))
	for _, k := range engineEnvAllowlist {
		if v, ok := cfg.env[k]; ok {
			env = append(env, k+"="+v)
		}
	}
	for k, v := range extra {
		env = append(env, k+"="+v)
	}
	return env
}

// bazelRun invokes bazel in the workspace. Unlike the engine, bazel gets the
// orchestrator's FULL environment: it needs its own ambient configuration
// (cache dirs, toolchain locations, CI credentials) and there is no
// unset-sensitive contract to protect here.
func bazelRun(cfg config, args ...string) (string, error) {
	cmd := exec.Command(cfg.bazel, args...)
	cmd.Dir = cfg.repoRoot
	cmd.Env = flatEnv(cfg.env)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return stdout.String(), fmt.Errorf("%s %s: %v: %s",
			filepath.Base(cfg.bazel), strings.Join(args, " "), err, oneLine(stderr.String()))
	}
	return stdout.String(), nil
}

// gitOutput runs git in the workspace and returns trimmed stdout, or "" on any
// failure. Callers treat "" as "could not determine", which is a fail-open.
func gitOutput(cfg config, args ...string) string {
	cmd := exec.Command("git", args...)
	cmd.Dir = cfg.repoRoot
	cmd.Env = flatEnv(cfg.env)
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func flatEnv(env map[string]string) []string {
	out := make([]string, 0, len(env))
	for k, v := range env {
		out = append(out, k+"="+v)
	}
	return out
}

func nonEmptyLines(s string) []string {
	var out []string
	for _, l := range strings.Split(s, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			out = append(out, l)
		}
	}
	return out
}

func oneLine(s string) string {
	return strings.Join(strings.Fields(strings.TrimSpace(s)), " ")
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v = strings.TrimSpace(v); v != "" {
			return v
		}
	}
	return ""
}

func envMap(environ []string) map[string]string {
	m := make(map[string]string, len(environ))
	for _, kv := range environ {
		if k, v, ok := strings.Cut(kv, "="); ok {
			m[k] = v
		}
	}
	return m
}

func main() {
	env := envMap(os.Environ())

	fs := flag.NewFlagSet("orchestrate", flag.ExitOnError)
	out := fs.String("out", defaultManifestName,
		"where to write the delivery manifest (relative paths resolve against the workspace root)")
	// ORCHESTRATE_BAZEL exists so a caller that already resolved bazelisk (or
	// a test harness) can point this at a specific binary without editing the
	// generated workflow. --bazel wins over it.
	bazelBin := fs.String("bazel", firstNonEmpty(env["ORCHESTRATE_BAZEL"], "bazel"),
		"the bazel binary used for discovery (env ORCHESTRATE_BAZEL)")
	// NOTE: there is deliberately no --dry-run. The only thing this binary
	// writes is its own manifest and the job outputs; nothing it does is
	// side-effecting, so a "skip the side effects" flag would have nothing to
	// skip and would only invite the belief that some invocation of it might
	// deploy something.
	_ = fs.Parse(os.Args[1:])

	// BUILD_WORKSPACE_DIRECTORY is set by `bazel run`, whose cwd is the
	// runfiles tree — without this the engine would `git diff` the wrong
	// directory and the manifest would land somewhere nobody looks.
	root := env["BUILD_WORKSPACE_DIRECTORY"]
	if root == "" {
		wd, err := os.Getwd()
		if err != nil {
			fmt.Fprintf(os.Stderr, "orchestrate: cannot determine the workspace root: %v\n", err)
			os.Exit(1)
		}
		root = wd
	}
	manifestPath := *out
	if !filepath.IsAbs(manifestPath) {
		manifestPath = filepath.Join(root, manifestPath)
	}

	os.Exit(orchestrate(config{
		repoRoot: root,
		script:   filepath.Join(root, deployAffectedRel),
		bazel:    *bazelBin,
		out:      manifestPath,
		env:      env,
		stdout:   os.Stdout,
	}))
}
