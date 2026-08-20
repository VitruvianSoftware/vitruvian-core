# Copyright (c) 2026 VitruvianSoftware
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

"""delivery() — declare a unit the delivery orchestrator governs.

The Bazel graph is the delivery registry (spec:
docs/superpowers/specs/2026-08-19-delivery-orchestrator-design.md §4.1).
Each unit materializes an inert filegroup tagged "delivery" wrapping a JSON
metadata file. The orchestrator discovers units with a plain `bazel query`
over the "delivery" tag (query, not cquery: nothing is configured, so the
macOS-toolchain landmine from #1039/#1297 cannot fire) and `bazel build`s
the metadata files to read them.

Nothing here runs anything. The `run` target is executed by the generated
delivery workflow — and by the break-glass runbook, which is the point: one
delivery path, two triggers.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")

def delivery(
        name,
        kind,
        run,
        environments,
        github_environment,
        build = "",
        build_context = "",
        image_repository_path = "",
        shared_build = "",
        image_digest_output = "",
        promotion = "",
        soak = False,
        render = "",
        legacy_workflow = "",
        legacy_job = "",
        gate_var = "",
        companions = [],
        extra_paths = [],
        exclude_paths = [],
        graph_targets = [],
        workflow_inputs = {},
        changelog_inputs = {},
        preflight = ""):
    """Declares one delivery unit.

    Args:
      name: unit name, unique repo-wide (conformance-enforced).
      kind: "cloud-run" | "pulumi" | "publish" — selects the generated job shape.
      run: the bazel run target that performs the delivery (the break-glass target).
      environments: ordered ladder, e.g. ["development", "nonproduction", "production"].
      github_environment: GitHub Environment name pattern; "{env}" is substituted.
      build: optional BAZEL target that must build before delivery ("" = none).
      build_context: Docker build context directory for an app whose image is
        NOT a Bazel target (build = ""), e.g. "oauth-user-inspector/". The
        generated build job runs `docker buildx build --push <build_context>`
        and captures the pushed image's immutable digest, exactly as the
        hand-written build job it replaces does.
      image_repository_path: Artifact Registry path UNDER the project for that
        image, e.g. "oauth-user-inspector/app". The region and project come
        from the build GitHub Environment's own vars, so this is the only part
        of the image ref a declaration owns.
      shared_build: name of a SHARED build job every unit carrying the same
        value consumes, e.g. "tabula" (one `tabula-build` job producing both
        the API and the web image, exactly as tabula-deploy.yaml's single
        `build` job does today). A shared build's steps cannot be derived from
        a declaration — they are transcribed verbatim from the job they
        replace and pinned by a parity test — so //tools/delivery/gen keeps an
        explicit registry of them and rejects an unregistered name rather than
        rendering a build that pushes nothing. Mutually exclusive with
        build / build_context / image_repository_path: the shared job owns how
        its images are produced.
      image_digest_output: WHICH output of that shared build job this unit
        deploys, e.g. "image-digest" (tabula-api) vs "web-image-digest"
        (tabula-web). Required with shared_build, and validated against the
        registered job's declared outputs by the generator: GitHub resolves an
        unknown `needs.<job>.outputs.<name>` to the EMPTY STRING rather than
        erroring, so a typo here would deploy an empty image ref instead of
        failing.
      promotion: "" (every env on push) or "release:<tag-prefix>" — first env on
        push, later envs only on a matching release event.
      render: how the generated job for each rung is built.
        "" (default) uses the kind's built-in shape — kind="cloud-run" calls
        _deploy-cloud-run.yaml, every other kind renders NOTHING (it can still
        be another unit's companion, which is what zitadel-apps is).
        "reusable" calls a reusable workflow registered for this unit in
        //tools/delivery/gen (the identity ladders' _*-identity-apply.yaml).
        "transcribed" renders the legacy job's steps verbatim, from a template
        registered for this unit in //tools/delivery/gen.
        WHY THE TEMPLATE LIVES IN THE GENERATOR AND NOT HERE: a declaration is
        DATA. A steps blob in a BUILD file would be YAML-in-Starlark that no
        linter, no actionlint and no parity test could reach, and every
        declaration would become a place to hand-edit workflow logic — which is
        the class of drift the generator exists to end. The steps are
        transcribed once, in Go, and pinned against the live legacy job by a
        parity test keyed on legacy_workflow/legacy_job below.
      legacy_workflow: PROVENANCE — the workflow file this unit's job was
        transcribed FROM, e.g. ".github/workflows/tabula-dev-latest.yaml". It
        was the parity test's baseline while both files existed; Phase 3 deleted
        those workflows, so it now records where the transcription came from for
        anyone reading the generated job (git history has the original). Not a
        runtime input.
      legacy_job: the job id inside legacy_workflow that was transcribed.
      gate_var: an ADDITIONAL repo-variable condition every rendered rung must
        satisfy, e.g. "SYNC_AUTH_AUTO_APPLY" — the opt-in switch a legacy job
        carries because its apply is off by default. Dropping it would turn
        "cleanly does not run" into "runs on every affected push".
      soak: gate the promotion rungs on tools/ci/require-dev-soak.sh, which
        refuses to promote while the unit's DEVELOPMENT deploy is red. Requires
        promotion (there is no promotion rung to gate without it) and at least
        two environments (the ladder needs something to promote INTO).
      companions: expand-before-serve delivery() labels that must apply first.
      extra_paths: path regexes ADDED to the unit's affected detection
        (moves the workflow extra-path-regex strings next to the code).
      exclude_paths: path regexes REMOVED from the unit's affected detection.
      graph_targets: Bazel labels handed to the affected engine as
        DEPLOY_TARGETS, which switches it from path-only mode into GRAPH
        (target-determinator) attribution — the `deploy-targets:` input the
        unit's hand-written gate passes today. Path-only mode both
        under-triggers (a shared-library change outside the app's directories
        never redeployed it) and over-triggers (a docs-only change inside them
        did), which is why the graph is the authority wherever the artifact is
        graph-tracked. Empty = path-only mode.
      workflow_inputs: the `with:` map the generated job passes to its reusable
        workflow (spec §4.3: the generated file is a THIN CALLER LAYER over
        _deploy-cloud-run.yaml / _zitadel-apps-apply.yaml, which are kept
        as-is). String keys, scalar values (string / bool / int) — anything
        nested would have to be re-serialized into YAML by the generator, and
        the reusable workflows' `workflow_call` inputs are scalars by
        definition, so a non-scalar here is a declaration bug, not a feature.
        `environment` is DELIBERATELY not settable: which rung of the ladder a
        job serves comes from `environments`, so a declaration cannot make its
        development job deploy production.
      changelog_inputs: the `with:` map for _changelog-summary.yaml, rendering
        "what is shipping" onto the run page before the (gated) deploy. Empty
        = no changelog job. Same scalar rules as workflow_inputs.
      preflight: how this unit's deploy decides it can be SKIPPED because the
        live service already serves the desired state (spec §4.5). Values:
          ""               no preflight (the default).
          "revision-name"  the unit's Pulumi program provides cmd/revname, so
                           the desired revision name (config hash + image
                           digest) can be compared against the live serving
                           revision. The generator renders
                           `skip-if-unchanged: true` for the unit's rungs, and
                           _deploy-cloud-run.yaml runs
                           tools/ci/tabula-deploy-preflight.sh inside the
                           deploy job — AFTER the build, which is the only
                           place the image digest it needs exists.
        THE PREFLIGHT IS NOT AN ORCHESTRATOR VETO, deliberately: the decision
        needs the built digest, and the orchestrator runs before every build.
        See //tools/delivery/gen's preflight test for the full evidence.
    """
    if kind not in ("cloud-run", "pulumi", "publish"):
        fail("delivery(%s): unknown kind %r" % (name, kind))
    if not environments:
        fail("delivery(%s): environments must be a non-empty ladder" % name)
    if promotion and not promotion.startswith("release:"):
        fail("delivery(%s): promotion must be \"\" or \"release:<tag-prefix>\"" % name)

    # A cloud-run unit has to say HOW its image is produced, because the
    # generated ladder builds it: either a Bazel image target (build = ...) or a
    # Docker context + registry path. Leaving both unset would render a deploy
    # with no image, which is the shape the Phase-1 skeleton shipped -- a job
    # that can only ever fail, and only at deploy time.
    # A SHARED build is the third way a cloud-run unit's image can be produced:
    # one job, transcribed from the hand-written build it replaces, whose
    # several outputs several units consume. The two attrs are useless alone --
    # a shared_build with no image_digest_output renders a deploy that reads no
    # digest, and an image_digest_output with no shared_build names an output of
    # nothing -- so neither is accepted without the other.
    if shared_build and not image_digest_output:
        fail("delivery(%s): shared_build = %r needs image_digest_output (WHICH of that job's outputs this unit deploys, e.g. \"image-digest\")" % (name, shared_build))
    if image_digest_output and not shared_build:
        fail("delivery(%s): image_digest_output = %r without shared_build — there is no job to read that output from" % (name, image_digest_output))
    if shared_build and kind != "cloud-run":
        fail("delivery(%s): shared_build applies to kind=\"cloud-run\" only (it produces a container image for a Cloud Run rollout)" % name)
    if shared_build and (build or build_context or image_repository_path):
        fail("delivery(%s): shared_build owns how the image is produced — drop build / build_context / image_repository_path" % name)

    if kind == "cloud-run":
        docker = bool(build_context) or bool(image_repository_path)
        if build and docker:
            fail("delivery(%s): set EITHER build (a Bazel image target) OR build_context+image_repository_path (a Docker build), not both" % name)
        if not build and not shared_build:
            if not build_context:
                fail("delivery(%s): kind=\"cloud-run\" with build=\"\" needs build_context (the docker build directory) or shared_build" % name)
            if not image_repository_path:
                fail("delivery(%s): kind=\"cloud-run\" with build=\"\" needs image_repository_path (the Artifact Registry path under the project, e.g. \"app/api\")" % name)
    elif build_context or image_repository_path:
        fail("delivery(%s): build_context/image_repository_path apply to kind=\"cloud-run\" only" % name)

    # The soak interlock (tools/ci/require-dev-soak.sh) refuses to PROMOTE
    # while development is red. Both preconditions below are the difference
    # between a gate and a decoration: with no promotion there is no rung to
    # hold back, and with a one-rung ladder the only environment IS the one the
    # gate reads its evidence from, so it could only ever gate itself.
    if soak and not promotion:
        fail("delivery(%s): soak = True needs promotion — the dev-soak interlock guards a PROMOTION rung, and this unit has none" % name)
    if soak and len(environments) < 2:
        fail("delivery(%s): soak = True needs at least two environments (it holds environments[1:] back until environments[0] is green); got %r" % (name, environments))

    if render not in ("", "reusable", "transcribed"):
        fail("delivery(%s): render must be \"\", \"reusable\" or \"transcribed\", got %r" % (name, render))
    if render == "transcribed" and not (legacy_workflow and legacy_job):
        fail("delivery(%s): render = \"transcribed\" needs legacy_workflow + legacy_job — a transcription with no recorded origin is a block of workflow YAML nobody can trace back to the job it was copied from" % name)
    if render and kind == "cloud-run":
        fail("delivery(%s): kind=\"cloud-run\" already has a render shape (_deploy-cloud-run.yaml); render = %r would render it twice" % (name, render))
    if legacy_workflow and not legacy_workflow.startswith(".github/workflows/"):
        fail("delivery(%s): legacy_workflow must be a repo-root path under .github/workflows/, got %r" % (name, legacy_workflow))

    if preflight not in ("", "revision-name"):
        fail("delivery(%s): preflight must be \"\" or \"revision-name\", got %r — the only preflight mechanism that exists is the desired-vs-live revision-name comparison (tools/ci/tabula-deploy-preflight.sh)" % (name, preflight))
    if preflight and kind != "cloud-run":
        fail("delivery(%s): preflight applies to kind=\"cloud-run\" only — it is implemented by _deploy-cloud-run.yaml's skip-if-unchanged step" % name)

    for t in graph_targets:
        if not t.startswith("//"):
            fail("delivery(%s): graph_targets must be absolute Bazel labels (//pkg:target), got %r — target-determinator resolves nothing else" % (name, t))

    # workflow_inputs is rendered straight into a generated workflow's `with:`
    # map, so validate it HERE rather than in the generator: a bad value fails
    # the BUILD file that declares it (pointing at the author), instead of
    # failing `bazel run //tools/ci:gen` for whoever regenerates next.
    for k, v in workflow_inputs.items():
        if type(k) != "string":
            fail("delivery(%s): workflow_inputs keys must be strings, got %r" % (name, k))
        if k == "environment":
            fail("delivery(%s): workflow_inputs must not set \"environment\" — the ladder (environments =) owns which rung a generated job serves" % name)
        if k == "skip-if-unchanged":
            fail("delivery(%s): workflow_inputs must not set \"skip-if-unchanged\" — it is rendered from preflight =, so the declaration has ONE place that says whether this unit can skip a redundant deploy" % name)
        if type(v) not in ("string", "bool", "int"):
            fail("delivery(%s): workflow_inputs[%r] must be a scalar (string/bool/int), got %s — a reusable workflow's workflow_call inputs are scalars" % (name, k, type(v)))

    # Same rules for the changelog job's `with:` map; it is the same kind of
    # thing (a workflow_call input set), rendered by the same code path.
    for k, v in changelog_inputs.items():
        if type(k) != "string":
            fail("delivery(%s): changelog_inputs keys must be strings, got %r" % (name, k))
        if type(v) not in ("string", "bool", "int"):
            fail("delivery(%s): changelog_inputs[%r] must be a scalar (string/bool/int), got %s" % (name, k, type(v)))

    meta = {
        "schema": 1,
        "name": name,
        "kind": kind,
        "run": run,
        "build": build,
        "build_context": build_context,
        "image_repository_path": image_repository_path,
        "shared_build": shared_build,
        "image_digest_output": image_digest_output,
        "environments": environments,
        "github_environment": github_environment,
        "promotion": promotion,
        "soak": soak,
        "render": render,
        "legacy_workflow": legacy_workflow,
        "legacy_job": legacy_job,
        "gate_var": gate_var,
        "companions": companions,
        "extra_paths": extra_paths,
        "exclude_paths": exclude_paths,
        "graph_targets": graph_targets,
        "workflow_inputs": workflow_inputs,
        "changelog_inputs": changelog_inputs,
        "preflight": preflight,
        "package": native.package_name(),
    }
    write_file(
        name = name + ".delivery",
        out = name + ".delivery.json",
        content = [json.encode_indent(meta, indent = "  "), ""],
    )
    native.filegroup(
        name = name + ".delivery_unit",
        srcs = [name + ".delivery.json"],
        tags = [
            "delivery",
            "delivery-kind=" + kind,
            # keep it out of wildcard builds/tests; the orchestrator builds it
            # by explicit label after querying the tag.
            "manual",
        ],
    )
