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

// gen — render .github/workflows/delivery.yaml from the delivery()
// declarations in the Bazel graph (spec §4.3).
//
//	bazel run //tools/ci:gen        # //tools/delivery/gen behind the spec's alias
//
// WHY A GENERATOR AT ALL. The repo's delivery surface is 19 hand-written
// workflows that each re-implement the same five things (a changed-paths gate,
// a concurrency posture, a GitHub Environment ladder, a fan-out, an artifact
// upload) slightly differently. Every incident this week was one of those
// copies drifting from the others rather than any of them being wrong in
// isolation:
//
//   - #1759: six jobs made `github.event_name == 'push'` an unconditional first
//     clause, so the path gate they all shared was bypassed on main.
//   - #1763: a gated job kept the default depth-1 checkout, so its gate diffed
//     against a `github.event.before` that was not in the clone and fail-opened
//     forever. The gate was not broken; it could not see.
//   - #1794: a state-mutating Pulumi apply had no gate at all while every job
//     around it did — ~9 needless applies a day against the OIDC stack whose
//     force-replace deletes the live client.
//
// A generator makes those five things exist ONCE. The declaration (the
// delivery() macro, tools/delivery/defs.bzl) is the only thing a human writes;
// the workflow is a build artifact, and tidy-check fails the PR if the artifact
// is stale (see .github/workflows/tidy-check.yaml).
//
// PHASE 1 SCOPE (spec §6). --phase 0 is shadow mode: one `orchestrate` job that
// computes and uploads a delivery manifest and acts on nothing. --phase 1 (the
// DEFAULT, and what .github/workflows/delivery.yaml is generated at today)
// additionally renders the PUSH LANE'S FIRST RUNG — environments[0], i.e.
// development — for every cloud-run unit, plus that unit's companions. It
// renders NOTHING for nonproduction/production: promotion stays release-gated
// in the legacy per-app workflow until Phase 2, and rendering a promotion job
// that nothing triggers would be an invitation to wire it up by hand.
//
// WHAT THE PHASE-1 SKELETON GOT WRONG, all of it now covered by a test:
//
//   - it rendered `bazel run <unit run target>` directly, with no image, no
//     WIF credentials and no secrets — a job that could only ever fail. The
//     image is now built by a generated `<unit>-build` job (renderBuildJob),
//     transcribed once from the hand-written one and asserted against it;
//   - it chained the WHOLE ladder off a push, so a merge to main would have
//     deployed production;
//   - it rendered no companion job, so the OIDC client would not exist when
//     the new revision arrived (the expand-before-serve half, §2.15);
//   - it referenced `needs.orchestrate.outputs.affected_oauth-user-inspector`
//     with DASHES while the orchestrator emits UNDERSCORES. GitHub Actions
//     resolves an unknown output to the empty string rather than erroring, so
//     that condition could never be true: a workflow that looks green forever
//     while delivering nothing. outputVarName below now folds names by the
//     orchestrator's EXACT rule, pinned by the same table on both sides and by
//     TestEveryAffectedOutputNameIsOneTheOrchestratorEmits, which re-derives
//     every `affected_*` token out of the rendered YAML.
//
// DETERMINISM IS A HARD REQUIREMENT, not a nicety: tidy-check asserts
// `git diff --exit-code` after a regenerate, so any instability (map iteration
// order, unsorted units, a timestamp) would turn the enforcement step into a
// flaky red on unrelated PRs and get it deleted. Units are sorted by name
// everywhere, nothing time- or environment-dependent is emitted, and
// TestRenderIsOrderIndependent guards it.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// schemaVersion is the delivery() metadata contract this generator understands
// (tools/delivery/defs.bzl writes `"schema": 1`). Refusing an unknown version
// is deliberate: the macro and this renderer are edited by different people at
// different times, and a silently-ignored new field is exactly the class of
// drift that produces a green regenerate rendering a workflow that no longer
// matches the declaration.
const schemaVersion = 1

// generatedBanner is the loud, single-line DO-NOT-EDIT marker. Kept on one line
// on purpose: it is what a human sees first in a diff, and what
// tools/conformance/check.sh greps for to prove delivery.yaml is the generated
// file and not a hand-edited namesake.
const generatedBanner = "# GENERATED by 'bazel run //tools/ci:gen' from delivery() declarations — DO NOT EDIT. tidy-check enforces regeneration."

// killSwitchExpr is the spec §6.1 level-1 rollback guarantee: flipping the
// DELIVERY_ORCHESTRATOR_ENABLED repo variable to anything but "true" makes the
// whole workflow a no-op WITHOUT a commit, a revert, or a deploy. It is
// asserted three ways — here, in TestKillSwitchIsRendered, and in
// //tools/conformance:check's check_delivery against the committed file —
// because a rollback control that is merely believed to be present is not a
// rollback control.
const killSwitchExpr = "vars.DELIVERY_ORCHESTRATOR_ENABLED == 'true'"

// checkoutPin / setupBazel / uploadArtifactPin mirror the pins the rest of
// .github/workflows already uses, so Dependabot's github-actions ecosystem
// bumps this file's output the same day it bumps every hand-written lane. A
// divergent pin here would be invisible: nobody reviews a generated file's
// action versions by eye.
const (
	checkoutPin       = "actions/checkout@v7.0.1"
	setupBazelAction  = "./.github/actions/setup-bazel"
	uploadArtifactPin = "actions/upload-artifact@v7"
)

// mitHeader is the licence block every file in this repo carries, in `#`
// comment form for YAML. //tools/license:check enforces its presence, and it
// is stricter than the local verify.sh, so a generated file missing it fails
// CI while passing locally.
const mitHeader = `# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
`

// kindCloudRun is the only kind Phase 1 fans out. A "pulumi" unit reaches the
// generated file only as another unit's COMPANION (see companionWorkflows);
// "publish" units are Phase 2. Rendering a job for a kind whose invocation
// shape has not been designed yet would be a guess, and a guess in a delivery
// workflow is a deploy that fails at 2am.
const kindCloudRun = "cloud-run"

// The reusable workhorses. Spec §4.3 keeps them AS-IS and makes the generated
// file a thin caller layer, which is why this is a re-plumbing rather than a
// rewrite of deploy logic — every input below is a `workflow_call` input those
// files already declare.
const cloudRunWorkflow = "./.github/workflows/_deploy-cloud-run.yaml"

// buildRung is the pseudo-environment the BUILD job binds to.
//
// Build-once/promote-by-digest builds ONCE, into a shared Artifact Registry in
// the infra-pipeline project, and every environment then deploys that one
// immutable digest. That registry is reached with the credentials of a GitHub
// Environment which is not a rung of the ladder — it is
// "<github_environment pattern with {env}=build>", i.e.
// oauth-user-inspector-build today, exactly as the hand-written build job
// declares. Deriving it from the same pattern keeps ONE naming rule for
// environments; TestGeneratedBuildJobMatchesLegacy pins the result against the
// real workflow, so the derivation cannot quietly resolve to a non-existent
// environment (which fails a run at startup with no jobs instantiated).
const buildRung = "build"

// defaultRegion is the fallback baked into the build job's `GCP_REGION` when
// the Environment defines none — kept equal to _deploy-cloud-run.yaml's own
// `default-region` default so the build and the deploy can never disagree
// about which registry host they are talking to. A declaration that pins
// `default-region` in workflow_inputs wins over this (same fact, one source).
const defaultRegion = "us-central1"

