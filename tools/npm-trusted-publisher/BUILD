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
