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

    bazel run //infrastructure/pulumi/platform/repo_config:up
    bazel run //infrastructure/pulumi/platform/repo_config:preview -- --diff
    bazel run //infrastructure/pulumi/platform/repo_config:config -- set repoOwner my-org
    bazel run //infrastructure/pulumi/platform/repo_config:setup        # guided bootstrap

Each target is a thin `sh_binary` whose wrapper (`//tools/pulumi:pulumi_cmd.sh`
or `:pulumi_setup.sh`) cd's to the project dir under $BUILD_WORKSPACE_DIRECTORY
and execs the real `pulumi` CLI (Pulumi compiles/runs the Go program itself —
Bazel only launches it). Extra args after `--` are forwarded to pulumi verbatim.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# pulumi subcommands exposed as run targets, each baked into the wrapper via args.
_SUBCOMMANDS = [
    "preview",
    "up",
    "destroy",
    "refresh",
    "config",
    # `stack` (e.g. --show-urns) + `state` (e.g. state delete <urn>) for surgical
    # state ops — used to orphan resources from Pulumi state during a non-faithful
    # ArgoCD cutover without touching the live (ArgoCD-managed) objects.
    "stack",
    "state",
    # `import` adopts an already-existing cloud resource into this stack's state
    # WITHOUT changing the resource. It is the ONE sanctioned local exception to
    # "every apply runs in the pipeline" (core-vs-application-infrastructure.md
    # §7): a state-only adoption, in kind unlike `up`/`destroy` which mutate the
    # cloud. Used to move a live Cloud Run service (or a deploy identity) onto a
    # foundation stack during a workload cutover, e.g.
    #   bazel run //infrastructure/pulumi/foundation/gcp-app-infra/business_unit_2/development:import -- \
    #     --stack production --generate-code=false \
    #     gcp:cloudrunv2/service:Service tabula projects/<proj>/locations/<region>/services/tabula-api-development
    "import",
]

def pulumi_project(name, dir, visibility = ["//visibility:public"]):
    """Generate `bazel run` wrappers for a Pulumi Go project.

    Args:
      name: label prefix for the generated targets (purely a unique handle; the
        developer-facing target names are fixed — `preview`, `up`, `destroy`,
        `refresh`, `config`, `setup` — in the calling package).
      dir: workspace-relative path to the Pulumi project directory (the dir that
        holds the project's `go.mod` and `Pulumi.yaml`), e.g.
        "infrastructure/pulumi/platform/repo_config".
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

def pulumi_go_test(name = "test", extra_data = [], visibility = ["//visibility:public"]):
    """Declare a `bazel test` target that runs `go test ./...` for this Pulumi
    Go project.

    These projects are standalone Go modules (their own `go.mod`), deliberately
    kept out of the repo's `go.work` (see `pulumi_cmd.sh`) — so they aren't
    covered by the ordinary rules_go + gazelle graph, and this shells out to the
    ambient `go` toolchain the same way `pulumi_cmd.sh` shells out to the
    ambient `pulumi` CLI. It exercises the SAME `go test ./...` CI already runs
    (`.github/workflows/ci.yaml`, job "go test (IaC modules with tests)") —
    this target gives local `bazel test` / `bazel query` visibility into that
    coverage, it is not what makes CI run it.

    Tagged `no-remote-exec` + `requires-network`: RBE workers aren't guaranteed
    a `go` toolchain or Go module cache the way the GitHub Actions runner is
    (`actions/setup-go` in that job), and module verification needs the
    network. Same reasoning `tabula/api`'s `no-remote-exec` service tests use
    for an unavailable-on-RBE dependency — this runs locally only, not on RBE.

    Call this from the Pulumi project's own BUILD file, alongside
    `pulumi_project`, e.g.:

        pulumi_project(name = "repo_config", dir = "infrastructure/pulumi/platform/repo_config")
        pulumi_go_test()

    Args:
      name: target name (developer-facing label is `test`).
      extra_data: labels for files a `replace` directive in this project's
        `go.mod` points at outside this package (glob() can't cross package
        boundaries to reach them). E.g. repo_config's `go.mod` has
        `replace .../pkg/secrets => ../../pkg/secrets`, so it passes
        `["//infrastructure/pulumi:pkg_secrets_files"]` here — the replace
        target's real files have to be on disk at that relative path or `go
        test` fails with "replacement directory ... does not exist", not a
        missing-dependency error.
      visibility: visibility for the generated target.
    """
    sh_test(
        name = name,
        srcs = ["//tools/pulumi:pulumi_go_test.sh"],
        args = [native.package_name()],
        data = native.glob(["**/*.go", "go.mod", "go.sum"]) + extra_data,
        # Bazel sanitizes the test environment to PATH=/bin:/usr/bin:/usr/local/bin,
        # so an ambient `go` installed anywhere else (mise, asdf, /opt/homebrew,
        # actions/setup-go's toolcache) is invisible and the wrapper's toolchain
        # guard fires on a machine that HAS go. Inherit the caller's PATH so this
        # target resolves the same toolchain the developer's shell does; HOME and
        # the GO* cache vars come along because `go test` writes to the module and
        # build caches and re-downloads the module graph without them.
        env_inherit = [
            "PATH",
            "HOME",
            "GOPATH",
            "GOCACHE",
            "GOMODCACHE",
        ],
        tags = [
            "no-remote-exec",
            "requires-network",
        ],
        visibility = visibility,
    )

def pulumi_create_app(name = "create-app", visibility = ["//visibility:public"]):
    """Declare the one-time GitHub App Manifest-flow bootstrap target.

    Unlike `pulumi_project`, this is NOT per Pulumi project — it is a single
    repo-level helper run ONCE per GitHub org to create a shared App and set
    org-level credentials (`bazel run //tools/pulumi:create-app`). Call it from
    the `//tools/pulumi` package's BUILD file.

    Args:
      name: target name (the developer-facing label is `create-app`).
      visibility: visibility for the generated target.
    """
    sh_binary(
        name = name,
        srcs = ["create_app.sh"],
        visibility = visibility,
    )