// setupGcloudPin is the SHA-pinned Cloud SDK action, byte-identical to the
// hand-written build job's. Kept as a constant beside the other pins so
// Dependabot's bump lands in one place (see the DEPENDABOT note rendered into
// the generated file).
const setupGcloudPin = "google-github-actions/setup-gcloud@aa5489c8933f4cc7a4f7d45035b3b1440c9c10db # v3.0.1"

// gcpAuthAction is the repo's WIF composite. Ambient keyless auth: the
// Environment supplies the provider + service account as variables, so no
// credential is ever a GitHub secret.
const gcpAuthAction = "./.github/actions/gcp-auth"

// cloudRunRequiredInputs are _deploy-cloud-run.yaml's `required: true` inputs
// MINUS `environment` (which the ladder supplies). Checked before rendering:
// GitHub only reports a missing required input when the job starts, i.e.
// mid-delivery on main, whereas this fails the regenerate that introduced it.
var cloudRunRequiredInputs = []string{"app-name", "env-prefix", "pulumi-dir", "service-name"}

// companionSpec says HOW a companion unit is applied from its consumer's
// ladder: which reusable workflow runs it, and any extra repo-variable gate
// that must hold.
type companionSpec struct {
	workflow string
	// gateVar is an additional `if:` clause, "" for none. It exists because
	// the zitadel companion is gated on ZITADEL_APPS_AUTO_APPLY today
	// (oauth-user-inspector-deploy.yaml's zitadel-dev job) — the variable is
	// still the switch that keeps the apply off until the machine-user key and
	// stack ids are seeded, and dropping it here would turn "cleanly no-ops"
	// into "fails the deploy".
	gateVar string
}

// companionWorkflows is an EXPLICIT table, deliberately not a naming
// convention ("_" + name + "-apply.yaml"). A convention would silently render
// a `uses:` pointing at a file that does not exist — GitHub fails the whole
// workflow at startup for that, taking `orchestrate` down with it. An
// unlisted companion is a hard generator error instead, which is a
// five-second fix at declaration time.
var companionWorkflows = map[string]companionSpec{
	"zitadel-apps": {
		workflow: "./.github/workflows/_zitadel-apps-apply.yaml",
		gateVar:  "vars.ZITADEL_APPS_AUTO_APPLY == 'true'",
	},
}

// callerPermissions is the grant a reusable-workflow CALLER job needs.
//
// It is job-level, not workflow-level, on purpose. Both callees
// (_deploy-cloud-run.yaml, _zitadel-apps-apply.yaml) authenticate to GCP with
// keyless WIF and therefore need `id-token: write`; a called workflow's own
// `permissions:` can only NARROW what the caller job holds, never widen it, so
// the caller must hold it. Granting it at the WORKFLOW level (which is how
// oauth-user-inspector-deploy.yaml does it) would also hand it to
// `orchestrate`, which never talks to GCP. A job-level block on a `uses:` job
// is proven to work in this repo today — oauth-user-inspector-deploy.yaml's
// `gate` job carries exactly this shape.
var callerPermissions = []string{"contents: read", "id-token: write"}

// unit is one delivery() declaration, decoded from the JSON the macro writes.
//
// These structs are DELIBERATELY not shared with //tools/delivery/orchestrate:
// both decode the same on-disk contract independently, so a macro change that
// only one of them was taught about shows up as a disagreement between two
// programs rather than as a silent no-op in one. The shared thing is the JSON
// schema, which is versioned (see schemaVersion) precisely so that works.
type unit struct {
	Schema int    `json:"schema"`
	Name   string `json:"name"`
	Kind   string `json:"kind"`
	Run    string `json:"run"`
	Build  string `json:"build"`

	// How the unit's image is produced when it is NOT a Bazel target. The
	// generated <unit>-build job is the hand-written build job it replaces,
	// parameterized by exactly these two facts (the region and project come
	// from the build GitHub Environment's vars).
	BuildContext        string `json:"build_context"`
	ImageRepositoryPath string `json:"image_repository_path"`

	Environments      []string `json:"environments"`
	GitHubEnvironment string   `json:"github_environment"`
	Promotion         string   `json:"promotion"`
	Companions        []string `json:"companions"`
	ExtraPaths        []string `json:"extra_paths"`
	ExcludePaths      []string `json:"exclude_paths"`
	Preflight         string   `json:"preflight"`
	Package           string   `json:"package"`

	// WorkflowInputs is the `with:` map handed to the unit's reusable
	// workflow. `any` rather than map[string]string because the values are
	// typed workflow_call inputs — `workload-migrated: false` must render as
	// a YAML boolean, not the string "false", or GitHub coerces it back to
	// TRUE (a non-empty string is truthy) and the deploy skips its own
	// blue-green. delivery() rejects non-scalars, and yamlScalar rejects them
	// again here.
	WorkflowInputs map[string]any `json:"workflow_inputs"`
}

// decodeUnit parses one *.delivery.json and validates the invariants the
// renderer relies on. Every failure here is a hard error rather than a skip:
// a unit that silently vanished from the generated file is indistinguishable
// from a unit that was never declared, which is the #1794 failure shape
// (something that should have been gated simply was not there).
func decodeUnit(b []byte) (unit, error) {
	var u unit
	if err := json.Unmarshal(b, &u); err != nil {
		return u, fmt.Errorf("decode: %w", err)
	}
	if u.Schema != schemaVersion {
		return u, fmt.Errorf("unit %q: schema %d, this generator understands %d — regenerate after updating tools/delivery/gen for the new macro contract", u.Name, u.Schema, schemaVersion)
	}
	if u.Name == "" {
		return u, errors.New("unit has no name")
	}
	if u.Run == "" {
		return u, fmt.Errorf("unit %q has no run target", u.Name)
	}
	if len(u.Environments) == 0 {
		return u, fmt.Errorf("unit %q has an empty environment ladder", u.Name)
	}
	return u, nil
}

// loadUnits reads and decodes every path, then sorts by name. Sorting HERE
// (not at each use site) is what makes the output byte-stable no matter what
// order `bazel query` happened to print labels in.
func loadUnits(paths []string) ([]unit, error) {
	units := make([]unit, 0, len(paths))
	for _, p := range paths {
		b, err := os.ReadFile(p)
		if err != nil {
			return nil, fmt.Errorf("read %s: %w", p, err)
		}
		u, err := decodeUnit(b)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", p, err)
		}
		units = append(units, u)
	}
	sort.Slice(units, func(i, j int) bool { return units[i].Name < units[j].Name })

	// Duplicate names would render two jobs with the same id (invalid YAML
	// semantics: the second silently wins). //tools/conformance:check catches
	// this statically and offline; catching it here too means `bazel run
	// //tools/ci:gen` cannot produce the broken file in the first place.
	for i := 1; i < len(units); i++ {
		if units[i].Name == units[i-1].Name {
			return nil, fmt.Errorf("duplicate delivery unit name %q — unit names must be unique repo-wide", units[i].Name)
		}
	}
	return units, nil
}

// promotionNote renders the promotion field for the human-readable unit
// inventory. "" means "every environment delivers on push".
func promotionNote(u unit) string {
	if u.Promotion == "" {
		return "push-all"
	}
	return u.Promotion
}

