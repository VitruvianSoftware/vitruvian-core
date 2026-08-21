# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# Configures npm trusted publishing for every publishable package in one pass.
# The npm UI re-challenges 2FA on page NAVIGATION, so doing this by hand costs
# ~62 hardware key touches; `npm trust` needs one.
sh_binary(
    name = "setup",
    srcs = ["setup.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "setup_test",
    size = "small",
    srcs = ["setup_test.sh"],
    args = ["$(location setup.sh)"],
    data = ["setup.sh"],
)

# Gives a never-published package its FIRST publish, then hands off to :setup.
# Trusted publishing attaches to a package that EXISTS, and the release workflow
# authenticates by OIDC alone -- so a brand-new name cannot be created by CI at
# all. Exactly one manual publish per package breaks that cycle.
sh_binary(
    name = "bootstrap",
    srcs = ["bootstrap.sh"],
    data = ["setup.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "bootstrap_test",
    size = "small",
    srcs = ["bootstrap_test.sh"],
    args = ["$(location bootstrap.sh)"],
    data = ["bootstrap.sh"],
)
