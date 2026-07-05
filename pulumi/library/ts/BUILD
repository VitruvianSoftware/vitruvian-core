load("@aspect_rules_js//npm:defs.bzl", "npm_package")

# Minimal packaging target for the private ts/ meta-package so aspect_rules_js
# can link it into the virtual store. See a package BUILD for context.
npm_package(
    name = "pkg",
    srcs = ["package.json"],
    visibility = ["//visibility:public"],
)
