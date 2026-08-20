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

// concurrencyGroupExpr serializes delivery runs WITHOUT letting one release
// evict another (spec §5 "two pushes race", corrected by the Phase-2 live
// rollout).
//
// Push runs share one coalescing lane, which is safe because an evicted push
// run's commit range is re-diffed by the next run's durable base
// (tools/ci/resolve-deploy-base.sh). A RELEASE run has no such successor —
// nothing re-derives "promote what tag X names" — so each tag gets its own
// lane. Same-tag re-publishes still queue behind each other, which is the only
// same-environment race this can have.
//
// A DISPATCH run has no successor either — nothing re-fires the operator's
// request — and it is the break-glass lane, so it must not queue behind (or
// evict) the push lane. Proven live on the first post-Phase-3 dispatch: the
// push lane's head was `waiting` on Environment approvals, the dispatch sat
// `pending` behind it indefinitely, and it evicted the pending push run for
// the next commit on the way in. Each unit+environment pair gets its own
// dispatch lane; re-dispatches of the same pair still serialize. A dispatch
// CAN now overlap a push run touching the same unit — Pulumi's state lock
// serializes the applies, and Cloud Run deploys are last-writer-wins, which
// is the behaviour an operator firing a break-glass deploy wants anyway.
//
// It stays a single top-level group because per-JOB groups are not available
// here: GitHub rejects `concurrency:` on any job with `uses:`, proven twice in
// this repo (#1607 — every dispatch failed instantly, no runner assigned).
const concurrencyGroupExprBase = "delivery-${{ github.event_name == 'release' && github.event.release.tag_name || 'push' }}"

const concurrencyGroupExprDispatch = "delivery-${{ github.event_name == 'release' && github.event.release.tag_name || github.event_name == 'workflow_dispatch' && format('dispatch-{0}-{1}', inputs.unit, inputs.environment) || 'push' }}"

// concurrencyGroupExpr picks the group for the phase being rendered: the
// dispatch arm references inputs.unit/inputs.environment, which only exist
// once the phase renders workflow_dispatch inputs (phase >= 2) — the trigger
// and every expression that reads it must be rendered by the same phase
// (TestPhase1RendersOnlyTheFirstRung pins this).
func concurrencyGroupExpr(phase int) string {
	if phase >= 2 {
		return concurrencyGroupExprDispatch
	}
	return concurrencyGroupExprBase
}

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

// The render modes a declaration may pick for a kind with no built-in shape
// (tools/delivery/defs.bzl validates the same set).
const (
	renderReusable    = "reusable"
	renderTranscribed = "transcribed"
)

// The reusable workhorses. Spec §4.3 keeps them AS-IS and makes the generated
// file a thin caller layer, which is why this is a re-plumbing rather than a
// rewrite of deploy logic — every input below is a `workflow_call` input those
// files already declare.
const cloudRunWorkflow = "./.github/workflows/_deploy-cloud-run.yaml"

// cloudRunCalleeJob is the job id INSIDE that reusable workflow. It is the
// second half of the check-run name GitHub composes for a reusable-workflow
// call ("<caller job id> / <callee job id>"), which is the name the promotion
// soak gate scans run history for — so it is a constant here and derived from
// the real file by the parity test, never guessed at either end.
const cloudRunCalleeJob = "deploy"

// changelogWorkflow renders "what is shipping" onto the run page before the
// (gated) deploy, so an approver reads the actual scope rather than a stale
// digest. Kept as a call, not a transcription: it is already the deduped
// reusable job four workflows share.
const changelogWorkflow = "./.github/workflows/_changelog-summary.yaml"

// soakScript is the promotion interlock: refuse to promote while the unit's
// DEVELOPMENT deploy is red. It runs as an ORDINARY top-level job, never as a
// step inside a reusable deploy workflow — granting that job's own
// `permissions:` block `actions: read` makes GitHub reject the entire calling
// workflow at startup with no jobs instantiated, bisected empirically on
// tabula-deploy.yaml (see its require-dev-soak-api comment).
const soakScript = "./tools/ci/require-dev-soak.sh"

// soakRung is the ladder position the interlock guards: environments[1], the
// first PROMOTION rung. Legacy gates exactly there — nonproduction checks the
// soak, production instead chains behind nonproduction's success — so the
// guard is rendered once per unit, not once per rung.
const soakRung = 1

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

// setupBuildxPin is the buildx setup action tabula's build job uses before its
// (non-Bazel) web image build. Same Dependabot reasoning as the pins above.
const setupBuildxPin = "docker/setup-buildx-action@v4"

// setupHelmPin / pulumiActionsPin / pulumiRunCapturedAction /
// pulumiSummaryAction are the remaining pins the transcribed B2 jobs use.
// Same Dependabot reasoning as the pins above: a bump has to land on the
// constant, not on the generated file.
const (
	setupHelmPin            = "azure/setup-helm@9bc31f4ebc9c6b171d7bfbaa5d006ae7abdb4310 # v5.0.1"
	pulumiActionsPin        = "pulumi/actions@8e5e406f4007fca908480587cb9893c07090f58d # v7.0.0"
	pulumiRunCapturedAction = "./.github/actions/pulumi-run-captured"
	pulumiSummaryAction     = "./.github/actions/pulumi-summary"
)

// gcpAuthAction is the repo's WIF composite. Ambient keyless auth: the
// Environment supplies the provider + service account as variables, so no
// credential is ever a GitHub secret.
const gcpAuthAction = "./.github/actions/gcp-auth"

// orchestrateTimeout / orchestrateGraphTimeout bound the DECIDE job.
//
// The engine runs once per unit. In PATH-ONLY mode that is a `git diff` and a
// regex — the 15 minutes below is already generous. In GRAPH mode it runs
// target-determinator, which the hand-written gate this replaces gives 20
// minutes (tabula-deploy.yaml's gate passes `timeout-minutes: 20` to
// _deploy-gate.yaml, whose default is 5). Timing out is not a silent failure —
// orchestrate goes red and every fan-out job's fail-open arm delivers anyway —
// but that is a whole-repo over-delivery paid on a clock we set, so the
// transcribed 20 applies whenever any declared unit is graph-mode.
const (
	orchestrateTimeout      = 15
	orchestrateGraphTimeout = 20
)

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

// ---------------------------------------------------------------------------
// Shared builds: one job, several consumers (spec §4.3).
// ---------------------------------------------------------------------------

// sharedBuildSpec is ONE transcribed build job several units consume.
//
// WHY A REGISTRY AND NOT A DERIVATION. A per-unit Docker build is derivable
// from two declaration fields (build_context + image_repository_path) because
// every such build is the same five steps. A shared build is not: tabula's
// pushes a Bazel rules_oci image AND a Dockerfile image, with a remote-cache
// flag, a buildx setup and two different digest-capture idioms — eight steps
// whose only correct source is the job they replace. So they are TRANSCRIBED
// here, once, and TestGeneratedSharedBuildJobMatchesLegacy compares the
// rendered steps to the real ones text-for-text. An unregistered shared_build
// name is a hard generator error, exactly like an unregistered companion: a
// derived-but-wrong build job pushes nothing and is discovered at deploy time.
type sharedBuildSpec struct {
	// environment is the GitHub Environment the build binds to. It is ALSO
	// derivable from any consumer's github_environment with {env}=build; the
	// renderer asserts the two agree, so a declaration whose pattern would
	// resolve to a non-existent Environment (a run that fails at startup with
	// no jobs instantiated) fails the regenerate instead.
	environment string
	// outputs are the digest outputs the job declares, in render order. A
	// consumer's image_digest_output is checked against this list: GitHub
	// resolves an unknown `needs.<job>.outputs.<name>` to the EMPTY STRING,
	// so a typo would deploy an empty image ref rather than fail.
	outputs []string
	// timeoutMinutes and env are the job-level facts, transcribed.
	timeoutMinutes int
	env            []string
	// renderSteps writes the `steps:` block at job-body indentation.
	renderSteps func(b *strings.Builder)
}

// sharedBuilds is the registry. One entry today: tabula's.
var sharedBuilds = map[string]sharedBuildSpec{
	"tabula": {
		environment:    "tabula-build",
		outputs:        []string{"image-digest", "web-image-digest"},
		timeoutMinutes: 30,
		env: []string{
			"GCP_PROJECT_ID: ${{ vars.GCP_PROJECT_ID }}",
			"GCP_REGION: ${{ vars.GCP_REGION || '" + defaultRegion + "' }}",
		},
		renderSteps: renderTabulaBuildSteps,
	},
}