// renderInventory emits the declared-unit inventory as a YAML comment block.
//
// WHY THE GENERATED FILE CARRIES A UNIT LIST AT ALL: not every declared unit
// renders a job (Phase 1 fans out cloud-run units only, and only their first
// rung), so without an inventory a change to a not-yet-rendered declaration
// would produce NO diff — and the tidy-check regeneration assertion, the one
// gate proving this file tracks the declarations, would prove nothing about
// it. The inventory makes every declaration change visible in the generated
// artifact regardless of phase. Deliberately WITHOUT column alignment: an
// aligned table re-flows every row when the longest name changes, turning a
// one-unit diff into a whole-block diff.
func renderInventory(b *strings.Builder, units []unit) {
	b.WriteString("# Units declared today (sorted by name). The orchestrator re-derives this list\n")
	b.WriteString("# at run time from the Bazel graph — it is reproduced here so that adding,\n")
	b.WriteString("# renaming or deleting a delivery() declaration shows up as a DIFF in this\n")
	b.WriteString("# generated file, which is what makes tidy-check's regeneration assertion\n")
	b.WriteString("# mean something even for a unit that renders no job yet.\n")
	if len(units) == 0 {
		// A zero-unit render is almost certainly a discovery failure (a broken
		// query, a moved tag) rather than a repo with no delivery units, so say
		// so loudly in the artifact a human reads.
		b.WriteString("#   (none — if that is unexpected, `bazel query 'attr(tags, \"delivery\", //...)'` found nothing)\n")
		return
	}
	for _, u := range units {
		fmt.Fprintf(b, "#   - %s  kind=%s  run=%s  envs=%s  promotion=%s\n",
			u.Name, u.Kind, u.Run, strings.Join(u.Environments, ","), promotionNote(u))
		// The unit's affected-detection inputs. Rendered because "why did (or
		// didn't) this unit deliver" is the first question anyone asks of this
		// file, and the answer used to be invisible here — it lives in the
		// declaration, which is a different file in a different language.
		// tools/conformance/check.sh's deploy-sequencer guard reads the
		// DECLARATIONS for the same coupling; this is the human-readable half.
		if len(u.ExtraPaths) > 0 {
			fmt.Fprintf(b, "#       paths:  %s\n", strings.Join(u.ExtraPaths, " "))
		}
		if len(u.ExcludePaths) > 0 {
			fmt.Fprintf(b, "#       except: %s\n", strings.Join(u.ExcludePaths, " "))
		}
	}
}

// render produces the complete .github/workflows/delivery.yaml text.
//
// phase 0 = shadow (orchestrate only). phase 1 additionally renders the push
// lane's FIRST rung per cloud-run unit (plus its companions). workflowFile is
// the generated file's own basename, which the durable-base resolver needs to
// query this workflow's own run history.
//
// It returns an error for every input that would render a workflow GitHub
// rejects at startup, or accepts and then fails mid-delivery — an unknown
// companion, a missing required input, a non-scalar `with:` value. A generator
// that renders such a file "successfully" moves the failure from a regenerate
// (cheap, local, attributable) to a push to main (expensive, remote, and
// discovered by the deploy not happening).
func render(units []unit, phase int, workflowFile string) (string, error) {
	var b strings.Builder

	b.WriteString(mitHeader)
	b.WriteString("\n")
	b.WriteString(generatedBanner)
	b.WriteString("\n#\n")
	b.WriteString("# Source of truth: the delivery() declarations in the Bazel graph\n")
	b.WriteString("# (tools/delivery/defs.bzl). Renderer: //tools/delivery/gen, aliased\n")
	b.WriteString("# //tools/ci:gen. Editing this file by hand is a no-op that CI reverts:\n")
	b.WriteString("# tidy-check regenerates and fails on any diff.\n")
	b.WriteString("#\n")
	b.WriteString("# DEPENDABOT: the action pins below are rendered from constants in\n")
	b.WriteString("# tools/delivery/gen/main.go. Dependabot's github-actions ecosystem scans\n")
	b.WriteString("# every file under .github/workflows/, so it will offer to bump them HERE —\n")
	b.WriteString("# and that PR fails tidy-check, because the next regeneration puts the old\n")
	b.WriteString("# pin back. Apply the bump to the constant in main.go and run\n")
	b.WriteString("# `bazel run //tools/ci:gen`; the diff in this file then matches.\n")
	b.WriteString("#\n")
	renderPhaseNote(&b, phase)
	b.WriteString("#\n")
	renderInventory(&b, units)
	b.WriteString("\n")

	b.WriteString("name: delivery\n")
	b.WriteString("\n")
	b.WriteString("on:\n")
	b.WriteString("  push:\n")
	b.WriteString("    branches: [main]\n")
	// Deliberately NO `paths:` filter, at any phase: GitHub evaluates a
	// workflow-level path filter over the same event range a dropped run
	// loses, so a filtered-out push is a PERMANENT skip with no job to blame
	// (#1351). Relevance is decided by `orchestrate`, which is a job, logs its
	// reasoning, and fails open.
	//
	// No `workflow_dispatch` inputs: a manual re-delivery of one unit is the
	// break-glass `bazel run <unit run target>` in the runbook (identical
	// target, no Actions dependency), and until Phase 2 the legacy per-app
	// workflow keeps its own single-env dispatch.
	b.WriteString("  workflow_dispatch: {}\n")
	b.WriteString("\n")
	b.WriteString("# Least privilege AT THE WORKFLOW LEVEL: `contents: read` to check out and\n")
	b.WriteString("# `actions: read` so the orchestrator can resolve a durable diff base from\n")
	b.WriteString("# this workflow's own run history. `id-token: write` is deliberately NOT\n")
	b.WriteString("# here — the fan-out jobs that need WIF grant it on THEMSELVES (see their\n")
	b.WriteString("# job-level permissions blocks), so `orchestrate`, which never talks to\n")
	b.WriteString("# GCP, cannot mint a cloud credential.\n")
	b.WriteString("permissions:\n")
	b.WriteString("  contents: read\n")
	b.WriteString("  actions: read\n")
	b.WriteString("\n")
	b.WriteString("# State-mutation posture: one constant group, never cancel. Two delivery\n")
	b.WriteString("# runs must not race the same live environment, and a queued run must not be\n")
	b.WriteString("# cancelled mid-rollout.\n")
	b.WriteString("#\n")
	b.WriteString("# WHY WORKFLOW-LEVEL AND NOT PER-UNIT (spec §4.3 asks for\n")
	b.WriteString("# `delivery-<unit>-<env>` groups): every fan-out job below is a `uses:`\n")
	b.WriteString("# caller, and this repo has already paid for that experiment — #1607 put a\n")
	b.WriteString("# `concurrency:` on the calling jobs in tabula-deploy.yaml and every\n")
	b.WriteString("# dispatch failed INSTANTLY with no runner assigned, reproducibly, even\n")
	b.WriteString("# with a static expression-free group string; workflow-level was the only\n")
	b.WriteString("# placement that worked. A constant group here is strictly STRONGER\n")
	b.WriteString("# serialization than per-unit groups (it also serializes unrelated units,\n")
	b.WriteString("# which at this scale costs nothing) — it can never let two runs touch one\n")
	b.WriteString("# environment at once. Revisit only with a live experiment, never by\n")
	b.WriteString("# reasoning from the docs.\n")
	b.WriteString("#\n")
	b.WriteString("# KNOWN CONSEQUENCE (#1351), now MITIGATED: a constant group means GitHub\n")
	b.WriteString("# evicts an already-PENDING run when a newer one queues, and\n")
	b.WriteString("# `github.event.before` is fixed at the EVICTED run's push — a range no\n")
	b.WriteString("# successor re-diffs, i.e. a silent permanent skip. The orchestrate job\n")
	b.WriteString("# therefore resolves a DURABLE base from this workflow's last successful\n")
	b.WriteString("# push run (tools/ci/resolve-deploy-base.sh) and only falls back to\n")
	b.WriteString("# github.event.before when that cannot be determined.\n")
	b.WriteString("concurrency:\n")
	b.WriteString("  group: delivery-orchestrate\n")
	b.WriteString("  cancel-in-progress: false\n")
	b.WriteString("\n")
	b.WriteString("jobs:\n")
	renderOrchestrateJob(&b, units, workflowFile)

	// ---- Phase 1+ boundary -------------------------------------------------
	if phase >= 1 {
		if err := renderPhase1Jobs(&b, units); err != nil {
			return "", err
		}
	}

	return b.String(), nil
}

