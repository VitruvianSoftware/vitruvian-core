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
        promotion = "",
        companions = [],
        extra_paths = [],
        exclude_paths = [],
        preflight = ""):
    """Declares one delivery unit.

    Args:
      name: unit name, unique repo-wide (conformance-enforced).
      kind: "cloud-run" | "pulumi" | "publish" — selects the generated job shape.
      run: the bazel run target that performs the delivery (the break-glass target).
      environments: ordered ladder, e.g. ["development", "nonproduction", "production"].
      github_environment: GitHub Environment name pattern; "{env}" is substituted.
      build: optional target that must build before delivery ("" = none).
      promotion: "" (every env on push) or "release:<tag-prefix>" — first env on
        push, later envs only on a matching release event.
      companions: expand-before-serve delivery() labels that must apply first.
      extra_paths: path regexes ADDED to the unit's affected detection
        (moves the workflow extra-path-regex strings next to the code).
      exclude_paths: path regexes REMOVED from the unit's affected detection.
      preflight: optional digest-preflight run target (Phase 2; recorded now).
    """
    if kind not in ("cloud-run", "pulumi", "publish"):
        fail("delivery(%s): unknown kind %r" % (name, kind))
    if not environments:
        fail("delivery(%s): environments must be a non-empty ladder" % name)
    if promotion and not promotion.startswith("release:"):
        fail("delivery(%s): promotion must be \"\" or \"release:<tag-prefix>\"" % name)

    meta = {
        "schema": 1,
        "name": name,
        "kind": kind,
        "run": run,
        "build": build,
        "environments": environments,
        "github_environment": github_environment,
        "promotion": promotion,
        "companions": companions,
        "extra_paths": extra_paths,
        "exclude_paths": exclude_paths,
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
