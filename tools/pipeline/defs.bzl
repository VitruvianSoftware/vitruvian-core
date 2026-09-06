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

"""pipeline_unit() — declare a modular test & CI verification unit in the Bazel graph.

Each unit materializes an inert JSON metadata file `<name>.pipeline.json` wrapped in a
filegroup tagged "pipeline", "pipeline-tier=<tier>", and "pipeline-persona=<persona>".
The dynamic DAG generator (`tools/pipeline/gen`) discovers these units via `bazel query`
over the "pipeline" tag or by reading metadata files, compiling them into GitHub Actions
workflows and execution matrices.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")

VALID_TIERS = ["L0", "L1", "L2", "L3"]
VALID_PERSONAS = ["all", "frontend", "backend", "infra", "platform", "security", "docs"]

def pipeline_unit(
        name,
        test_targets,
        tier = "L1",
        runner = "ubuntu-latest",
        persona = "all",
        concurrency_group = "",
        timeout_minutes = 30,
        env = {},
        depends_on = [],
        needs_emulator = False,
        tags = []):
    """Declares one modular pipeline unit.

    Args:
      name: string, unique unit name repo-wide.
      test_targets: list of strings, Bazel test/build labels to execute.
      tier: "L0" (Local) | "L1" (Presubmit) | "L2" (Merge Queue) | "L3" (Async Soak). Default: "L1".
      runner: runner tag, e.g. "ubuntu-latest" or "macos-latest". Default: "ubuntu-latest".
      persona: "all" | "frontend" | "backend" | "infra" | "platform" | "security" | "docs". Default: "all".
      concurrency_group: optional concurrency group name. Default: "pipeline-<name>".
      timeout_minutes: integer timeout in minutes for job execution. Default: 30.
      env: dict of string -> string environment variables to inject.
      depends_on: list of upstream pipeline_unit names this unit depends on in the DAG.
      needs_emulator: bool, when True the generated job boots an Android emulator
        before running the unit's targets, and passes ANDROID_HOME/ANDROID_SERIAL/PATH
        through to the tests. Only meaningful on a Linux runner: the emulator needs
        KVM, which macOS runners do not provide. Default: False.
      tags: additional tags to append.
    """
    if not name:
        fail("pipeline_unit: name must not be empty")
    if not test_targets:
        fail("pipeline_unit(%s): test_targets must be a non-empty list of Bazel labels" % name)
    if tier not in VALID_TIERS:
        fail("pipeline_unit(%s): tier %r must be one of %r" % (name, tier, VALID_TIERS))
    if persona not in VALID_PERSONAS:
        fail("pipeline_unit(%s): persona %r must be one of %r" % (name, persona, VALID_PERSONAS))
    if timeout_minutes <= 0:
        fail("pipeline_unit(%s): timeout_minutes must be positive, got %d" % (name, timeout_minutes))

    # Validate test targets syntax
    for t in test_targets:
        if not (t.startswith("//") or t.startswith(":") or t.startswith("@")):
            fail("pipeline_unit(%s): test_target %r must be a valid Bazel label (start with //, :, or @)" % (name, t))

    # Validate env key-values
    for k, v in env.items():
        if type(k) != "string" or type(v) != "string":
            fail("pipeline_unit(%s): env must be a dict of string -> string, got key %r: %r" % (name, k, v))

    if needs_emulator and runner == "macos-latest":
        fail("pipeline_unit(%s): needs_emulator requires a Linux runner -- the Android emulator needs KVM, which the macOS runners do not expose" % name)

    cg = concurrency_group if concurrency_group else ("pipeline-" + name)

    meta = {
        "schema": 1,
        "name": name,
        "package": native.package_name(),
        "test_targets": test_targets,
        "tier": tier,
        "runner": runner,
        "persona": persona,
        "concurrency_group": cg,
        "timeout_minutes": timeout_minutes,
        "env": env,
        "depends_on": depends_on,
        "needs_emulator": needs_emulator,
        "tags": tags,
    }

    # Emit <name>.pipeline.json
    write_file(
        name = name + ".pipeline_meta",
        out = name + ".pipeline.json",
        content = [json.encode_indent(meta, indent = "  "), ""],
    )

    # Materialize discoverable filegroup
    native.filegroup(
        name = name + ".pipeline_unit",
        srcs = [name + ".pipeline.json"],
        tags = [
            "pipeline",
            "pipeline-tier=" + tier,
            "pipeline-persona=" + persona,
            "manual",
        ] + tags,
    )