// renderTabulaBuildSteps is tabula-deploy.yaml's `build` job steps, transcribed
// verbatim (its lines 184-253). Every comment that explains a NON-OBVIOUS
// choice comes with it, because those comments are the record of two live
// incidents (the NEXT_PUBLIC_ bake-in that broke prod login, and the mutable
// `:latest` read that could hand one run another run's digest).
func renderTabulaBuildSteps(b *strings.Builder) {
	b.WriteString("    steps:\n")
	fmt.Fprintf(b, "      - uses: %s\n", checkoutPin)
	b.WriteString("\n")
	fmt.Fprintf(b, "      - uses: %s\n", setupBazelAction)
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
	b.WriteString("        env:\n")
	b.WriteString("          BUILDBUDDY_API_KEY: ${{ secrets.BUILDBUDDY_API_KEY }}\n")
	b.WriteString("        run: |\n")
	b.WriteString("          set -euo pipefail\n")
	b.WriteString("          IMAGE=\"${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/tabula/api\"\n")
	b.WriteString("          bazel run --config=remotecache-ci --remote_header=x-buildbuddy-api-key=\"$BUILDBUDDY_API_KEY\" \\\n")
	b.WriteString("            //tabula/api:image_push -- \\\n")
	b.WriteString("            --repository \"${IMAGE}\" --tag \"${GITHUB_SHA}\" --tag latest\n")
	b.WriteString("          DIGEST=\"$(gcloud artifacts docker images describe \"${IMAGE}:${GITHUB_SHA}\" \\\n")
	b.WriteString("            --format='value(image_summary.digest)')\"\n")
	b.WriteString("          if [ -z \"$DIGEST\" ]; then\n")
	b.WriteString("            echo \"::error::could not resolve the pushed image digest\"\n")
	b.WriteString("            exit 1\n")
	b.WriteString("          fi\n")
	b.WriteString("          echo \"image-digest=${IMAGE}@${DIGEST}\" >> \"$GITHUB_OUTPUT\"\n")
	b.WriteString("\n")
	b.WriteString("      # ---- tabula/web (Docker, not Bazel) ----\n")
	b.WriteString("      - name: Set up Docker Buildx\n")
	fmt.Fprintf(b, "        uses: %s\n", setupBuildxPin)
	b.WriteString("\n")
	b.WriteString("      - name: Build and push tabula-web image\n")
	b.WriteString("        id: web-image\n")
	b.WriteString("        run: |\n")
	b.WriteString("          set -euo pipefail\n")
	b.WriteString("          # NO --build-arg NEXT_PUBLIC_API_URL here, deliberately: this image\n")
	b.WriteString("          # is built ONCE and promoted unchanged across dev/nonprod/prod\n")
	b.WriteString("          # below, and NEXT_PUBLIC_ vars are inlined into the client bundle\n")
	b.WriteString("          # at `next build` time — a single build can only ever bake in ONE\n")
	b.WriteString("          # environment's API host (this broke prod login: the shared image\n")
	b.WriteString("          # shipped everywhere with development's API URL frozen into it).\n")
	b.WriteString("          # The API URL is now a plain runtime env var (API_URL, injected per\n")
	b.WriteString("          # environment by tabula/infra/web/main.go from Pulumi's `apiUrl`\n")
	b.WriteString("          # config) that tabula/web/lib/runtime-config.ts and proxy.ts\n")
	b.WriteString("          # read fresh on every request instead.\n")
	b.WriteString("          IMAGE=\"${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/tabula/web\"\n")
	b.WriteString("          docker build \\\n")
	b.WriteString("            -f tabula/web/Dockerfile \\\n")
	b.WriteString("            -t \"${IMAGE}:${GITHUB_SHA}\" \\\n")
	b.WriteString("            -t \"${IMAGE}:latest\" \\\n")
	b.WriteString("            .\n")
	b.WriteString("          docker push \"${IMAGE}:${GITHUB_SHA}\"\n")
	b.WriteString("          docker push \"${IMAGE}:latest\"\n")
	b.WriteString("          # Resolve the digest via the immutable per-commit tag, NOT :latest --\n")
	b.WriteString("          # :latest is a shared mutable reference two concurrent builds can\n")
	b.WriteString("          # overwrite between each other's push and inspect, handing one run\n")
	b.WriteString("          # the OTHER run's digest. Matches the API image's push step above,\n")
	b.WriteString("          # which already reads back via ${GITHUB_SHA} for the same reason.\n")
	b.WriteString("          DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' \"${IMAGE}:${GITHUB_SHA}\")\n")
	b.WriteString("          echo \"digest=${DIGEST}\" >> \"$GITHUB_OUTPUT\"\n")
}

// ---------------------------------------------------------------------------
// Render modes for units whose kind has no built-in shape (Wave B2).
// ---------------------------------------------------------------------------
//
// A cloud-run unit's job is derivable: every one of them calls
// _deploy-cloud-run.yaml with a `with:` map the declaration owns. The rest of
// the delivery surface is not — a Helm publish, a rolling GitHub prerelease, a
// Pulumi apply behind a reusable, and a Pulumi apply written inline are four
// different jobs with nothing in common but a checkout. So the generator keeps
// two EXPLICIT registries, keyed by unit name, and the declaration only says
// WHICH mode applies (render = "reusable" | "transcribed").
//
// WHY REGISTRIES AND NOT DECLARATION DATA. Putting the steps in the BUILD file
// would be YAML-in-Starlark: unreachable by actionlint, unreadable in review,
// and a standing invitation to hand-edit delivery logic in six places — the
// drift class this generator exists to end. Putting them here costs
// boilerplate and buys one property: every one of them is compared, text for
// text, against the live legacy job it was transcribed from, on every test run
// (parity_test.go). An unregistered name is a hard render error, exactly like
// an unregistered companion.

// reusableSpec is a unit rendered as a caller of a reusable workflow.
type reusableSpec struct {
	workflow string
	// rungInputs is the `with:` map for one rung. It exists because the
	// ladder's rung is NOT always an input called "environment": the identity
	// appliers take `stack` (the Pulumi stack) plus `gh-environment` (the
	// GitHub Environment whose reviewer and WIF vars gate it), and a caller
	// job cannot use `environment:` at all when it has `uses:`.
	rungInputs func(u unit, env string) map[string]any
}

// identityRungInputs is the tabula / oauth identity appliers' contract.
var identityRungInputs = func(u unit, env string) map[string]any {
	return map[string]any{
		"stack": env,
		// The GitHub Environment is passed as an INPUT, not bound with
		// `environment:`, because GitHub rejects `environment:` on a job that
		// has `uses:`. The callee binds it on its own job, which is where the
		// reviewer gate and the per-env WIF vars live.
		"gh-environment": strings.ReplaceAll(u.GitHubEnvironment, "{env}", env),
	}
}

var reusableWorkflows = map[string]reusableSpec{
	"tabula-identity": {
		workflow:   "./.github/workflows/_tabula-identity-apply.yaml",
		rungInputs: identityRungInputs,
	},
	"oauth-user-inspector-identity": {
		workflow:   "./.github/workflows/_oauth-identity-apply.yaml",
		rungInputs: identityRungInputs,
	},
}

// transcribedSpec is a unit rendered as a plain job whose steps are the legacy
// job's, verbatim.
type transcribedSpec struct {
	timeoutMinutes int
	// permissions are the job's OWN grant. Job-level permissions REPLACE the
	// workflow-level block, and this file's workflow-level grant is
	// `contents: read` + `actions: read` — narrower than several of these jobs
	// need (a release upload needs contents: write, a GHCR push needs
	// packages: write). Getting this wrong is a 403 in the middle of a
	// publish, so each is transcribed from the legacy workflow it came from.
	permissions []string
	// environment is the GitHub Environment to bind, "" for none. Unlike a
	// `uses:` caller, a plain job MAY bind one.
	environment []string
	env         []string
	renderSteps func(b *strings.Builder, u unit, env string)
}

var transcribedJobs = map[string]transcribedSpec{
	"tabula-dev-latest": {
		timeoutMinutes: 45,
		// `contents: write` is what `gh release upload` needs; the legacy
		// workflow grants it at the workflow level, which this file cannot do
		// without handing it to orchestrate and every other unit.
		permissions: []string{"contents: write"},
		renderSteps: renderTabulaDevLatestSteps,
	},
	"charts": {
		timeoutMinutes: 45,
		permissions:    []string{"contents: read", "packages: write"},
		renderSteps:    renderChartsPublishSteps,
	},
	"tabula-build-stack": {
		timeoutMinutes: 60,
		permissions:    []string{"contents: read", "id-token: write"},
		env: []string{
			"GOWORK: off",
			// Authenticate Pulumi's github:// plugin downloads so the job does
			// not hit the 60/hr/IP unauthenticated GitHub API rate limit CI
			// runners routinely exhaust (intermittent 403s); GITHUB_TOKEN
			// raises this to 5000/hr. Same class of fix as #756.
			"GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}",
		},
		renderSteps: renderTabulaBuildStackSteps,
	},
	"copybara-sync-auth": {
		timeoutMinutes: 45,
		// No id-token: this job authenticates to GitHub with a minted App
		// token, not to GCP with WIF.
		permissions: []string{"contents: read"},
		renderSteps: renderCopybaraSyncAuthSteps,
	},
}

// renderTabulaDevLatestSteps calls the extracted publisher.
//
// Its build/stamp/publish body is NOT inlined here: it lives in
// tabula/extension/publish-dev-latest.sh, wrapped by
// //tabula/extension:publish-dev-latest. This was the last unit whose `run`
// target was not runnable — the declaration could only name :chrome_zip, a
// genrule — so "CI and break-glass execute the same target" (spec §4.1) was
// true of every unit but this one. Now it is true of all of them, and the
// script is the single copy: a change to the publish cannot drift between a
// workflow and a runbook.
func renderTabulaDevLatestSteps(b *strings.Builder, u unit, env string) {
	b.WriteString("    steps:\n")
	fmt.Fprintf(b, "      - uses: %s\n", checkoutPin)
	b.WriteString("\n")
	b.WriteString("      - name: Set up Bazel\n")
	fmt.Fprintf(b, "        uses: %s\n", setupBazelAction)
	b.WriteString("\n")
	b.WriteString("      - name: Build, stamp and publish the rolling dev-latest bundle\n")
	b.WriteString("        env:\n")
	b.WriteString("          # Cache-only (see --config=remotecache-ci in tools/remote.bazelrc):\n")
	b.WriteString("          # reuse the chrome_zip build CI already cached. Absent (a laptop,\n")
	b.WriteString("          # a fork) the script builds locally instead of failing on auth.\n")
	b.WriteString("          BUILDBUDDY_API_KEY: ${{ secrets.BUILDBUDDY_API_KEY }}\n")
	b.WriteString("          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}\n")
	b.WriteString("        run: bash tabula/extension/publish-dev-latest.sh\n")
}

// renderChartsPublishSteps is charts-publish.yml's `publish` job, transcribed.
//
// Its 45-line packaging script is NOT inlined here: it lives in
// tools/charts/publish.sh, which BOTH this job and the legacy one now run.
// That extraction is what makes the unit declarable at all — delivery(run=)
// must name a target that exists, //tools/conformance:check proves it
// resolves, and before this there was no Bazel target of any kind for the
// charts (`grep -rn "deploy/chart" --include=BUILD --include=*.bzl` found
// none). One script, one sh_binary, one break-glass path: the spec's "CI and
// break-glass execute the same target" (§4.1), which an inline `run:` block
// can never satisfy.
func renderChartsPublishSteps(b *strings.Builder, u unit, env string) {
	b.WriteString("    steps:\n")
	fmt.Fprintf(b, "      - uses: %s\n", checkoutPin)
	b.WriteString("        with:\n")
	b.WriteString("          # The per-chart scoping inside publish.sh diffs against the\n")
	b.WriteString("          # pre-push tip; the default depth-1 clone has no such commit and\n")
	b.WriteString("          # the script would fail open to republishing every chart.\n")
	b.WriteString("          fetch-depth: 0\n")
	b.WriteString("      - name: Install Helm\n")
	fmt.Fprintf(b, "        uses: %s\n", setupHelmPin)
	b.WriteString("      - name: Log in to GHCR\n")
	b.WriteString("        run: echo \"${{ secrets.GITHUB_TOKEN }}\" | helm registry login ghcr.io -u \"${{ github.actor }}\" --password-stdin\n")
	b.WriteString("      - name: Package and push charts\n")
	b.WriteString("        env:\n")
	b.WriteString("          # Per-chart scoping input. This is github.event.before, not the\n")
	b.WriteString("          # orchestrator's durable base: the script fails OPEN to publishing\n")
	b.WriteString("          # every chart when it cannot resolve it, and re-pushing an\n")
	b.WriteString("          # unchanged chart version is a harmless overwrite. Sharpening this\n")
	b.WriteString("          # to the durable base is a detection change, not a trigger change,\n")
	b.WriteString("          # and belongs with the Phase-3 preflight work.\n")
	b.WriteString("          BEFORE_REV: ${{ github.event.before }}\n")
	b.WriteString("          FORCED_PUSH: ${{ github.event.forced }}\n")
	b.WriteString("        run: bash tools/charts/publish.sh\n")
	b.WriteString("      - name: Visibility note\n")
	b.WriteString("        run: |\n")
	b.WriteString("          echo \"New GHCR packages start private. Make each chart public once (UI or):\"\n")
	b.WriteString("          echo \"  gh api -X PATCH /orgs/vitruviansoftware/packages/container/charts%2F<name> -f visibility=public\"\n")
}

