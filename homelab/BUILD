load("//tools/doctor:defs.bzl", "doctor")

# gazelle:prefix github.com/VitruvianSoftware/homelab
# Inter-app boundary (#82) for gazelle-generated packages: the hand-set
# app-scoped visibility on //homelab/cmd/homelab is PRESERVED by gazelle on
# regeneration; any future non-internal package generating as
# //visibility:public is caught by the conformance guard
# (tools/conformance/check.sh check_app_visibility).

# Inter-app boundary (#82): targets in this package default to homelab-internal
# visibility so other top-level apps can't depend on homelab internals. Each
# internal/* package already sets explicit //homelab:__subpackages__; this marks
# the boundary at the app root for consistency and future root-package targets.
package(default_visibility = ["//homelab:__subpackages__"])

# Developer-environment check: `bazel run //homelab:doctor` (CLI `run` ignores
# visibility, so the package default is wide enough). Go is pinned to this
# app's own go.mod (`--gomod homelab/go.mod`).
doctor(
    name = "doctor",
    gomod = "homelab/go.mod",
    label = "homelab",
    optional = [
        "mise",
        "lima",
    ],
    required = [
        "bazel",
        "go",
        "git",
    ],
)
