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
        runner = "ubuntu-26.04",
        persona = "all",
        concurrency_group = "",
        timeout_minutes = 30,
        env = {},
        depends_on = [],
        needs_emulator = False,
        artifacts = {},
        build_flags = [],
        tags = []):
    """Declares one modular pipeline unit.

    Args:
      name: string, unique unit name repo-wide.
      test_targets: list of strings, Bazel test/build labels to execute.
      tier: "L0" (Local) | "L1" (Presubmit) | "L2" (Merge Queue) | "L3" (Async Soak). Default: "L1".
      runner: runner tag, e.g. "ubuntu-26.04" or "macos-latest". Default: "ubuntu-26.04".
      persona: "all" | "frontend" | "backend" | "infra" | "platform" | "security" | "docs". Default: "all".
      concurrency_group: optional concurrency group name. Default: "pipeline-<name>".
      timeout_minutes: integer timeout in minutes for job execution. Default: 30.
      env: dict of string -> string environment variables to inject.
      depends_on: list of upstream pipeline_unit names this unit depends on in the DAG.
      needs_emulator: bool, when True the generated job boots an Android emulator
        before running the unit's targets, and passes ANDROID_HOME/ANDROID_SERIAL/PATH
        through to the tests. Only meaningful on a Linux runner: the emulator needs
        KVM, which macOS runners do not provide. Default: False.
      artifacts: dict of artifact name -> path RELATIVE TO bazel-bin, uploaded
        after the unit's targets run (e.g. `apps/mobile/android-remote/app.apk`).
        Resolved with `bazel info bazel-bin` under this unit's own flags, because
        flags like --android_platforms move outputs to a different bin directory
        than the workspace `bazel-bin` symlink points at.
        Uploaded with `if: success()`: an artifact from a failed build is worse
        than none, because it looks installable.
      build_flags: extra Bazel flags for this unit's build/test invocation, e.g.
        ["--fat_apk_cpu=arm64-v8a,x86_64"]. For flags a unit needs that the
        shared configs do not provide; prefer a .bazelrc config when the need is
        repo-wide.
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

    for k, v in artifacts.items():
        if type(k) != "string" or type(v) != "string":
            fail("pipeline_unit(%s): artifacts must be a dict of string -> string, got key %r: %r" % (name, k, v))
        if not k:
            fail("pipeline_unit(%s): artifact name must not be empty" % name)
        if not v:
            fail("pipeline_unit(%s): artifact %r must have a non-empty path" % (name, k))
        if v.startswith("/"):
            fail("pipeline_unit(%s): artifact %r path %r must be workspace-relative, not absolute" % (name, k, v))

    for f in build_flags:
        if type(f) != "string":
            fail("pipeline_unit(%s): build_flags must be strings, got %r" % (name, f))
        if not f.startswith("--"):
            fail("pipeline_unit(%s): build_flag %r must start with -- " % (name, f))

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
        "artifacts": artifacts,
        "build_flags": build_flags,
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