// renderTabulaBuildStackSteps is tabula-build-stack.yaml's `deploy` job,
// transcribed verbatim (its lines 82-112).
func renderTabulaBuildStackSteps(b *strings.Builder, u unit, env string) {
	b.WriteString("    steps:\n")
	fmt.Fprintf(b, "      - uses: %s\n", checkoutPin)
	b.WriteString("\n")
	b.WriteString("      - name: Authenticate to GCP (WIF, keyless)\n")
	fmt.Fprintf(b, "        uses: %s\n", gcpAuthAction)
	b.WriteString("        with:\n")
	b.WriteString("          workload-identity-provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}\n")
	b.WriteString("          service-account: ${{ vars.GCP_SERVICE_ACCOUNT }}\n")
	b.WriteString("\n")
	b.WriteString("      - name: Install Pulumi\n")
	fmt.Fprintf(b, "        uses: %s\n", pulumiActionsPin)
	b.WriteString("\n")
	b.WriteString("      - name: Pulumi up (tabula-build / production)\n")
	b.WriteString("        id: pulumi\n")
	fmt.Fprintf(b, "        uses: %s\n", pulumiRunCapturedAction)
	b.WriteString("        with:\n")
	b.WriteString("          command: up\n")
	b.WriteString("          stack: production\n")
	b.WriteString("          working-directory: tabula/infra/build\n")
	b.WriteString("          pulumi-access-token: ${{ secrets.PULUMI_ACCESS_TOKEN }}\n")
	b.WriteString("\n")
	b.WriteString("      # Render the pulumi output digest onto the run's step-summary page via the\n")
	b.WriteString("      # shared composite (.github/actions/pulumi-summary). Runs even when the\n")
	b.WriteString("      # deploy fails so the failure — and what it touched — is surfaced.\n")
	b.WriteString("      - name: Pulumi digest → step summary\n")
	b.WriteString("        if: always()\n")
	fmt.Fprintf(b, "        uses: %s\n", pulumiSummaryAction)
	b.WriteString("        with:\n")
	b.WriteString("          label: tabula-build\n")
	b.WriteString("          out-file: ${{ runner.temp }}/pulumi-out.txt\n")
	b.WriteString("          exit-code: ${{ steps.pulumi.outputs.exit_code }}\n")
}