// renderPhaseNote emits the "what does this file actually do today" paragraph.
// It is phase-dependent because the honest answer changes: at phase 0 a wrong
// verdict costs an artifact, at phase 1 it costs a deploy.
func renderPhaseNote(b *strings.Builder, phase int) {
	if phase < 1 {
		b.WriteString("# PHASE 0 — SHADOW. This workflow decides nothing and delivers nothing. It\n")
		b.WriteString("# computes a delivery manifest (which units a push affects, and why) and\n")
		b.WriteString("# uploads it as an artifact. The hand-written delivery workflows remain\n")
		b.WriteString("# the acting path, so a wrong verdict here costs an artifact, not a\n")
		b.WriteString("# deploy. That is the whole point of shipping the detector before the\n")
		b.WriteString("# actuator: real main-branch data to A/B the verdicts against.\n")
		return
	}
	b.WriteString("# PHASE 1 — THE DEVELOPMENT RUNG ACTS (spec §6). On a push to main this\n")
	b.WriteString("# workflow now DELIVERS: for every cloud-run unit the orchestrator finds\n")
	b.WriteString("# affected, it applies that unit's companions and then deploys its FIRST\n")
	b.WriteString("# environment. Nonproduction and production are NOT rendered here — they\n")
	b.WriteString("# stay release-gated in the legacy per-app workflow until Phase 2, which is\n")
	b.WriteString("# also why that workflow keeps its `release:` and `workflow_dispatch`\n")
	b.WriteString("# triggers (only its `push:` trigger was removed).\n")
	b.WriteString("#\n")
	b.WriteString("# ROLLBACK (spec §6.1): flip the DELIVERY_ORCHESTRATOR_ENABLED repo\n")
	b.WriteString("# variable to false and every job below no-ops without a commit; the legacy\n")
	b.WriteString("# workflow's workflow_dispatch is the level-0 \"deliver now\" path, and the\n")
	b.WriteString("# break-glass `bazel run` targets are unchanged.\n")
}

// renderOrchestrateJob emits the DECIDE job every other job hangs off.
func renderOrchestrateJob(b *strings.Builder, units []unit, workflowFile string) {
	b.WriteString("  orchestrate:\n")
	b.WriteString("    # Kill switch (spec §6.1, rollback level 1): flip the\n")
	b.WriteString("    # DELIVERY_ORCHESTRATOR_ENABLED repo variable to disable the whole\n")
	b.WriteString("    # orchestrator without a commit, a revert or a deploy. Repo-scoped, not\n")
	b.WriteString("    # environment-scoped: a job-level `if:` cannot see an environment\n")
	b.WriteString("    # variable. Declared in infrastructure/pulumi/platform/repo_config.\n")
	fmt.Fprintf(b, "    if: %s\n", killSwitchExpr)
	b.WriteString("    runs-on: ubuntu-latest\n")
	b.WriteString("    timeout-minutes: 15\n")
	renderOrchestrateOutputs(b, units)
	b.WriteString("    steps:\n")
	fmt.Fprintf(b, "      - uses: %s\n", checkoutPin)
	b.WriteString("        with:\n")
	b.WriteString("          # fetch-depth: 0 is LOAD-BEARING, not hygiene. The engine diffs\n")
	b.WriteString("          # HEAD against `github.event.before`, which does not exist in the\n")
	b.WriteString("          # default depth-1 clone — the gate then fail-opens on every run\n")
	b.WriteString("          # and reports \"affected\" for everything, forever, while looking\n")
	b.WriteString("          # perfectly healthy. That is exactly #1763: the gate was not\n")
	b.WriteString("          # broken, it could not see.\n")
	b.WriteString("          fetch-depth: 0\n")
	fmt.Fprintf(b, "      - uses: %s\n", setupBazelAction)
	b.WriteString("      - name: Resolve the durable diff base (#1351)\n")
	b.WriteString("        id: durable-base\n")
	b.WriteString("        env:\n")
	b.WriteString("          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}\n")
	fmt.Fprintf(b, "          WORKFLOW_FILE: %s\n", workflowFile)
	b.WriteString("        # Reads THIS workflow's last successful push run and uses its head\n")
	b.WriteString("        # sha as the diff base, so a run evicted by the constant\n")
	b.WriteString("        # concurrency group above does not take its commit range to the\n")
	b.WriteString("        # grave. Always exits 0: an empty base_sha means \"could not\n")
	b.WriteString("        # determine\", and the step below falls back.\n")
	b.WriteString("        run: bash tools/ci/resolve-deploy-base.sh\n")
	b.WriteString("      - name: Compute the delivery manifest\n")
	b.WriteString("        id: manifest\n")
	b.WriteString("        env:\n")
	b.WriteString("          # Durable base first, github.event.before only as the fallback\n")
	b.WriteString("          # (empty is falsy in a GitHub Actions expression). The engine\n")
	b.WriteString("          # itself fails open if BOTH are unusable.\n")
	b.WriteString("          BEFORE_REV: ${{ steps.durable-base.outputs.base_sha || github.event.before }}\n")
	b.WriteString("          # A force-push makes any base untrustworthy; the orchestrator\n")
	b.WriteString("          # turns this into a whole-manifest fail-open with a loud reason.\n")
	b.WriteString("          FORCED_PUSH: ${{ github.event.forced }}\n")
	b.WriteString("          # The affected engine may build/query through the shared remote\n")
	b.WriteString("          # cache; absent (e.g. a fork) it degrades to a local build.\n")
	b.WriteString("          BUILDBUDDY_API_KEY: ${{ secrets.BUILDBUDDY_API_KEY }}\n")
	b.WriteString("        run: bazel run //tools/delivery/orchestrate -- --out delivery-manifest.json\n")
	b.WriteString("      - name: Upload the delivery manifest\n")
	fmt.Fprintf(b, "        uses: %s\n", uploadArtifactPin)
	b.WriteString("        with:\n")
	b.WriteString("          name: delivery-manifest\n")
	b.WriteString("          path: delivery-manifest.json\n")
	b.WriteString("          # 30 days: long enough to A/B a delivery verdict against what the\n")
	b.WriteString("          # legacy workflows actually did, which is how each phase is\n")
	b.WriteString("          # signed off before the legacy path is deleted.\n")
	b.WriteString("          retention-days: 30\n")
}

