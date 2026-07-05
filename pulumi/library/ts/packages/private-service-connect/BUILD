load("@aspect_rules_js//npm:defs.bzl", "npm_package")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@npm//:defs.bzl", "npm_link_all_packages")

# Build + publish targets for @vitruviansoftware/foundation-private-service-connect. Test targets (vitest) are run
# natively for now; a vitest-under-Bazel rule is a follow-up (the monorepo
# standard is aspect_rules_jest). CI's gazelle (js) is the source of truth
# and will reconcile these against the package's actual imports.

npm_link_all_packages(name = "node_modules")

ts_project(
    name = "lib",
    srcs = glob(
        ["src/**/*.ts"],
        exclude = ["src/**/*.test.ts"],
    ),
    declaration = True,
    out_dir = "dist",
    root_dir = "src",
    tsconfig = "tsconfig.json",
    visibility = ["//visibility:public"],
    deps = [
        ":node_modules/@pulumi/gcp",
        ":node_modules/@pulumi/pulumi",
        ":node_modules/@pulumi/random",
    ],
)

npm_package(
    name = "pkg",
    srcs = [
        "package.json",
        ":lib",
    ],
    visibility = ["//visibility:public"],
)