// renderCopybaraSyncAuthSteps is copybara-sync-auth-apply.yaml's `apply` job,
// transcribed verbatim (its lines 66-110).
func renderCopybaraSyncAuthSteps(b *strings.Builder, u unit, env string) {
	b.WriteString("    steps:\n")
	fmt.Fprintf(b, "      - uses: %s\n", checkoutPin)
	b.WriteString("\n")
	b.WriteString("      - name: Set up Bazel\n")
	fmt.Fprintf(b, "        uses: %s\n", setupBazelAction)
	b.WriteString("\n")
	b.WriteString("      # Org-scoped so the Pulumi GitHub provider can manage deploy keys +\n")
	b.WriteString("      # Actions secrets on the standalone component repos, not only the\n")
	b.WriteString("      # monorepo (this is the key difference from the repo_config apply).\n")
	b.WriteString("      - name: Mint a GitHub App token for the Pulumi GitHub provider\n")
	b.WriteString("        id: app-token\n")
	b.WriteString("        uses: ./.github/actions/mint-pulumi-app-token\n")
	b.WriteString("        with:\n")
	b.WriteString("          client-id: ${{ vars.PULUMI_APP_CLIENT_ID }} # var wins so //tools/pulumi:create-app can rebootstrap; empty falls back to the composite's default id\n")
	b.WriteString("          private-key: ${{ secrets.APP_PRIVATE_KEY }}\n")
	b.WriteString("          owner: ${{ github.repository_owner }}\n")
	b.WriteString("\n")
	b.WriteString("      - name: Pulumi up (vitruvian-core-infra sync-auth)\n")
	b.WriteString("        id: pulumi\n")
	b.WriteString("        env:\n")
	b.WriteString("          GITHUB_TOKEN: ${{ steps.app-token.outputs.token }}\n")
	b.WriteString("          GITHUB_OWNER: ${{ github.repository_owner }}\n")
	b.WriteString("          PULUMI_ACCESS_TOKEN: ${{ secrets.PULUMI_ACCESS_TOKEN }}\n")
	b.WriteString("          # The shared sync App creds, injected from pipeline secrets (never\n")
	b.WriteString("          # committed). The program reads these env vars in CI and falls back\n")
	b.WriteString("          # to the gitignored local Pulumi stack config for local dev.\n")
	b.WriteString("          SYNC_APP_ID: ${{ secrets.SYNC_APP_ID }}\n")
	b.WriteString("          SYNC_APP_PRIVATE_KEY: ${{ secrets.SYNC_APP_PRIVATE_KEY }}\n")
	b.WriteString("        run: |\n")
	b.WriteString("          # +e to capture pulumi's real exit code for the digest below.\n")
	b.WriteString("          set +e -u -o pipefail\n")
	b.WriteString("          bazel run //infrastructure/pulumi:up -- --stack dev --yes \\\n")
	b.WriteString("              2>&1 | tee /tmp/apply-raw.txt\n")
	b.WriteString("          ec=\"${PIPESTATUS[0]}\"\n")
	b.WriteString("          echo \"exit_code=${ec}\" >> \"${GITHUB_OUTPUT}\"\n")
	b.WriteString("          exit \"${ec}\"\n")
	b.WriteString("\n")
	b.WriteString("      # Digest of the apply on the Actions run summary (push → summary only).\n")
	b.WriteString("      - name: Pulumi digest → step summary\n")
	b.WriteString("        if: ${{ always() }}\n")
	fmt.Fprintf(b, "        uses: %s\n", pulumiSummaryAction)
	b.WriteString("        with:\n")
	b.WriteString("          label: sync-auth\n")
	b.WriteString("          out-file: /tmp/apply-raw.txt\n")
	b.WriteString("          exit-code: ${{ steps.pulumi.outputs.exit_code }}\n")
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

	// SharedBuild names a build job SEVERAL units consume (tabula's single
	// `build` job produces both the API and the web image). The job's steps
	// are transcribed, not derived, so sharedBuilds below is an explicit
	// registry and an unregistered name is a hard error.
	// ImageDigestOutput says WHICH of that job's outputs this unit deploys.
	SharedBuild       string `json:"shared_build"`
	ImageDigestOutput string `json:"image_digest_output"`

	Environments      []string `json:"environments"`
	GitHubEnvironment string   `json:"github_environment"`
	Promotion         string   `json:"promotion"`
	Soak              bool     `json:"soak"`

	// Render selects the job shape for a unit whose kind has none built in:
	// "reusable" (a registered reusable workflow) or "transcribed" (the legacy
	// job's steps, verbatim). "" means the kind's default — which for
	// everything but cloud-run is "render nothing", so a pulumi unit that is
	// only ever another unit's companion stays exactly that.
	Render string `json:"render"`
	// LegacyWorkflow/LegacyJob are the parity baseline: the job this unit's
	// rendering was taken from. Not runtime inputs; they go with Phase 3.
	LegacyWorkflow string `json:"legacy_workflow"`
	LegacyJob      string `json:"legacy_job"`
	// GateVar is an extra repo-variable opt-in for the PUSH arm (see
	// gateVarExpr): the legacy "auto-apply is off by default" switch.
	GateVar      string   `json:"gate_var"`
	Companions   []string `json:"companions"`
	ExtraPaths   []string `json:"extra_paths"`
	ExcludePaths []string `json:"exclude_paths"`
	GraphTargets []string `json:"graph_targets"`
	Preflight    string   `json:"preflight"`
	Package      string   `json:"package"`

	// WorkflowInputs is the `with:` map handed to the unit's reusable
	// workflow. `any` rather than map[string]string because the values are
	// typed workflow_call inputs — `workload-migrated: false` must render as
	// a YAML boolean, not the string "false", or GitHub coerces it back to
	// TRUE (a non-empty string is truthy) and the deploy skips its own
	// blue-green. delivery() rejects non-scalars, and yamlScalar rejects them
	// again here.
	WorkflowInputs map[string]any `json:"workflow_inputs"`

	// ChangelogInputs is the `with:` map for _changelog-summary.yaml. Empty
	// means the unit renders no changelog job.
	ChangelogInputs map[string]any `json:"changelog_inputs"`
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
		// Graph mode vs path-only mode is the single biggest determinant of a
		// verdict's sharpness, and (like the regexes above) it lives in the
		// declaration — invisible from here unless it is rendered.
		if len(u.GraphTargets) > 0 {
			fmt.Fprintf(b, "#       graph:  %s\n", strings.Join(u.GraphTargets, " "))
		}
		if u.SharedBuild != "" {
			fmt.Fprintf(b, "#       build:  shared %q → %s\n", u.SharedBuild, u.ImageDigestOutput)
		}
		if u.Soak {
			fmt.Fprintf(b, "#       soak:   promotion blocked while %s is red\n", u.Environments[0])
		}
		// How the unit's job is produced, and from what. Both are declaration
		// facts a reader of the generated file cannot otherwise see, and the
		// legacy pair is what the parity test uses as its baseline — so a
		// declaration that stopped naming one shows up as a diff here.
		if u.Render != "" {
			if u.LegacyWorkflow != "" {
				fmt.Fprintf(b, "#       render: %s from %s job %q\n", u.Render, u.LegacyWorkflow, u.LegacyJob)
			} else {
				fmt.Fprintf(b, "#       render: %s\n", u.Render)
			}
		}
		if u.GateVar != "" {
			fmt.Fprintf(b, "#       gate:   push applies require vars.%s == 'true'\n", u.GateVar)
		}
		if u.Preflight != "" {
			fmt.Fprintf(b, "#       skip:   preflight=%s (deploy skipped when live already serves the desired revision)\n", u.Preflight)
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
	opts := renderOpts{
		phase:        phase,
		workflowFile: workflowFile,
		// Phase 2 is where a HUMAN can drive one unit+env from the run page:
		// the per-unit dispatch inputs exist, so every fan-out job can carry a
		// dispatch arm. Rendering those arms at an earlier phase would
		// reference inputs the `on:` block does not declare — actionlint red,
		// and at runtime an expression that silently reads "".
		dispatch: phase >= 2,
		// ...and the release trigger only when something actually promotes on
		// it. A `release:` trigger with no release-gated job instantiates this
		// whole workflow on EVERY published release in the repo for nothing.
		release: phase >= 2 && len(promotionUnits(units)) > 0,
	}

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
	// `workflow_dispatch` inputs arrive with Phase 2 (renderDispatchTrigger):
	// they are what lets the legacy per-app workflows drop their own single-env
	// dispatch escape hatches. The break-glass `bazel run <unit run target>` in
	// the runbook stays the Actions-independent path either way.
	renderDispatchTrigger(&b, units, opts)
	renderReleaseTrigger(&b, opts)
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
	b.WriteString("# KNOWN CONSEQUENCE (#1351), MITIGATED FOR PUSHES: a coalescing group\n")
	b.WriteString("# means GitHub EVICTS an already-PENDING run when a newer one queues, and\n")
	b.WriteString("# `github.event.before` is fixed at the EVICTED run's push — a range no\n")
	b.WriteString("# successor re-diffs, i.e. a silent permanent skip. The orchestrate job\n")
	b.WriteString("# therefore resolves a DURABLE base from this workflow's last successful\n")
	b.WriteString("# push run (tools/ci/resolve-deploy-base.sh) and only falls back to\n")
	b.WriteString("# github.event.before when that cannot be determined: the NEXT push run\n")
	b.WriteString("# re-diffs the evicted one's range, so eviction costs latency, not a\n")
	b.WriteString("# delivery. Observed live and working on the Phase-2 merge burst.\n")
	b.WriteString("#\n")
	b.WriteString("# WHY RELEASE RUNS ARE KEYED SEPARATELY, PER TAG: that recovery does not\n")
	b.WriteString("# exist for a release. A release run delivers what its TAG names, and no\n")
	b.WriteString("# later run ever re-derives it — so an evicted release run is a promotion\n")
	b.WriteString("# that silently never happens, recoverable only by a human noticing and\n")
	b.WriteString("# dispatching it. That is not hypothetical: two releases published in the\n")
	b.WriteString("# same minute during the Phase-2 rollout evicted each other (runs\n")
	b.WriteString("# 32345258539 / 32344982262 — harmless only because both tags were infra\n")
	b.WriteString("# ones with no rung of their own; a tabula-api-v + tabula-web-v pair would\n")
	b.WriteString("# have dropped one service's promotion). Keying release runs on the tag\n")
	b.WriteString("# gives every tag its own lane: two tags never evict each other, while two\n")
	b.WriteString("# runs of the SAME tag (a re-publish) still serialize, which is the case\n")
	b.WriteString("# that could actually race one environment.\n")
	b.WriteString("concurrency:\n")
	fmt.Fprintf(&b, "  group: %s\n", concurrencyGroupExpr(phase))
	b.WriteString("  cancel-in-progress: false\n")
	b.WriteString("\n")
	b.WriteString("jobs:\n")
	renderOrchestrateJob(&b, units, workflowFile)

	// ---- Phase 1+ boundary -------------------------------------------------
	if phase >= 1 {
		if err := renderFanOut(&b, units, opts); err != nil {
			return "", err
		}
	}

	return b.String(), nil
}

// renderOpts carries what every job renderer needs to know about the FILE it is
// rendering into: which triggers exist. A job may only reference a
// `workflow_dispatch` input the `on:` block declares, and may only carry a
// release arm when a release can actually start this workflow — so these two
// booleans and the `on:` block are derived from the same place, once.
type renderOpts struct {
	phase        int
	workflowFile string
	dispatch     bool
	release      bool
}

// promotionUnits are the cloud-run units with a release-gated ladder, sorted
// (units already are). Used for the release trigger, the dispatch inventory,
// and the shared build's release arm.
func promotionUnits(units []unit) []unit {
	var out []unit
	for _, u := range units {
		if u.Kind == kindCloudRun && u.Promotion != "" && len(u.Environments) > 1 {
			out = append(out, u)
		}
	}
	return out
}

// dispatchUnits are the units a human can actually name in the dispatch form.
//
// DELIBERATELY NOT "every declared unit": a companion (zitadel-apps) is applied
// from its CONSUMER's ladder and carries no job of its own, so offering it here
// would render a form option whose every dispatch silently matches no job —
// a control that looks like it works and does nothing, which is the exact shape
// this program exists to delete. Re-applying a companion is a dispatch of the
// unit it expands for.
func dispatchUnits(units []unit) []unit {
	var out []unit
	for _, u := range units {
		if u.Kind == kindCloudRun || u.Render != "" {
			out = append(out, u)
		}
	}
	return out
}

// dispatchEnvironments is the union of the dispatchable units' ladders, in
// LADDER order (development, nonproduction, production) rather than
// alphabetical — the form reads as the promotion sequence it drives. Units are
// sorted before this runs, so the result is deterministic.
func dispatchEnvironments(units []unit) []string {
	var out []string
	for _, u := range dispatchUnits(units) {
		for _, env := range u.Environments {
			if !contains(out, env) {
				out = append(out, env)
			}
		}
	}
	// The app ladder first, then everything else in first-appearance order.
	// Wave B2 added rung names that are not environments in the app sense
	// ("publish", "shared", the sync-auth stack) and they sort ahead of
	// "development" alphabetically — which would make the form's DEFAULT a
	// publish rung. A stable sort on an explicit rank keeps the form reading
	// as the promotion sequence it drives, and keeps the output deterministic.
	rank := func(env string) int {
		switch env {
		case "development":
			return 0
		case "nonproduction":
			return 1
		case "production":
			return 2
		}
		return 3
	}
	sort.SliceStable(out, func(i, j int) bool { return rank(out[i]) < rank(out[j]) })
	return out
}

// renderDispatchTrigger emits `workflow_dispatch:` — bare at phase <2, and with
// the unit/environment/allow-unsoaked inputs from Phase 2 on.
//
// These three inputs are what makes Phase 3's deletion of the legacy workflows
// possible: their `workflow_dispatch` blocks are the documented break-glass
// "redeploy ONE environment" path (docs/break-glass-deploy-runbook.md), and
// nothing may be deleted until an equivalent exists here.
func renderDispatchTrigger(b *strings.Builder, units []unit, opts renderOpts) {
	if !opts.dispatch {
		b.WriteString("  workflow_dispatch: {}\n")
		return
	}
	b.WriteString("  # Manual, single unit + single environment (the escape hatch that\n")
	b.WriteString("  # replaces every legacy per-app workflow's own dispatch block). Every\n")
	b.WriteString("  # fan-out job below carries a dispatch arm naming ITS unit and ITS rung,\n")
	b.WriteString("  # so a dispatch delivers exactly one thing — never the whole ladder.\n")
	b.WriteString("  workflow_dispatch:\n")
	b.WriteString("    inputs:\n")
	b.WriteString("      unit:\n")
	b.WriteString("        description: Delivery unit to deliver (a companion is applied by dispatching the unit it expands for)\n")
	b.WriteString("        type: choice\n")
	b.WriteString("        required: true\n")
	b.WriteString("        options:\n")
	for _, u := range dispatchUnits(units) {
		fmt.Fprintf(b, "          - %s\n", u.Name)
	}
	b.WriteString("      environment:\n")
	b.WriteString("        description: Target environment (single-env break-glass redeploy)\n")
	b.WriteString("        type: choice\n")
	b.WriteString("        required: true\n")
	envs := dispatchEnvironments(units)
	if len(envs) > 0 {
		fmt.Fprintf(b, "        default: %s\n", envs[0])
	}
	b.WriteString("        options:\n")
	for _, env := range envs {
		fmt.Fprintf(b, "          - %s\n", env)
	}
	b.WriteString("      allow-unsoaked:\n")
	b.WriteString("        description: Promote even if the unit's development deploy is RED (logged loudly; tools/ci/require-dev-soak.sh)\n")
	b.WriteString("        type: boolean\n")
	b.WriteString("        required: false\n")
	b.WriteString("        default: false\n")
}

// renderReleaseTrigger emits the promotion trigger.
//
// GitHub offers no per-tag filter on `on: release`, so this fires on EVERY
// published release in the repo (foundation-*, buzz, every app). That is why
// every release-gated job below carries its own `startsWith(tag_name, ...)`
// guard: without it, one component's release would rebuild and re-promote
// another's — the exact waste the legacy build jobs' tag guards document.
func renderReleaseTrigger(b *strings.Builder, opts renderOpts) {
	if !opts.release {
		return
	}
	b.WriteString("  # Promotion trigger. release-please publishes a GitHub Release when a\n")
	b.WriteString("  # component's release PR merges; that fires here and drives the\n")
	b.WriteString("  # nonproduction -> production ladder for the unit whose tag prefix\n")
	b.WriteString("  # matches. Filtered PER JOB (see each rung's `if:`), never here: the\n")
	b.WriteString("  # event itself carries no tag filter.\n")
	b.WriteString("  release:\n")
	b.WriteString("    types: [published]\n")
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
	if phase >= 2 {
		b.WriteString("# PHASE 2 — THE WHOLE LADDER ACTS (spec §6). This workflow is now the\n")
		b.WriteString("# delivery path for every unit below, on all three of its triggers:\n")
		b.WriteString("#   - push to main      -> the FIRST environment of every AFFECTED unit\n")
		b.WriteString("#                          (companions applied first, expand-before-serve);\n")
		b.WriteString("#   - release published -> nonproduction then production for the unit whose\n")
		b.WriteString("#                          tag prefix matches, each rung holding its legacy\n")
		b.WriteString("#                          interlocks (dev-soak, prior-rung success, the\n")
		b.WriteString("#                          production Environment's required reviewer);\n")
		b.WriteString("#   - workflow_dispatch -> exactly ONE unit into ONE environment.\n")
		b.WriteString("#\n")
		b.WriteString("# The legacy per-app workflows keep ONLY their own workflow_dispatch, as\n")
		b.WriteString("# dispatch-only shells pending their Phase-3 deletion; their `push:` and\n")
		b.WriteString("# `release:` triggers are gone, so nothing here races them.\n")
		b.WriteString("#\n")
		b.WriteString("# ROLLBACK (spec §6.1): flip the DELIVERY_ORCHESTRATOR_ENABLED repo\n")
		b.WriteString("# variable to false and every job below no-ops without a commit. Level 0\n")
		b.WriteString("# is the break-glass `bazel run` target, unchanged, per the runbook.\n")
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
	b.WriteString("    #\n")
	b.WriteString("    # PUSH-ONLY, and that is not a narrowing of the gate — it is what this\n")
	b.WriteString("    # job decides. Its verdict is \"which units did this DIFF affect\", which\n")
	b.WriteString("    # only a push has: a release event promotes an already-built digest by\n")
	b.WriteString("    # tag, and a dispatch names its unit outright. Running it anyway would\n")
	b.WriteString("    # pay a Bazel setup + a target-determinator sweep on EVERY published\n")
	b.WriteString("    # release in the repo (this workflow has no per-tag trigger filter) for\n")
	b.WriteString("    # an answer nothing reads. Every fan-out job below stays reachable with\n")
	b.WriteString("    # this skipped: their conditions use always()/!cancelled() and their\n")
	b.WriteString("    # release/dispatch arms, exactly as the legacy jobs did with their own\n")
	b.WriteString("    # push-only `gate` job skipped.\n")
	fmt.Fprintf(b, "    if: %s && github.event_name == 'push'\n", killSwitchExpr)
	b.WriteString("    runs-on: ubuntu-latest\n")
	// Graph-mode units run target-determinator inside this job; the gate that
	// used to do it for tabula was given 20 minutes, so inherit that when any
	// unit is graph-mode rather than letting the DECIDE stage time out into a
	// whole-repo fail-open.
	timeout := orchestrateTimeout
	for _, u := range units {
		if len(u.GraphTargets) > 0 || u.Build != "" {
			timeout = orchestrateGraphTimeout
			break
		}
	}
	fmt.Fprintf(b, "    timeout-minutes: %d\n", timeout)
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

// renderFanOut emits, per cloud-run unit, its ladder: the build that produces
// the image, the companions that expand before it serves, and one deploy job
// per rung the current phase renders.
//
// Phase 1 renders environments[0] only (the push lane). Phase 2 renders the
// whole ladder, with the later rungs keyed on the release event and the
// interlocks — dev-soak, prior-rung success, the companion-per-rung chain —
// transcribed from the legacy jobs they replace, because the acceptance test
// is "identical delivery behaviour to today" measured on a real release, not
// "a defensible new design".
func renderFanOut(b *strings.Builder, units []unit, opts renderOpts) error {
	byName := make(map[string]unit, len(units))
	for _, u := range units {
		byName[u.Name] = u
	}
	// Deduped across units: two consumers may share one companion or one
	// build, and two jobs with the same id is a YAML mapping whose second
	// entry silently wins.
	rendered := make(map[string]bool)
	consumers := sharedBuildConsumers(units)

	for _, u := range units {
		if u.Kind != kindCloudRun {
			// A unit with no render mode deliberately renders NOTHING of its
			// own: zitadel-apps is a declared unit that only ever appears as
			// another unit's companion. Wave B2's publishes and applies opt in
			// with render = "reusable" | "transcribed".
			if u.Render == "" || opts.phase < 2 {
				continue
			}
			if err := renderDeclaredModeUnit(b, u, opts); err != nil {
				return err
			}
			continue
		}
		if err := checkCloudRunInputs(u); err != nil {
			return err
		}
		// environments[0] IS the push rung, by the declaration's own contract
		// ("ordered ladder"); later rungs promote on a release event.
		rungs := u.Environments[:1]
		if opts.phase >= 2 {
			if len(u.Environments) > 1 && u.Promotion == "" {
				return fmt.Errorf("unit %q declares %d environments and no promotion — every rung would then deliver on a PUSH, i.e. a merge to main would walk into %q. Declare promotion = \"release:<tag-prefix>\", or drop the extra environments", u.Name, len(u.Environments), u.Environments[len(u.Environments)-1])
			}
			rungs = u.Environments
		}

		fmt.Fprintf(b, "\n  # ======== unit: %s → %s ========\n", u.Name, strings.Join(rungs, " → "))
		fmt.Fprintf(b, "  # Declared in %s/BUILD; break-glass target: %s\n", u.Package, u.Run)
		fmt.Fprintf(b, "  # GitHub Environments: %s (approvals + keyless-WIF vars live there)\n",
			strings.Join(githubEnvironments(u, rungs), ", "))
		if u.Promotion != "" && opts.phase >= 2 {
			fmt.Fprintf(b, "  # Promotion to %s: on a published release tagged %s* (release-please).\n",
				strings.Join(u.Environments[1:], "/"), strings.TrimPrefix(u.Promotion, "release:"))
		} else if u.Promotion != "" {
			fmt.Fprintf(b, "  # Promotion to %s: still the legacy ladder, on %s* (Phase 2 migrates it).\n",
				strings.Join(u.Environments[1:], "/"), strings.TrimPrefix(u.Promotion, "release:"))
		}

		if err := renderChangelogJob(b, u, opts); err != nil {
			return err
		}

		buildJob, digestOutput, err := renderUnitBuild(b, u, consumers, rendered, opts)
		if err != nil {
			return err
		}

		soakJob := ""
		if u.Soak && opts.phase >= 2 {
			// Checked HERE, not where the job is rendered: with a one-rung
			// ladder that render site is never reached, so the declaration
			// would pass through silently having asked for a gate that does
			// not exist.
			if len(u.Environments) <= soakRung {
				return fmt.Errorf("unit %q declares soak but only %d environment(s) — there is no promotion rung to hold back (delivery() enforces this too)", u.Name, len(u.Environments))
			}
			soakJob = u.Name + "-require-dev-soak"
		}

		for i, env := range rungs {
			// The interlock is rendered immediately before the rung it
			// guards, so the two read as one thing in the file a human
			// reviews — and so a rung that lost its gate is a visibly
			// missing job rather than a quietly missing clause.
			if i == soakRung && soakJob != "" {
				if err := renderSoakJob(b, soakJob, u, opts); err != nil {
					return err
				}
			}
			companionJobs, err := renderRungCompanions(b, u, byName, rendered, i, env, opts)
			if err != nil {
				return err
			}
			if err := renderDeployJob(b, u, i, env, buildJob, digestOutput, soakJob, companionJobs, opts); err != nil {
				return err
			}
		}
	}
	return nil
}

// githubEnvironments resolves the unit's Environment names for the rungs being
// rendered — the human-readable half of "where do the approvals live".
func githubEnvironments(u unit, rungs []string) []string {
	out := make([]string, 0, len(rungs))
	for _, env := range rungs {
		out = append(out, strings.ReplaceAll(u.GitHubEnvironment, "{env}", env))
	}
	return out
}

// sharedBuildConsumers maps a shared_build name to the units that consume it,
// in the units' (sorted) order — so the shared job's condition ORs its
// consumers deterministically.
func sharedBuildConsumers(units []unit) map[string][]unit {
	out := map[string][]unit{}
	for _, u := range units {
		if u.SharedBuild != "" {
			out[u.SharedBuild] = append(out[u.SharedBuild], u)
		}
	}
	return out
}

// renderUnitBuild renders (once) the job that produces this unit's image and
// returns the job id plus the OUTPUT NAME this unit's deploys read from it.
func renderUnitBuild(b *strings.Builder, u unit, consumers map[string][]unit, rendered map[string]bool, opts renderOpts) (string, string, error) {
	if u.SharedBuild == "" {
		job := u.Name + "-build"
		if rendered[job] {
			return job, "image-digest", nil
		}
		rendered[job] = true
		return job, "image-digest", renderBuildJob(b, job, u, opts)
	}

	spec, ok := sharedBuilds[u.SharedBuild]
	if !ok {
		return "", "", fmt.Errorf("unit %q declares shared_build %q, which //tools/delivery/gen has no registered build job for — register it in sharedBuilds (a derived-but-unverified build job pushes nothing, and is discovered at deploy time)", u.Name, u.SharedBuild)
	}
	if !contains(spec.outputs, u.ImageDigestOutput) {
		return "", "", fmt.Errorf("unit %q reads image_digest_output %q from the %q build, which declares %v — GitHub resolves an unknown `needs.<job>.outputs.<name>` to the EMPTY STRING, so this would deploy an empty image ref instead of failing", u.Name, u.ImageDigestOutput, u.SharedBuild, spec.outputs)
	}
	// The build binds a GitHub Environment. Deriving it from the consumer's
	// own pattern keeps ONE naming rule; comparing that against the
	// transcribed value catches a pattern that would resolve to an
	// Environment which does not exist — a run that fails at startup with no
	// jobs instantiated.
	derived := strings.ReplaceAll(u.GitHubEnvironment, "{env}", buildRung)
	if derived != spec.environment {
		return "", "", fmt.Errorf("unit %q's github_environment %q resolves the build rung to %q, but the %q build job binds %q — one of them is wrong, and a non-existent Environment fails the whole run at startup", u.Name, u.GitHubEnvironment, derived, u.SharedBuild, spec.environment)
	}

	job := u.SharedBuild + "-build"
	if rendered[job] {
		return job, u.ImageDigestOutput, nil
	}
	rendered[job] = true
	renderSharedBuildJob(b, job, u.SharedBuild, spec, consumers[u.SharedBuild], opts)
	return job, u.ImageDigestOutput, nil
}

// renderSharedBuildJob emits ONE build job for several consuming units.
//
// Its condition is the UNION of its consumers': the image must exist whenever
// ANY of them is delivering, on any trigger. Union, not intersection, is the
// fail-safe direction — an extra image push touches no live service, while a
// missing one fails every deploy that needs it.
func renderSharedBuildJob(b *strings.Builder, job, name string, spec sharedBuildSpec, consumers []unit, opts renderOpts) {
	b.WriteString("\n")
	fmt.Fprintf(b, "  # BUILD ONCE for every %s unit, promote by digest: one job pushes the\n", name)
	b.WriteString("  # images into the shared Artifact Registry owned by the build\n")
	b.WriteString("  # Environment's project, and every rung of every consuming unit deploys\n")
	b.WriteString("  # those immutable @sha256 refs. Rebuilding per environment is what made\n")
	b.WriteString("  # what reached production not be the artifact that was smoke-tested.\n")
	fmt.Fprintf(b, "  # Consumed by: %s\n", strings.Join(unitNames(consumers), ", "))
	fmt.Fprintf(b, "  %s:\n", job)
	b.WriteString("    needs: [orchestrate]\n")
	fmt.Fprintf(b, "    if: %s\n", buildCondition(consumers, opts))
	b.WriteString("    runs-on: ubuntu-latest\n")
	fmt.Fprintf(b, "    timeout-minutes: %d\n", spec.timeoutMinutes)
	b.WriteString("    permissions:\n")
	for _, p := range callerPermissions {
		fmt.Fprintf(b, "      %s\n", p)
	}
	fmt.Fprintf(b, "    environment: %s\n", spec.environment)
	b.WriteString("    env:\n")
	for _, e := range spec.env {
		fmt.Fprintf(b, "      %s\n", e)
	}
	b.WriteString("    outputs:\n")
	for _, out := range spec.outputs {
		fmt.Fprintf(b, "      %s: ${{ steps.%s.outputs.%s }}\n", out, sharedBuildStepID(out), sharedBuildStepOutput(out))
	}
	spec.renderSteps(b)
}

// sharedBuildStepID / sharedBuildStepOutput map a job output to the step that
// writes it, transcribed from tabula-deploy.yaml's `outputs:` block
// (image-digest <- steps.push.outputs.image-digest,
// web-image-digest <- steps.web-image.outputs.digest). The two idioms differ
// because the two steps do, and a job output wired to the wrong step resolves
// to "" — the deploy then runs with an empty image ref.
func sharedBuildStepID(output string) string {
	if output == "web-image-digest" {
		return "web-image"
	}
	return "push"
}

func sharedBuildStepOutput(output string) string {
	if output == "web-image-digest" {
		return "digest"
	}
	return output
}

func unitNames(units []unit) []string {
	out := make([]string, 0, len(units))
	for _, u := range units {
		out = append(out, u.Name)
	}
	return out
}

// renderChangelogJob emits "what is shipping" onto the run page.
//
// PUSH-KEYED (legacy tabula-deploy's carried no `if:` at all): with a
// repo-wide `release:` trigger this job would otherwise run on every published
// release of every unrelated component — the same waste the legacy build job's
// tag guard exists to prevent — and on a release event the release already
// carries its own curated changelog.
func renderChangelogJob(b *strings.Builder, u unit, opts renderOpts) error {
	if len(u.ChangelogInputs) == 0 {
		return nil
	}
	b.WriteString("\n")
	b.WriteString("  # Render WHAT IS SHIPPING into the run page before the (gated) deploys, so\n")
	b.WriteString("  # an approver reads the actual scope. Ungated by the manifest and\n")
	b.WriteString("  # independent of every other job, so it never delays a rollout.\n")
	fmt.Fprintf(b, "  %s-changelog:\n", u.Name)
	fmt.Fprintf(b, "    if: %s && github.event_name == 'push'\n", killSwitchExpr)
	fmt.Fprintf(b, "    uses: %s\n", changelogWorkflow)
	// No `environment:` and no rung: this job reads a file and writes a step
	// summary, so renderWith's ladder key must not be applied to it.
	return renderInputs(b, u.ChangelogInputs)
}

// renderSoakJob emits the promotion interlock (tools/ci/require-dev-soak.sh):
// refuse to promote while this unit's DEVELOPMENT deploy is red.
//
// Transcribed from tabula-deploy.yaml's require-dev-soak-api /
// oauth-user-inspector-deploy.yaml's require-dev-soak, including the two facts
// that make it real rather than decorative:
//
//   - it is an ORDINARY top-level job. `actions: read` on a `uses:` job's own
//     permissions block makes GitHub reject the entire calling workflow at
//     startup, with no jobs instantiated — bisected empirically, four times.
//   - its `if:` is the SAME condition as the rung it guards, so it can never be
//     skipped when that rung runs. A skipped need with an explicit
//     `result == 'success'` check would block the promotion outright; a skipped
//     need WITHOUT one silently disarms the gate.
func renderSoakJob(b *strings.Builder, job string, u unit, opts renderOpts) error {
	env := u.Environments[soakRung]
	b.WriteString("\n")
	b.WriteString("  # PROMOTION INTERLOCK: refuse to promote while development is RED.\n")
	b.WriteString("  # release-please opens a release PR on any push and auto-merges it on the\n")
	b.WriteString("  # PR check suite, which knows nothing about the DEPLOYMENT — so without\n")
	b.WriteString("  # this a commit whose development deploy FAILED rides into nonproduction\n")
	b.WriteString("  # with no human in the loop. Fails CLOSED on a definitive red, OPEN on an\n")
	b.WriteString("  # indeterminate answer (tools/ci/require-dev-soak.sh).\n")
	fmt.Fprintf(b, "  %s:\n", job)
	fmt.Fprintf(b, "    if: %s\n", soakCondition(u, env, opts))
	b.WriteString("    runs-on: ubuntu-latest\n")
	b.WriteString("    timeout-minutes: 5\n")
	b.WriteString("    permissions:\n")
	b.WriteString("      contents: read\n")
	b.WriteString("      # `actions: read` is what lets the script read this repo's run\n")
	b.WriteString("      # history; it is safe on an ordinary job (see the header note).\n")
	b.WriteString("      actions: read\n")
	b.WriteString("    steps:\n")
	fmt.Fprintf(b, "      - uses: %s\n", checkoutPin)
	b.WriteString("      - env:\n")
	b.WriteString("          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}\n")
	b.WriteString("          # WHICH workflow's history holds the development deploy, and which\n")
	b.WriteString("          # job in it. DEV_JOB_NAME is the CHECK-RUN name, which GitHub\n")
	b.WriteString("          # composes as \"<caller job id> / <called workflow's job id>\" — the\n")
	b.WriteString("          # generated development job calling _deploy-cloud-run.yaml's\n")
	b.WriteString("          # `deploy`. A name that matches nothing makes the gate fail-open\n")
	b.WriteString("          # forever, i.e. visible and inert, which its own header calls\n")
	b.WriteString("          # worse than no gate at all.\n")
	fmt.Fprintf(b, "          WORKFLOW_FILE: %s\n", opts.workflowFile)
	fmt.Fprintf(b, "          DEV_JOB_NAME: %s-%s / %s\n", u.Name, u.Environments[0], cloudRunCalleeJob)
	b.WriteString("          # Break-glass override, from the dispatch form first and the repo\n")
	b.WriteString("          # variable second (an unset variable is falsy, so this ends at\n")
	b.WriteString("          # 'false'). The script logs loudly when it is honoured.\n")
	b.WriteString("          ALLOW_UNSOAKED: ${{ inputs.allow-unsoaked || vars.ALLOW_UNSOAKED_PROMOTION || 'false' }}\n")
	fmt.Fprintf(b, "        run: %s\n", soakScript)
	return nil
}

// renderRungCompanions renders (once each) the companions that must apply
// before this unit serves THIS rung, and returns their job ids.
func renderRungCompanions(b *strings.Builder, u unit, byName map[string]unit, rendered map[string]bool, rung int, env string, opts renderOpts) ([]string, error) {
	jobs := make([]string, 0, len(u.Companions))
	for _, c := range u.Companions {
		name := companionUnitName(c)
		cu, ok := byName[name]
		if !ok {
			return nil, fmt.Errorf("unit %q lists companion %q, which is not a declared delivery() unit — the generated `needs:` would reference a job that does not exist and GitHub would reject the whole workflow at startup", u.Name, c)
		}
		spec, ok := companionWorkflows[name]
		if !ok {
			return nil, fmt.Errorf("unit %q lists companion %q, but //tools/delivery/gen has no reusable workflow registered for it — add it to companionWorkflows (an unregistered companion would render a `uses:` pointing nowhere)", u.Name, name)
		}
		if !contains(cu.Environments, env) {
			return nil, fmt.Errorf("unit %q delivers to %q, but its companion %q declares no %q rung (environments = %v) — the companion cannot expand for an environment it does not have", u.Name, env, name, env, cu.Environments)
		}
		job := name + "-" + env
		jobs = append(jobs, job)
		if rendered[job] {
			continue
		}
		rendered[job] = true
		if err := renderCompanionJob(b, job, u, cu, spec, rung, env, opts); err != nil {
			return nil, err
		}
	}
	return jobs, nil
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
func renderBuildJob(b *strings.Builder, job string, u unit, opts renderOpts) error {
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
	fmt.Fprintf(b, "    if: %s\n", buildCondition([]unit{u}, opts))
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

// renderCompanionJob emits the EXPAND half of expand-before-serve (§2.15):
// register the environment's OIDC client before its new revision arrives.
//
// One companion job per RUNG, chained exactly as legacy chains them: the
// development one hangs off the manifest, the nonproduction one off the
// release event, and the production one additionally behind nonproduction's
// DEPLOY having succeeded (legacy zitadel-prod's `needs: [deploy-nonprod]`).
func renderCompanionJob(b *strings.Builder, job string, consumer, companion unit, spec companionSpec, rung int, env string, opts renderOpts) error {
	b.WriteString("\n")
	fmt.Fprintf(b, "  # EXPAND before serve (§2.15): %s is applied before\n", companion.Name)
	fmt.Fprintf(b, "  # %s's new %s revision takes traffic, or hosted login is\n", consumer.Name, env)
	b.WriteString("  # broken on arrival. Gated on the SAME verdict as the deploy below — if\n")
	b.WriteString("  # no revision is arriving there is nothing to expand for. Applying it\n")
	b.WriteString("  # unconditionally is #1794: ~9 needless applies a day against a stack\n")
	b.WriteString("  # whose force-replace DELETES the live OIDC client.\n")
	fmt.Fprintf(b, "  %s:\n", job)
	if rung == 0 {
		b.WriteString("    needs: [orchestrate]\n")
		b.WriteString("    # `always() && !cancelled()` (not the implicit success()-of-needs):\n")
		b.WriteString("    # orchestrate may legitimately be skipped or red, and the fail-open arm\n")
		b.WriteString("    # below has to be reachable in exactly those cases.\n")
	} else if rung > 1 {
		fmt.Fprintf(b, "    needs: [%s]\n", deployJobID(consumer, consumer.Environments[rung-1]))
	}
	fmt.Fprintf(b, "    if: %s\n", companionCondition(spec, consumer, rung, env, opts))
	renderCallerPermissions(b)
	fmt.Fprintf(b, "    uses: %s\n", spec.workflow)
	if err := renderWith(b, companion.WorkflowInputs, env); err != nil {
		return fmt.Errorf("unit %q: companion %q: %w", consumer.Name, companion.Name, err)
	}
	b.WriteString("    secrets: inherit\n")
	return nil
}

// deployJobID is the one place a rung's job id is spelled, so a `needs:`
// pointing at a rung and the rung itself cannot disagree.
func deployJobID(u unit, env string) string {
	return u.Name + "-" + env
}

// renderDeployJob emits the SERVE half for one rung.
func renderDeployJob(b *strings.Builder, u unit, rung int, env, buildJob, digestOutput, soakJob string, companionJobs []string, opts renderOpts) error {
	b.WriteString("\n")
	if rung == 0 {
		b.WriteString("  # The push rung: main is the continuous-integration surface, so every\n")
		b.WriteString("  # affected merge lands here and nowhere else.\n")
	} else {
		fmt.Fprintf(b, "  # PROMOTION rung %d/%d — release-gated, never reached by a push.\n", rung, len(u.Environments)-1)
	}
	fmt.Fprintf(b, "  %s:\n", deployJobID(u, env))

	needs := []string{}
	if rung == 0 {
		needs = append(needs, "orchestrate")
	}
	needs = append(needs, buildJob)
	if rung == soakRung && soakJob != "" {
		needs = append(needs, soakJob)
	}
	if rung > 1 {
		// Ladder: production is smoke-gated by nonproduction WITHIN the same
		// release run.
		needs = append(needs, deployJobID(u, u.Environments[rung-1]))
	}
	needs = append(needs, companionJobs...)
	fmt.Fprintf(b, "    needs: [%s]\n", strings.Join(needs, ", "))

	b.WriteString("    # The build MUST have succeeded — there is no image otherwise, and this\n")
	b.WriteString("    # is an EQUALITY, not a `!= 'failure'`, so a SKIPPED build stops the\n")
	b.WriteString("    # deploy too rather than promoting whatever the registry's `latest`\n")
	b.WriteString("    # happens to hold. `!cancelled()` keeps the whole condition reachable\n")
	b.WriteString("    # when a need was skipped, which the implicit success()-of-needs would\n")
	b.WriteString("    # not.\n")
	if len(companionJobs) > 0 {
		b.WriteString("    # A companion that is SKIPPED — its repo-variable gate is off — must not\n")
		b.WriteString("    # block the deploy, while one that FAILED must.\n")
	}
	if rung == soakRung && soakJob != "" {
		b.WriteString("    # The soak result is checked EXPLICITLY: an `if:` REPLACES the default\n")
		b.WriteString("    # success()-of-all-needs rather than ANDing with it, so without this\n")
		b.WriteString("    # clause a RED interlock would still let the promotion run — the gate\n")
		b.WriteString("    # silently a no-op, which is how it was found broken before.\n")
	}
	fmt.Fprintf(b, "    if: %s\n", deployCondition(u, rung, env, buildJob, soakJob, companionJobs, opts))
	renderCallerPermissions(b)
	fmt.Fprintf(b, "    uses: %s\n", cloudRunWorkflow)
	// image-digest is the generator's to supply, not the declaration's: it
	// names a JOB this renderer created, and WHICH of that job's outputs comes
	// from image_digest_output. Build-once/promote-by-digest is the whole
	// point — the digest that soaked on development is the one that later
	// promotes, never a rebuild.
	inputs := make(map[string]any, len(u.WorkflowInputs)+1)
	for k, v := range u.WorkflowInputs {
		inputs[k] = v
	}
	inputs["image-digest"] = fmt.Sprintf("${{ needs.%s.outputs.%s }}", buildJob, digestOutput)
	// The preflight (spec §4.5) is likewise the generator's to supply: the
	// declaration says WHETHER this unit can content-address its live state
	// (preflight = "revision-name"), and that becomes the reusable workflow's
	// skip-if-unchanged input. delivery() refuses the input in workflow_inputs
	// so the two can never disagree.
	if u.Preflight != "" {
		inputs["skip-if-unchanged"] = true
	}
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

// renderDeclaredModeUnit renders a unit whose kind has no built-in job shape
// and whose declaration picks one (render = "reusable" | "transcribed").
//
// These are the Wave-B2 units: publishes and Pulumi applies. They carry
// promotion = "" — every rung delivers ON PUSH, which is exactly what their
// legacy workflows do. That is safe here and would not be for a cloud-run app,
// because the gate on each rung is its own GitHub Environment reviewer
// (foundation-proj-<env> is protected) rather than a release tag, and because
// the rungs are CHAINED: nonproduction cannot start until development
// succeeded, production not until nonproduction did — the sequential ladder
// their legacy workflows spell out job by job.
func renderDeclaredModeUnit(b *strings.Builder, u unit, opts renderOpts) error {
	fmt.Fprintf(b, "\n  # ======== unit: %s → %s ========\n", u.Name, strings.Join(u.Environments, " → "))
	fmt.Fprintf(b, "  # Declared in %s/BUILD; break-glass target: %s\n", u.Package, u.Run)
	if u.LegacyWorkflow != "" {
		fmt.Fprintf(b, "  # Transcribed from %s job %q (that file was deleted in Phase 3; see git history).\n", u.LegacyWorkflow, u.LegacyJob)
	}
	if u.GateVar != "" {
		fmt.Fprintf(b, "  # Push applies are OPT-IN: they additionally require vars.%s == 'true'.\n", u.GateVar)
	}

	for i, env := range u.Environments {
		switch u.Render {
		case renderReusable:
			if err := renderReusableRung(b, u, i, env, opts); err != nil {
				return err
			}
		case renderTranscribed:
			if err := renderTranscribedRung(b, u, i, env, opts); err != nil {
				return err
			}
		default:
			return fmt.Errorf("unit %q declares render %q, which //tools/delivery/gen does not implement (known: %q, %q)", u.Name, u.Render, renderReusable, renderTranscribed)
		}
	}
	return nil
}

// renderReusableRung emits one rung as a caller of a registered reusable
// workflow.
func renderReusableRung(b *strings.Builder, u unit, rung int, env string, opts renderOpts) error {
	spec, ok := reusableWorkflows[u.Name]
	if !ok {
		return fmt.Errorf("unit %q declares render = %q, but //tools/delivery/gen has no reusable workflow registered for it — add it to reusableWorkflows (an unregistered unit would render a `uses:` pointing nowhere, which GitHub rejects at startup, taking orchestrate down with it)", u.Name, renderReusable)
	}
	b.WriteString("\n")
	renderRungNote(b, u, rung, env)
	fmt.Fprintf(b, "  %s:\n", deployJobID(u, env))
	fmt.Fprintf(b, "    needs: [%s]\n", strings.Join(pushLadderNeeds(u, rung), ", "))
	fmt.Fprintf(b, "    if: %s\n", pushLadderCondition(u, rung, env, opts))
	renderCallerPermissions(b)
	fmt.Fprintf(b, "    uses: %s\n", spec.workflow)
	if err := renderInputs(b, spec.rungInputs(u, env)); err != nil {
		return fmt.Errorf("unit %q rung %q: %w", u.Name, env, err)
	}
	b.WriteString("    secrets: inherit\n")
	return nil
}

// renderTranscribedRung emits one rung as a plain job whose steps are the
// legacy job's, verbatim.
func renderTranscribedRung(b *strings.Builder, u unit, rung int, env string, opts renderOpts) error {
	spec, ok := transcribedJobs[u.Name]
	if !ok {
		return fmt.Errorf("unit %q declares render = %q, but //tools/delivery/gen has no transcribed job registered for it — transcribe %s's %q job into transcribedJobs and pin it with a parity test (a guessed publish/apply job is discovered failing at 2am)", u.Name, renderTranscribed, u.LegacyWorkflow, u.LegacyJob)
	}
	b.WriteString("\n")
	renderRungNote(b, u, rung, env)
	fmt.Fprintf(b, "  %s:\n", deployJobID(u, env))
	fmt.Fprintf(b, "    needs: [%s]\n", strings.Join(pushLadderNeeds(u, rung), ", "))
	fmt.Fprintf(b, "    if: %s\n", pushLadderCondition(u, rung, env, opts))
	b.WriteString("    runs-on: ubuntu-latest\n")
	fmt.Fprintf(b, "    timeout-minutes: %d\n", spec.timeoutMinutes)
	b.WriteString("    # Transcribed from the legacy job: job-level permissions REPLACE the\n")
	b.WriteString("    # workflow-level block, which is narrower than this job needs.\n")
	b.WriteString("    permissions:\n")
	for _, p := range spec.permissions {
		fmt.Fprintf(b, "      %s\n", p)
	}
	if u.GitHubEnvironment != "" {
		fmt.Fprintf(b, "    environment: %s\n", strings.ReplaceAll(u.GitHubEnvironment, "{env}", env))
	}
	if len(spec.env) > 0 {
		b.WriteString("    env:\n")
		for _, e := range spec.env {
			fmt.Fprintf(b, "      %s\n", e)
		}
	}
	spec.renderSteps(b, u, env)
	return nil
}

// renderRungNote is the per-rung human header.
func renderRungNote(b *strings.Builder, u unit, rung int, env string) {
	if len(u.Environments) == 1 {
		b.WriteString("  # Single rung: delivers on an affected push (and on a dispatch naming it).\n")
	} else if rung == 0 {
		b.WriteString("  # Rung 1 of the sequential ladder: delivers on an affected push. The\n")
		b.WriteString("  # later rungs chain behind it, exactly as the legacy workflow's jobs do.\n")
	} else {
		fmt.Fprintf(b, "  # Rung %d of %d: starts only once %s succeeded in THIS run.\n",
			rung+1, len(u.Environments), deployJobID(u, u.Environments[rung-1]))
	}
	if u.GitHubEnvironment != "" {
		fmt.Fprintf(b, "  # GitHub Environment: %s (its reviewer gate and WIF vars).\n",
			strings.ReplaceAll(u.GitHubEnvironment, "{env}", env))
	}
}

// pushLadderNeeds: every rung reads the manifest, so every rung waits for
// orchestrate; rungs after the first also wait for their predecessor.
func pushLadderNeeds(u unit, rung int) []string {
	needs := []string{"orchestrate"}
	if rung > 0 {
		needs = append(needs, deployJobID(u, u.Environments[rung-1]))
	}
	return needs
}

// pushLadderCondition is the push-lane ladder's `if:`.
//
// Rung 0: the manifest verdict (with its fail-open arm) or a dispatch naming
// this unit and this rung. Rung N>0: the same, AND the previous rung having
// SUCCEEDED — the chain the legacy workflows spell out with
// `needs.<prev>.result == 'success'` inside their push arm, so that a
// single-env dispatch can still target a later rung directly while a push
// always walks the ladder in order.
func pushLadderCondition(u unit, rung int, env string, opts renderOpts) string {
	push := pushArm([]unit{u})
	if u.GateVar != "" {
		// Inside the PUSH arm only: the legacy switch makes automatic applies
		// opt-in, while a deliberate human dispatch is always allowed.
		push = fmt.Sprintf("(github.event_name == 'push' && vars.%s == 'true' && %s)", u.GateVar, strings.TrimSuffix(strings.TrimPrefix(push, "(github.event_name == 'push' && "), ")"))
	}
	if rung > 0 {
		push = fmt.Sprintf("(%s && needs.%s.result == 'success')", push, deployJobID(u, u.Environments[rung-1]))
	}
	arms := []string{push}
	if opts.dispatch {
		arms = append(arms, dispatchArm(u, env))
	}
	return strings.Join([]string{killSwitchExpr, "!cancelled()", anyOf(arms...)}, " && ")
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

// pushArm is the manifest-driven half of every push-lane condition: deliver
// when the orchestrator says this unit is affected, AND ALSO when it did not
// manage to say anything (`result != 'success'` covers failed, skipped and the
// run being cancelled out from under it). Inherited verbatim — detection must
// never be the reason a real change fails to ship.
//
// SCOPED TO THE PUSH EVENT, which the Phase-1 shape did not need to be. Once
// `release:` is a trigger of this workflow, EVERY job in it is instantiated on
// EVERY published release in the repo — and on a release event `orchestrate`
// is skipped, so a bare fail-open arm would read `result != 'success'` as true
// and deploy development from an unrelated component's release. The `&&` is
// load-bearing: `github.event_name == 'push' || <gate>` is #1759, the shape
// that made six jobs bypass the gate they shared.
func pushArm(units []unit) string {
	clauses := []string{"needs.orchestrate.result != 'success'"}
	for _, u := range units {
		clauses = append(clauses, affectedExpr(u))
	}
	return fmt.Sprintf("(github.event_name == 'push' && (%s))", strings.Join(clauses, " || "))
}

// releaseArm is the promotion trigger, per unit's declared tag prefix.
//
// GitHub offers no per-tag filter on `on: release`, so every release-gated job
// carries this guard itself. Without it, one component's release rebuilds and
// re-promotes another's — wasted compute, a false red on that release's checks
// when the build flakes, and (for a deploy) an unreviewed promotion.
func releaseArm(units []unit) string {
	prefixes := make([]string, 0, len(units))
	for _, u := range units {
		prefixes = append(prefixes, fmt.Sprintf("startsWith(github.event.release.tag_name, '%s')", strings.TrimPrefix(u.Promotion, "release:")))
	}
	if len(prefixes) == 1 {
		return fmt.Sprintf("(github.event_name == 'release' && %s)", prefixes[0])
	}
	return fmt.Sprintf("(github.event_name == 'release' && (%s))", strings.Join(prefixes, " || "))
}

// releaseArmAfter is releaseArm plus the prior rung's success — the ladder
// that makes nonproduction smoke-gate production within one release run.
func releaseArmAfter(u unit, priorJob string) string {
	return fmt.Sprintf("(github.event_name == 'release' && startsWith(github.event.release.tag_name, '%s') && needs.%s.result == 'success')",
		strings.TrimPrefix(u.Promotion, "release:"), priorJob)
}

// dispatchArm matches a manual run naming THIS unit and THIS rung. One unit,
// one environment: a dispatch must never fan out into a ladder.
func dispatchArm(u unit, env string) string {
	return fmt.Sprintf("(github.event_name == 'workflow_dispatch' && inputs.unit == '%s' && inputs.environment == '%s')", u.Name, env)
}

// dispatchArmAnyRung matches a manual run naming any of these units, whatever
// environment it targets. The build is the only job that wants this: every
// rung of a unit consumes its digest, so the image has to exist for a dispatch
// of ANY of them (legacy's build carried a bare `event_name == 'workflow_dispatch'`
// arm for the same reason).
func dispatchArmAnyRung(units []unit) string {
	clauses := make([]string, 0, len(units))
	for _, u := range units {
		clauses = append(clauses, fmt.Sprintf("inputs.unit == '%s'", u.Name))
	}
	if len(clauses) == 1 {
		return fmt.Sprintf("(github.event_name == 'workflow_dispatch' && %s)", clauses[0])
	}
	return fmt.Sprintf("(github.event_name == 'workflow_dispatch' && (%s))", strings.Join(clauses, " || "))
}

// anyOf joins trigger arms with `||` and parenthesises the result, so the
// leading `&&`-chain of guards (kill switch, needs results) can never be
// shadowed by a single true arm.
func anyOf(arms ...string) string {
	nonEmpty := make([]string, 0, len(arms))
	for _, a := range arms {
		if a != "" {
			nonEmpty = append(nonEmpty, a)
		}
	}
	if len(nonEmpty) == 1 {
		return nonEmpty[0]
	}
	return "(" + strings.Join(nonEmpty, " || ") + ")"
}

// buildCondition: the image must exist whenever ANY consumer delivers, on any
// trigger any consumer answers to.
func buildCondition(consumers []unit, opts renderOpts) string {
	arms := []string{pushArm(consumers)}
	if opts.release {
		if promoting := promotionUnits(consumers); len(promoting) > 0 {
			arms = append(arms, releaseArm(promoting))
		}
	}
	if opts.dispatch {
		arms = append(arms, dispatchArmAnyRung(consumers))
	}
	return strings.Join([]string{killSwitchExpr, "always()", "!cancelled()", anyOf(arms...)}, " && ")
}

// companionCondition mirrors the legacy zitadel-* jobs' `if:` clause for
// clause, with `orchestrate` in place of `gate` and the kill switch in front.
func companionCondition(spec companionSpec, consumer unit, rung int, env string, opts renderOpts) string {
	parts := []string{killSwitchExpr}
	if spec.gateVar != "" {
		parts = append(parts, spec.gateVar)
	}
	var arms []string
	if rung == 0 {
		// `always()` only where there is a need whose skip must not stop this
		// job (orchestrate); the promotion rungs' companions either have no
		// needs at all or an explicit result check in their arm.
		parts = append(parts, "always()")
		arms = append(arms, pushArm([]unit{consumer}))
	} else if rung == 1 {
		arms = append(arms, releaseArm([]unit{consumer}))
	} else {
		arms = append(arms, releaseArmAfter(consumer, deployJobID(consumer, consumer.Environments[rung-1])))
	}
	if opts.dispatch {
		arms = append(arms, dispatchArm(consumer, env))
	}
	parts = append(parts, "!cancelled()", anyOf(arms...))
	return strings.Join(parts, " && ")
}

// soakCondition is DELIBERATELY the same condition as the rung it guards: a
// gate that can be skipped while its rung runs is a gate that is not there.
func soakCondition(u unit, env string, opts renderOpts) string {
	arms := []string{releaseArm([]unit{u})}
	if opts.dispatch {
		arms = append(arms, dispatchArm(u, env))
	}
	return strings.Join([]string{killSwitchExpr, "!cancelled()", anyOf(arms...)}, " && ")
}

// deployCondition mirrors the legacy deploy-* jobs' `if:` clause for clause:
// `needs.<build>.result == 'success'` (no image, no deploy — and note this is
// an EQUALITY, not a `!= 'failure'`, so a SKIPPED build also stops the deploy),
// each companion tolerated when skipped and refused when failed, the soak
// interlock checked explicitly on the rung it guards, and the trigger arms for
// this rung.
func deployCondition(u unit, rung int, env, buildJob, soakJob string, companionJobs []string, opts renderOpts) string {
	parts := []string{
		killSwitchExpr,
		"!cancelled()",
		fmt.Sprintf("needs.%s.result == 'success'", buildJob),
	}
	if rung == soakRung && soakJob != "" {
		parts = append(parts, fmt.Sprintf("needs.%s.result == 'success'", soakJob))
	}
	for _, job := range companionJobs {
		parts = append(parts, fmt.Sprintf("needs.%s.result != 'failure'", job))
	}

	var arms []string
	switch {
	case rung == 0:
		arms = append(arms, pushArm([]unit{u}))
	case rung == 1:
		arms = append(arms, releaseArm([]unit{u}))
	default:
		arms = append(arms, releaseArmAfter(u, deployJobID(u, u.Environments[rung-1])))
	}
	if opts.dispatch {
		arms = append(arms, dispatchArm(u, env))
	}
	parts = append(parts, anyOf(arms...))
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

	return renderInputs(b, merged)
}

// renderInputs emits a `with:` map with no ladder key — the changelog job's
// shape, and the primitive renderWith builds on. Keys are sorted so the output
// is byte-stable (Go map iteration is randomized on purpose, and tidy-check
// diffs bytes).
func renderInputs(b *strings.Builder, inputs map[string]any) error {
	keys := make([]string, 0, len(inputs))
	for k := range inputs {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	b.WriteString("    with:\n")
	for _, k := range keys {
		v, err := yamlScalar(inputs[k])
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
	// DEFAULT 2. tidy-check runs a bare `bazel run //tools/ci:gen` and diffs
	// the result against the committed file, so the default IS the committed
	// phase — a lower default here would regenerate a narrower workflow over
	// the acting one and fail the gate on every unrelated PR. `--phase 0` and
	// `--phase 1` remain for rendering the earlier shapes, which their goldens
	// pin: a feature that is supposed to be additive has to be provable as
	// additive.
	phase := flag.Int("phase", 2, "0 = shadow (orchestrate job only); 1 = + the push rung; >=2 = + release promotion, dispatch inputs and changelog")
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
