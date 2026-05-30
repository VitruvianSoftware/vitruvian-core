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
"""Bazel macro that wraps a Pulumi Go project behind `bazel run` targets.

Developers should never need to memorize the `pulumi` CLI. Instead of running
`pulumi up` from the project dir, they run:

    bazel run //infrastructure/pulumi/repo_config:up
    bazel run //infrastructure/pulumi/repo_config:preview -- --diff
    bazel run //infrastructure/pulumi/repo_config:config -- set repoOwner my-org
    bazel run //infrastructure/pulumi/repo_config:setup        # guided bootstrap

Each target is a thin `sh_binary` whose wrapper (`//tools/pulumi:pulumi_cmd.sh`
or `:pulumi_setup.sh`) cd's to the project dir under $BUILD_WORKSPACE_DIRECTORY
and execs the real `pulumi` CLI (Pulumi compiles/runs the Go program itself —
Bazel only launches it). Extra args after `--` are forwarded to pulumi verbatim.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# pulumi subcommands exposed as run targets, each baked into the wrapper via args.
_SUBCOMMANDS = [
    "preview",
    "up",
    "destroy",
    "refresh",
    "config",
]

def pulumi_project(name, dir, visibility = ["//visibility:public"]):
    """Generate `bazel run` wrappers for a Pulumi Go project.

    Args:
      name: label prefix for the generated targets (purely a unique handle; the
        developer-facing target names are fixed — `preview`, `up`, `destroy`,
        `refresh`, `config`, `setup` — in the calling package).
      dir: workspace-relative path to the Pulumi project directory (the dir that
        holds the project's `go.mod` and `Pulumi.yaml`), e.g.
        "infrastructure/pulumi/repo_config".
      visibility: visibility for the generated targets.
    """
    for subcmd in _SUBCOMMANDS:
        sh_binary(
            name = subcmd,
            srcs = ["//tools/pulumi:pulumi_cmd.sh"],
            args = [dir, subcmd],
            visibility = visibility,
        )

    # Guided bootstrap helper (prereq checks, login, stack select, hints).
    sh_binary(
        name = "setup",
        srcs = ["//tools/pulumi:pulumi_setup.sh"],
        args = [dir],
        visibility = visibility,
    )