// renderOrchestrateOutputs re-exports the step's $GITHUB_OUTPUT as JOB outputs.
//
// THIS BLOCK IS LOAD-BEARING AND EASY TO FORGET. A step writing $GITHUB_OUTPUT
// is NOT automatically visible to `needs.<job>.outputs.<name>`: the job has to
// re-export it. Without this, every `affected_*` a fan-out job reads resolves
// to the empty string, every condition is false, and the workflow is green
// forever while delivering nothing — the same silent-skip shape as the
// skeleton's dash bug, from a different cause. actionlint catches it
// ("property ... is not defined in object type {}"), which is why the
// generated file is linted like any hand-written one.
//
// One line per DECLARED unit, not per rendered job: the orchestrator emits a
// verdict for every unit it discovers, and a static output list is exactly the
// kind of thing generation makes tractable and hand-YAML does not.
func renderOrchestrateOutputs(b *strings.Builder, units []unit) {
	b.WriteString("    outputs:\n")
	b.WriteString("      # `manifest` is the whole delivery-manifest.json, compact, for a\n")
	b.WriteString("      # consumer that needs more than a boolean (fromJSON in a future\n")
	b.WriteString("      # phase). The affected_* pairs are the convenience form a job-level\n")
	b.WriteString("      # `if:` can actually read — expressions cannot index into JSON.\n")
	b.WriteString("      manifest: ${{ steps.manifest.outputs.manifest }}\n")
	for _, u := range units {
		name := outputVarName(u.Name)
		fmt.Fprintf(b, "      affected_%s: ${{ steps.manifest.outputs.affected_%s }}\n", name, name)
	}
}

// ---------------------------------------------------------------------------
// Phase 1 fan-out (spec §4.3, §6).
// ---------------------------------------------------------------------------

// renderPhase1Jobs emits, per cloud-run unit, the PUSH LANE'S FIRST RUNG only:
// the unit's companion applies, then its deploy.
//
// Shape and every clause of it is inherited from the job it replaces
// (oauth-user-inspector-deploy.yaml's zitadel-dev + deploy-dev), because Phase
// 1's acceptance test is "identical deploy behaviour to today" measured on a
// real push — not "a defensible new design".
func renderPhase1Jobs(b *strings.Builder, units []unit) error {
	byName := make(map[string]unit, len(units))
	for _, u := range units {
		byName[u.Name] = u
	}
	// Deduped across units: two consumers may share one companion, and two
	// jobs with the same id is a YAML mapping whose second entry silently
	// wins.
	renderedCompanions := make(map[string]bool)

	for _, u := range units {
		if u.Kind != kindCloudRun {
			continue
		}
		if err := checkCloudRunInputs(u); err != nil {
			return err
		}
		// environments[0] IS the push rung, by the declaration's own contract
		// ("ordered ladder"); later rungs promote on a release event.
		env := u.Environments[0]

		fmt.Fprintf(b, "\n  # ======== unit: %s → %s ========\n", u.Name, env)
		fmt.Fprintf(b, "  # Declared in %s/BUILD; break-glass target: %s\n", u.Package, u.Run)
		fmt.Fprintf(b, "  # GitHub Environment: %s (approvals + keyless-WIF vars live there)\n",
			strings.ReplaceAll(u.GitHubEnvironment, "{env}", env))
		if u.Promotion != "" {
			fmt.Fprintf(b, "  # Promotion to %s: still the legacy ladder, on %s* (Phase 2 migrates it).\n",
				strings.Join(u.Environments[1:], "/"), strings.TrimPrefix(u.Promotion, "release:"))
		}

		buildJob := u.Name + "-build"
		if err := renderBuildJob(b, buildJob, u); err != nil {
			return err
		}

		companionJobs := make([]string, 0, len(u.Companions))
		for _, c := range u.Companions {
			name := companionUnitName(c)
			cu, ok := byName[name]
			if !ok {
				return fmt.Errorf("unit %q lists companion %q, which is not a declared delivery() unit — the generated `needs:` would reference a job that does not exist and GitHub would reject the whole workflow at startup", u.Name, c)
			}
			spec, ok := companionWorkflows[name]
			if !ok {
				return fmt.Errorf("unit %q lists companion %q, but //tools/delivery/gen has no reusable workflow registered for it — add it to companionWorkflows (an unregistered companion would render a `uses:` pointing nowhere)", u.Name, name)
			}
			if !contains(cu.Environments, env) {
				return fmt.Errorf("unit %q delivers to %q first, but its companion %q declares no %q rung (environments = %v) — the companion cannot expand for an environment it does not have", u.Name, env, name, env, cu.Environments)
			}
			job := name + "-" + env
			companionJobs = append(companionJobs, job)
			if renderedCompanions[job] {
				continue
			}
			renderedCompanions[job] = true
			if err := renderCompanionJob(b, job, u, cu, spec, env); err != nil {
				return err
			}
		}
		if err := renderDeployJob(b, u, env, buildJob, companionJobs); err != nil {
			return err
		}
	}
	return nil
}

