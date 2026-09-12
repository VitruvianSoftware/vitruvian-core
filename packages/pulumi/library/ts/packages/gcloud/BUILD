load("@aspect_rules_js//npm:defs.bzl", "npm_package")

# Minimal packaging target so aspect_rules_js can link this pnpm workspace
# package into the virtual store. The full ts_project build (compiled dist/)
# is deferred — the package builds/tests natively via pnpm+vitest, and
# pulumi/library is gazelle-excluded, so this file is maintained by hand.
npm_package(
    name = "pkg",
    srcs = ["package.json"] + glob(
        ["src/**"],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)
