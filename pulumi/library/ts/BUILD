load("@aspect_rules_js//npm:defs.bzl", "npm_link_all_packages")

# TypeScript arm of pulumi-library. Each component under packages/* is an
# independently published @vitruviansoftware/foundation-* npm package built by
# its own ts_project. This root is a private meta-package holding the shared
# tsconfig (extended by every package) and the vitest config; CI's gazelle (js)
# is the source of truth for the generated TS targets.

npm_link_all_packages(name = "node_modules")

# Exported so each package's tsconfig.json can `extends` this base.
exports_files(
    ["tsconfig.json"],
    visibility = ["//pulumi/library/ts:__subpackages__"],
)