// renderBuildJob emits BUILD ONCE: push the image a single time and capture the
// immutable digest every environment then promotes.
//
// TRANSCRIBED, ONCE, FROM THE JOB IT REPLACES —
// oauth-user-inspector-deploy.yaml's `build` — and asserted against it by
// TestGeneratedBuildJobMatchesLegacy, which compares the rendered steps to the
// real ones text-for-text. Doing the build here rather than inside
// _deploy-cloud-run.yaml's `dockerfile-dir` path is not a style preference; that
// path is UNEXERCISED by any workflow in this repo and cannot work for this app:
//
//  1. it pushes an image but never resolves a digest, so the rollout runs
//     `--image-tag $GITHUB_SHA`, and the app's Pulumi program reads only
//     <PREFIX>_IMAGE_DIGEST ("deliberately no mutable-tag fallback",
//     oauth-user-inspector/infra/app/main.go) — `pulumi up` fails outright;
//  2. it would push into the ENVIRONMENT's project, where the per-env deploy SA
//     holds artifactregistry.READER (foundation module app_deploy_identity);
//     writer exists only in the build space.
//
// The build Environment's own SA does have writer on the shared registry, which
// is why THIS shape needs no IAM change and no edit to the shared workflow.
func renderBuildJob(b *strings.Builder, job string, u unit) error {
	if u.Build != "" {
		return fmt.Errorf("unit %q declares build=%q (a Bazel image target); the generated build job renders the Docker path only — teach //tools/delivery/gen the bazel-image shape before declaring one", u.Name, u.Build)
	}
	if u.BuildContext == "" || u.ImageRepositoryPath == "" {
		return fmt.Errorf("unit %q needs build_context and image_repository_path to render its build job (delivery() enforces this too; a unit reaching here without them would render a build that pushes nothing)", u.Name)
	}

	region := defaultRegion
	if v, ok := u.WorkflowInputs["default-region"].(string); ok && v != "" {
		region = v
	}

	b.WriteString("\n")
	b.WriteString("  # BUILD ONCE, promote by digest: the image is pushed a single time, into\n")
	b.WriteString("  # the shared Artifact Registry owned by the build Environment's project,\n")
	b.WriteString("  # and every rung deploys that one immutable @sha256 ref. The app's Pulumi\n")
	b.WriteString("  # program accepts nothing else — there is deliberately no mutable-tag\n")
	b.WriteString("  # fallback — so this job is what makes the deploy below possible at all.\n")
	fmt.Fprintf(b, "  %s:\n", job)
	b.WriteString("    needs: [orchestrate]\n")
	fmt.Fprintf(b, "    if: %s\n", buildCondition(u))
	b.WriteString("    runs-on: ubuntu-latest\n")
	b.WriteString("    timeout-minutes: 30\n")
	b.WriteString("    permissions:\n")
	for _, p := range callerPermissions {
		fmt.Fprintf(b, "      %s\n", p)
	}
	fmt.Fprintf(b, "    environment: %s\n", strings.ReplaceAll(u.GitHubEnvironment, "{env}", buildRung))
	b.WriteString("    env:\n")
	b.WriteString("      GCP_PROJECT_ID: ${{ vars.GCP_PROJECT_ID }}\n")
	fmt.Fprintf(b, "      GCP_REGION: ${{ vars.GCP_REGION || '%s' }}\n", region)
	b.WriteString("    outputs:\n")
	b.WriteString("      image-digest: ${{ steps.push.outputs.image-digest }}\n")
	b.WriteString("    steps:\n")
	fmt.Fprintf(b, "      - uses: %s\n", checkoutPin)
	b.WriteString("\n")
	b.WriteString("      - name: Authenticate to Google Cloud\n")
	fmt.Fprintf(b, "        uses: %s\n", gcpAuthAction)
	b.WriteString("        with:\n")
	b.WriteString("          workload-identity-provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}\n")
	b.WriteString("          service-account: ${{ vars.GCP_DEPLOY_SERVICE_ACCOUNT }}\n")
	b.WriteString("\n")
	b.WriteString("      - name: Set up Cloud SDK\n")
	fmt.Fprintf(b, "        uses: %s\n", setupGcloudPin)
	b.WriteString("\n")
	b.WriteString("      - name: Configure docker for Artifact Registry\n")
	b.WriteString("        run: gcloud auth configure-docker \"${GCP_REGION}-docker.pkg.dev\" --quiet\n")
	b.WriteString("\n")
	b.WriteString("      - name: Build and push the image (capture the digest)\n")
	b.WriteString("        id: push\n")
	b.WriteString("        run: |\n")
	b.WriteString("          set -euo pipefail\n")
	fmt.Fprintf(b, "          IMAGE=\"${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/%s\"\n", u.ImageRepositoryPath)
	b.WriteString("          NODE_VERSION=\"$(cut -d. -f1 .nvmrc 2>/dev/null || echo 22)\"\n")
	b.WriteString("          docker buildx build --push \\\n")
	b.WriteString("            --build-arg NODE_VERSION=\"${NODE_VERSION}\" \\\n")
	b.WriteString("            --tag \"${IMAGE}:${GITHUB_SHA}\" \\\n")
	b.WriteString("            --tag \"${IMAGE}:latest\" \\\n")
	fmt.Fprintf(b, "            %s\n", u.BuildContext)
	b.WriteString("          # Resolve the immutable digest from the registry (driver-agnostic,\n")
	b.WriteString("          # vs. buildx --metadata-file which varies by builder): this exact\n")
	b.WriteString("          # @sha256 ref is what every env deploys.\n")
	b.WriteString("          DIGEST=\"$(gcloud artifacts docker images describe \"${IMAGE}:${GITHUB_SHA}\" \\\n")
	b.WriteString("            --format='value(image_summary.digest)')\"\n")
	b.WriteString("          if [ -z \"$DIGEST\" ]; then\n")
	b.WriteString("            echo \"::error::could not resolve the pushed image digest\"\n")
	b.WriteString("            exit 1\n")
	b.WriteString("          fi\n")
	b.WriteString("          echo \"Built ${IMAGE}@${DIGEST}\"\n")
	b.WriteString("          echo \"image-digest=${IMAGE}@${DIGEST}\" >> \"$GITHUB_OUTPUT\"\n")
	return nil
}

// buildCondition mirrors the companion's shape: the push lane's arms only (the
// legacy job's release/dispatch arms belong to the promotion ladder, which
// Phase 1 leaves in the legacy workflow).
func buildCondition(u unit) string {
	return strings.Join([]string{killSwitchExpr, "always()", "!cancelled()", orchestrateArm(u)}, " && ")
}

// renderCompanionJob emits the EXPAND half of expand-before-serve (§2.15):
// register the environment's OIDC client before its new revision arrives.
func renderCompanionJob(b *strings.Builder, job string, consumer, companion unit, spec companionSpec, env string) error {
	b.WriteString("\n")
	fmt.Fprintf(b, "  # EXPAND before serve (§2.15): %s is applied before\n", companion.Name)
	fmt.Fprintf(b, "  # %s's new revision takes traffic, or hosted login is\n", consumer.Name)
	b.WriteString("  # broken on arrival. Gated on the SAME verdict as the deploy below — if\n")
	b.WriteString("  # no revision is arriving there is nothing to expand for. Applying it\n")
	b.WriteString("  # unconditionally is #1794: ~9 needless applies a day against a stack\n")
	b.WriteString("  # whose force-replace DELETES the live OIDC client.\n")
	fmt.Fprintf(b, "  %s:\n", job)
	b.WriteString("    needs: [orchestrate]\n")
	b.WriteString("    # `always() && !cancelled()` (not the implicit success()-of-needs):\n")
	b.WriteString("    # orchestrate may legitimately be skipped or red, and the fail-open arm\n")
	b.WriteString("    # below has to be reachable in exactly those cases.\n")
	fmt.Fprintf(b, "    if: %s\n", companionCondition(spec, consumer))
	renderCallerPermissions(b)
	fmt.Fprintf(b, "    uses: %s\n", spec.workflow)
	if err := renderWith(b, companion.WorkflowInputs, env); err != nil {
		return fmt.Errorf("unit %q: companion %q: %w", consumer.Name, companion.Name, err)
	}
	b.WriteString("    secrets: inherit\n")
	return nil
}

// renderDeployJob emits the SERVE half.
func renderDeployJob(b *strings.Builder, u unit, env, buildJob string, companionJobs []string) error {
	b.WriteString("\n")
	fmt.Fprintf(b, "  %s-%s:\n", u.Name, env)
	needs := append([]string{"orchestrate", buildJob}, companionJobs...)
	fmt.Fprintf(b, "    needs: [%s]\n", strings.Join(needs, ", "))
	b.WriteString("    # The build MUST have succeeded (there is no image otherwise), while a\n")
	b.WriteString("    # companion that is SKIPPED — its repo-variable gate is off — must not\n")
	b.WriteString("    # block the deploy and one that FAILED must. `!cancelled()` keeps this\n")
	b.WriteString("    # reachable when a need was skipped, which the implicit\n")
	b.WriteString("    # success()-of-needs would not.\n")
	fmt.Fprintf(b, "    if: %s\n", deployCondition(u, buildJob, companionJobs))
	renderCallerPermissions(b)
	fmt.Fprintf(b, "    uses: %s\n", cloudRunWorkflow)
	// image-digest is the generator's to supply, not the declaration's: it
	// names a JOB this renderer created. Build-once/promote-by-digest is the
	// whole point — the digest that soaked on development is the one that
	// later promotes, never a rebuild.
	inputs := make(map[string]any, len(u.WorkflowInputs)+1)
	for k, v := range u.WorkflowInputs {
		inputs[k] = v
	}
	inputs["image-digest"] = fmt.Sprintf("${{ needs.%s.outputs.image-digest }}", buildJob)
	if err := renderWith(b, inputs, env); err != nil {
		return fmt.Errorf("unit %q: %w", u.Name, err)
	}
	b.WriteString("    secrets: inherit\n")
	return nil
}

