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
        promotion = "",
        companions = [],
        extra_paths = [],
        exclude_paths = [],
        workflow_inputs = {},
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
      promotion: "" (every env on push) or "release:<tag-prefix>" — first env on
        push, later envs only on a matching release event.
      companions: expand-before-serve delivery() labels that must apply first.
      extra_paths: path regexes ADDED to the unit's affected detection
        (moves the workflow extra-path-regex strings next to the code).
      exclude_paths: path regexes REMOVED from the unit's affected detection.
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
      preflight: optional digest-preflight run target (Phase 2; recorded now).
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
    if kind == "cloud-run":
        docker = bool(build_context) or bool(image_repository_path)
        if build and docker:
            fail("delivery(%s): set EITHER build (a Bazel image target) OR build_context+image_repository_path (a Docker build), not both" % name)
        if not build:
            if not build_context:
                fail("delivery(%s): kind=\"cloud-run\" with build=\"\" needs build_context (the docker build directory)" % name)
            if not image_repository_path:
                fail("delivery(%s): kind=\"cloud-run\" with build=\"\" needs image_repository_path (the Artifact Registry path under the project, e.g. \"app/api\")" % name)
    elif build_context or image_repository_path:
        fail("delivery(%s): build_context/image_repository_path apply to kind=\"cloud-run\" only" % name)

    # workflow_inputs is rendered straight into a generated workflow's `with:`
    # map, so validate it HERE rather than in the generator: a bad value fails
    # the BUILD file that declares it (pointing at the author), instead of
    # failing `bazel run //tools/ci:gen` for whoever regenerates next.
    for k, v in workflow_inputs.items():
        if type(k) != "string":
            fail("delivery(%s): workflow_inputs keys must be strings, got %r" % (name, k))
        if k == "environment":
            fail("delivery(%s): workflow_inputs must not set \"environment\" — the ladder (environments =) owns which rung a generated job serves" % name)
        if type(v) not in ("string", "bool", "int"):
            fail("delivery(%s): workflow_inputs[%r] must be a scalar (string/bool/int), got %s — a reusable workflow's workflow_call inputs are scalars" % (name, k, type(v)))

    meta = {
        "schema": 1,
        "name": name,
        "kind": kind,
        "run": run,
        "build": build,
        "build_context": build_context,
        "image_repository_path": image_repository_path,
        "environments": environments,
        "github_environment": github_environment,
        "promotion": promotion,
        "companions": companions,
        "extra_paths": extra_paths,
        "exclude_paths": exclude_paths,
        "workflow_inputs": workflow_inputs,
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