func renderCallerPermissions(b *strings.Builder) {
	b.WriteString("    # Job-level, because a called workflow's permissions can only NARROW\n")
	b.WriteString("    # the caller's: keyless WIF needs id-token: write HERE, and granting it\n")
	b.WriteString("    # workflow-wide would hand it to orchestrate too.\n")
	b.WriteString("    permissions:\n")
	for _, p := range callerPermissions {
		fmt.Fprintf(b, "      %s\n", p)
	}
}

// outputVarName turns a unit name into the GitHub Actions job-output key the
// ORCHESTRATOR publishes: everything outside [A-Za-z0-9_] folded to "_".
//
// THIS RULE IS A CROSS-BINARY CONTRACT, copied character-for-character from
// //tools/delivery/orchestrate's outputVarName (see that function's comment
// for why the two cannot share a package in this repo today: the root go.mod
// module path and the Bazel/gazelle importpath prefix disagree, so a
// first-party cross-package import compiles under `bazel` or under `go`,
// never both). The Phase-1 skeleton's version left "-" alone and rendered a
// condition that could never be true. Both copies are pinned by an identical
// table — TestOutputVarNameIsTheOrchestratorContract here, TestOutputVarName
// there — so a one-sided edit fails its own package's test.
var notOutputSafe = regexp.MustCompile(`[^A-Za-z0-9_]`)

func outputVarName(name string) string {
	return notOutputSafe.ReplaceAllString(name, "_")
}

// affectedExpr is the orchestrator's per-unit verdict, read through that
// shared rule.
func affectedExpr(u unit) string {
	return fmt.Sprintf("needs.orchestrate.outputs.affected_%s == 'true'", outputVarName(u.Name))
}

// orchestrateArm is the fail-open half of every fan-out condition: deliver when
// the orchestrator says so, AND ALSO when the orchestrator did not manage to
// say anything (`result != 'success'` covers failed, skipped and the run being
// cancelled out from under it). Inherited verbatim from the job this replaces —
// detection must never be the reason a real change fails to ship.
func orchestrateArm(u unit) string {
	return fmt.Sprintf("(needs.orchestrate.result != 'success' || %s)", affectedExpr(u))
}

// companionCondition mirrors legacy zitadel-dev's `if:` with `orchestrate` in
// place of `gate`, and the kill switch in front.
func companionCondition(spec companionSpec, consumer unit) string {
	parts := []string{killSwitchExpr}
	if spec.gateVar != "" {
		parts = append(parts, spec.gateVar)
	}
	parts = append(parts, "always()", "!cancelled()", orchestrateArm(consumer))
	return strings.Join(parts, " && ")
}

// deployCondition mirrors legacy deploy-dev's `if:` clause for clause:
// `needs.<build>.result == 'success'` (no image, no deploy — and note this is
// an EQUALITY, not a `!= 'failure'`, so a SKIPPED build also stops the deploy),
// each companion tolerated when skipped and refused when failed, and the
// orchestrator's verdict with its fail-open arm.
func deployCondition(u unit, buildJob string, companionJobs []string) string {
	parts := []string{
		killSwitchExpr,
		"!cancelled()",
		fmt.Sprintf("needs.%s.result == 'success'", buildJob),
	}
	for _, job := range companionJobs {
		parts = append(parts, fmt.Sprintf("needs.%s.result != 'failure'", job))
	}
	parts = append(parts, orchestrateArm(u))
	return strings.Join(parts, " && ")
}

// renderWith emits the `with:` map: the declaration's workflow_inputs plus the
// rung this job serves. Keys are sorted so the output is byte-stable (Go map
// iteration is randomized on purpose, and tidy-check diffs bytes).
func renderWith(b *strings.Builder, inputs map[string]any, env string) error {
	merged := make(map[string]any, len(inputs)+1)
	for k, v := range inputs {
		merged[k] = v
	}
	// The ladder owns the environment; delivery() rejects an attempt to set it
	// in workflow_inputs, and this assignment is last so it cannot be shadowed
	// even if that guard were bypassed.
	merged["environment"] = env

	keys := make([]string, 0, len(merged))
	for k := range merged {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	b.WriteString("    with:\n")
	for _, k := range keys {
		v, err := yamlScalar(merged[k])
		if err != nil {
			return fmt.Errorf("workflow_inputs[%q]: %w", k, err)
		}
		fmt.Fprintf(b, "      %s: %s\n", k, v)
	}
	return nil
}

// yamlScalar renders one workflow_call input value.
//
// json.Marshal, not fmt: YAML 1.2 is a JSON superset, so a JSON scalar is a
// valid YAML scalar for every string this could hold, with the quoting and
// escaping already correct. It also keeps types honest — a bool renders as
// `false`, never as `"false"`, which GitHub would coerce back to true.
func yamlScalar(v any) (string, error) {
	switch v.(type) {
	case string, bool, float64, int:
		raw, err := json.Marshal(v)
		if err != nil {
			return "", fmt.Errorf("cannot render %v as a YAML scalar: %w", v, err)
		}
		return string(raw), nil
	case nil:
		return "", errors.New("value is null — a workflow_call input has no null; omit the key instead")
	default:
		return "", fmt.Errorf("value %v (%T) is not a scalar — a reusable workflow's inputs are string/boolean/number only", v, v)
	}
}

// checkCloudRunInputs fails the render when a cloud-run unit is missing an
// input _deploy-cloud-run.yaml declares `required: true`.
func checkCloudRunInputs(u unit) error {
	var missing []string
	for _, k := range cloudRunRequiredInputs {
		if _, ok := u.WorkflowInputs[k]; !ok {
			missing = append(missing, k)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("cloud-run unit %q is missing required workflow_inputs %v for %s — GitHub reports a missing required input only when the job STARTS, i.e. mid-delivery on main", u.Name, missing, cloudRunWorkflow)
	}
	return nil
}

// companionUnitName accepts the spellings a declaration may use for a
// companion — "zitadel-apps", ":zitadel-apps", "//pkg:zitadel-apps" — and
// returns the unit name. delivery() calls them "labels"; the unit NAME is what
// identifies a unit repo-wide (conformance enforces uniqueness), so that is
// what this resolves to.
func companionUnitName(c string) string {
	if i := strings.LastIndex(c, ":"); i >= 0 {
		return c[i+1:]
	}
	return c
}

func contains(hay []string, needle string) bool {
	for _, h := range hay {
		if h == needle {
			return true
		}
	}
	return false
}

// ---------------------------------------------------------------------------
// Discovery: the Bazel graph IS the delivery registry (spec §4.1).
// ---------------------------------------------------------------------------

// bazelRunner runs bazel and returns its stdout. Injected so the tests can
// drive discovery against a fake bazel without a workspace, the same way
// //tools/delivery/orchestrate does — an unpluggable exec.Command here would
// make discovery untestable and therefore untested.
type bazelRunner func(args ...string) ([]byte, error)

// execBazel is the production runner. `bazel` is resolved from --bazel /
// GEN_BAZEL / PATH.
func execBazel(bin, dir string) bazelRunner {
	return func(args ...string) ([]byte, error) {
		cmd := exec.Command(bin, args...)
		cmd.Dir = dir
		cmd.Stderr = os.Stderr
		return cmd.Output()
	}
}

// discover finds every delivery() unit and returns the paths of their metadata
// JSON files, sorted.
//
// `bazel query`, deliberately NOT `cquery`: query needs no configuration, so it
// cannot trip the macOS-toolchain resolution landmine that cost this repo #1039
// and #1297. The units are `manual`-tagged, so they never enter a wildcard
// build; we build them by explicit label after the query.
func discover(run bazelRunner) ([]string, error) {
	out, err := run("query", `attr(tags, "delivery", //...)`, "--output=label")
	if err != nil {
		return nil, fmt.Errorf("bazel query for delivery units: %w", err)
	}
	var labels []string
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		// The tag regex also matches the "delivery-kind=..." tag on the same
		// target, so filter on the macro's own naming convention rather than on
		// the tag alone.
		if strings.HasSuffix(line, ".delivery_unit") {
			labels = append(labels, line)
		}
	}
	sort.Strings(labels)
	if len(labels) == 0 {
		// Zero units is a discovery failure, not an empty repo: the generated
		// workflow would render an empty inventory and the diff would look
		// intentional. Fail instead of quietly rendering nothing — the
		// "green while checking nothing" shape this repo keeps re-learning.
		return nil, errors.New(`no delivery() units found by 'bazel query attr(tags, "delivery", //...)' — the tag, the macro, or the query drifted`)
	}

	if _, err := run(append([]string{"build"}, labels...)...); err != nil {
		return nil, fmt.Errorf("bazel build of delivery units: %w", err)
	}
	binOut, err := run("info", "bazel-bin")
	if err != nil {
		return nil, fmt.Errorf("bazel info bazel-bin: %w", err)
	}
	binDir := strings.TrimSpace(string(binOut))

	paths := make([]string, 0, len(labels))
	for _, l := range labels {
		pkg, target, ok := splitLabel(l)
		if !ok {
			return nil, fmt.Errorf("unparseable label %q", l)
		}
		// //pkg:<name>.delivery_unit -> bazel-bin/pkg/<name>.delivery.json
		base := strings.TrimSuffix(target, "_unit") + ".json"
		paths = append(paths, filepath.Join(binDir, filepath.FromSlash(pkg), base))
	}
	return paths, nil
}

// splitLabel splits "//some/pkg:target" into ("some/pkg", "target").
func splitLabel(label string) (pkg, target string, ok bool) {
	l := strings.TrimPrefix(label, "@//")
	l = strings.TrimPrefix(l, "//")
	i := strings.LastIndex(l, ":")
	if i < 0 {
		return "", "", false
	}
	return l[:i], l[i+1:], true
}

// ---------------------------------------------------------------------------
// Output.
// ---------------------------------------------------------------------------

// writeAtomic writes content to path via a same-directory temp file + rename,
// and reports whether the bytes changed. Atomic because tidy-check runs
// `git diff --exit-code` immediately afterwards: a partially-written file
// would fail the gate with a diff that has nothing to do with the change under
// review.
func writeAtomic(path, content string) (bool, error) {
	old, err := os.ReadFile(path)
	if err == nil && string(old) == content {
		return false, nil
	}
	if err != nil && !os.IsNotExist(err) {
		return false, fmt.Errorf("read %s: %w", path, err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false, fmt.Errorf("mkdir %s: %w", filepath.Dir(path), err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".delivery-gen-*")
	if err != nil {
		return false, fmt.Errorf("temp file: %w", err)
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName) // no-op after a successful rename
	if _, err := tmp.WriteString(content); err != nil {
		tmp.Close()
		return false, fmt.Errorf("write %s: %w", tmpName, err)
	}
	if err := tmp.Close(); err != nil {
		return false, fmt.Errorf("close %s: %w", tmpName, err)
	}
	if err := os.Chmod(tmpName, 0o644); err != nil {
		return false, fmt.Errorf("chmod %s: %w", tmpName, err)
	}
	if err := os.Rename(tmpName, path); err != nil {
		return false, fmt.Errorf("rename onto %s: %w", path, err)
	}
	return true, nil
}

// resolveWorkspace returns the repo root: BUILD_WORKSPACE_DIRECTORY under
// `bazel run`, then GITHUB_WORKSPACE, then the cwd. Same precedence as
// tools/copybara/sync.
func resolveWorkspace() string {
	if v := os.Getenv("BUILD_WORKSPACE_DIRECTORY"); v != "" {
		return v
	}
	if v := os.Getenv("GITHUB_WORKSPACE"); v != "" {
		return v
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "."
	}
	return cwd
}

// bazelBinary resolves the bazel to shell out to: --bazel, then GEN_BAZEL, then
// "bazel" on PATH. Pluggable for the same reason the orchestrator's is — tests
// must be able to run discovery hermetically.
func bazelBinary(flagVal string) string {
	if flagVal != "" {
		return flagVal
	}
	if v := os.Getenv("GEN_BAZEL"); v != "" {
		return v
	}
	return "bazel"
}

func main() {
	out := flag.String("out", ".github/workflows/delivery.yaml", "generated workflow path, relative to the workspace root")
	bazelFlag := flag.String("bazel", "", "bazel binary to shell out to (default: $GEN_BAZEL, else 'bazel')")
	// DEFAULT 1. tidy-check runs a bare `bazel run //tools/ci:gen` and diffs
	// the result against the committed file, so the default IS the committed
	// phase — a default of 0 here would regenerate a shadow workflow over the
	// acting one and fail the gate on every unrelated PR. `--phase 0` remains
	// for rendering the shadow shape (the Phase 0 golden pins it).
	phase := flag.Int("phase", 1, "0 = shadow (orchestrate job only); >=1 additionally renders the per-unit fan-out")
	flag.Parse()

	ws := resolveWorkspace()
	paths, err := discover(execBazel(bazelBinary(*bazelFlag), ws))
	if err != nil {
		fmt.Fprintf(os.Stderr, "delivery-gen: %v\n", err)
		os.Exit(1)
	}
	units, err := loadUnits(paths)
	if err != nil {
		fmt.Fprintf(os.Stderr, "delivery-gen: %v\n", err)
		os.Exit(1)
	}

	target := *out
	if !filepath.IsAbs(target) {
		target = filepath.Join(ws, target)
	}
	// The generated file's own basename is what the durable-base resolver
	// queries run history for, so it is rendered INTO the file rather than
	// hardcoded — `--out` and the WORKFLOW_FILE it produces cannot disagree.
	body, err := render(units, *phase, filepath.Base(target))
	if err != nil {
		fmt.Fprintf(os.Stderr, "delivery-gen: %v\n", err)
		os.Exit(1)
	}
	changed, err := writeAtomic(target, body)
	if err != nil {
		fmt.Fprintf(os.Stderr, "delivery-gen: %v\n", err)
		os.Exit(1)
	}
	state := "unchanged"
	if changed {
		state = "REGENERATED"
	}
	fmt.Printf("delivery-gen: %s (%d unit(s), phase %d) — %s\n", target, len(units), *phase, state)
}
