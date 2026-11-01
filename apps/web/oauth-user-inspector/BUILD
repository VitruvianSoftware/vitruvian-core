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

# oauth-user-inspector: a Vite/React frontend + Rust backend served as one
# container (see Dockerfile + oauth-user-inspector/infra/app for the
# Cloud Run deploy). The production frontend build runs via pnpm/vite (the monorepo
# does not bazel-build frontends — cf. tabula/web); bazel builds and tests the
# Rust server and helper suites in CI. gazelle:ignore stops the JS/TS extension
# from rewriting this hand-authored file.
# gazelle:ignore
# gazelle:exclude frontend
# gazelle:exclude server
# gazelle:exclude scripts
# gazelle:exclude dist
# gazelle:exclude dist-server
# infra/ holds the per-app Pulumi deployment stacks (standalone Go modules run
# by the Pulumi CLI via //tools/pulumi wrappers, never Bazel-built — same rule
# as the root `gazelle:exclude infrastructure`). Keep gazelle out of them.
# gazelle:exclude infra

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//apps/web/oauth-user-inspector/infra/app:smoke.bzl", "OAUTH_SMOKE")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

package(default_visibility = ["//apps/web/oauth-user-inspector:__subpackages__"])

rust_library(
    name = "oauth_server_lib",
    srcs = [
        "server/src/api_endpoints.rs",
        "server/src/lib.rs",
        "server/src/logger.rs",
        "server/src/oauth_error_guide.rs",
        "server/src/oauth_session.rs",
        "server/src/rate_limit.rs",
        "server/src/safe_fetch.rs",
        "server/src/security_headers.rs",
        "server/src/server.rs",
        "server/src/userinfo_request.rs",
    ],
    crate_name = "oauth_server_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "oauth-user-inspector-server",
    srcs = ["server/src/bin/server.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":oauth_server_lib"],
)

alias(
    name = "oauth_user_inspector_server",
    actual = ":oauth-user-inspector-server",
)

# Server + pure-helper unit test suite (migrated from ts-jest to native Rust).
rust_test(
    name = "unit_tests",
    size = "small",
    crate = ":oauth_server_lib",
    data = [
        # Read at runtime by explore_endpoints_parity to assert the UI
        # endpoint catalog matches the server's fail-closed /api/explore table.
        "frontend/utils/apiEndpoints.ts",
        # Read at runtime by dependency_consistency to assert react & @types/react
        # share the same major version.
        "package.json",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Developer-environment check: `bazel run //oauth-user-inspector:doctor`.
doctor(
    name = "doctor",
    label = "oauth-user-inspector",
    optional = [
        "docker",
        "gcloud",
    ],
    required = [
        "bazel",
        "node",
        "pnpm",
        "git",
    ],
)

rust_library(
    name = "oauth_scripts_lib",
    srcs = [
        "scripts/src/check_sensitive.rs",
        "scripts/src/deploy.rs",
        "scripts/src/lib.rs",
        "scripts/src/setup_dev.rs",
        "scripts/src/smoke.rs",
        "scripts/src/start.rs",
    ],
    crate_name = "oauth_scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_test(
    name = "oauth_scripts_lib_test",
    size = "small",
    crate = ":oauth_scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "check-sensitive",
    srcs = ["scripts/src/bin/check_sensitive.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":oauth_scripts_lib"],
)

# The candidate smoke //tools/deploy runs against each new revision
# (infra/app/BUILD's :deploy and the delivery workflow both call it).
rust_binary(
    name = "smoke",
    srcs = ["scripts/src/bin/smoke.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":oauth_scripts_lib"],
)

# :smoke end to end against stub curl/Chrome (expectations: the replaced smoke.sh).
rust_test(
    name = "smoke_test",
    size = "small",
    srcs = ["scripts/tests/smoke_test.rs"],
    data = [":smoke"],
    edition = "2021",
    env = {"SMOKE_BIN": "$(rootpath :smoke)"},
)

# :smoke the way a deploy runs it: through the real //tools/deploy:cloud-run
# --phase smoke, with the command :deploy and the delivery unit share.
rust_test(
    name = "deploy_smoke_test",
    size = "small",
    srcs = ["scripts/tests/deploy_smoke_test.rs"],
    data = [
        ":smoke",
        "//tools/deploy:cloud-run",
    ],
    edition = "2021",
    env = {
        "CLOUD_RUN_BIN": "$(rootpath //tools/deploy:cloud-run)",
        # `$$`: Bazel expands make variables in env values.
        "OAUTH_SMOKE": OAUTH_SMOKE.replace("$", "$$"),
        "SMOKE_BIN": "$(rootpath :smoke)",
    },
)

rust_binary(
    name = "start",
    srcs = ["scripts/src/bin/start.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":oauth_scripts_lib"],
)

# The container entrypoint end to end: `start` in the runtime image's /app
# layout must exec the native server and answer on $PORT (#4041).
rust_test(
    name = "start_test",
    size = "small",
    srcs = ["scripts/tests/start_test.rs"],
    data = [
        ":oauth-user-inspector-server",
        ":start",
    ],
    edition = "2021",
    env = {
        "SERVER_BIN": "$(rootpath :oauth-user-inspector-server)",
        "START_BIN": "$(rootpath :start)",
    },
)

rust_binary(
    name = "deploy-cloudbuild",
    srcs = ["scripts/src/bin/deploy.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":oauth_scripts_lib"],
)

alias(
    name = "deploy_cloudbuild",
    actual = ":deploy-cloudbuild",
)

rust_binary(
    name = "setup-dev",
    srcs = ["scripts/src/bin/setup_dev.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":oauth_scripts_lib"],
)

alias(
    name = "setup_dev",
    actual = ":setup-dev",
)

test_suite(
    name = "check-sensitive_test",
    tests = [":oauth_scripts_lib_test"],
)

alias(
    name = "check_sensitive_test",
    actual = ":check-sensitive_test",
)

pipeline_unit(
    name = "oauth-user-inspector",
    persona = "all",
    runner = "ubuntu-26.04",
    test_targets = [
        ":oauth_scripts_lib_test",
        ":deploy_smoke_test",
        ":smoke_test",
        ":start_test",
        ":unit_tests",
        # cloud_run_deploy's launcher check: the real :deploy reaches the sequencer.
        "//apps/web/oauth-user-inspector/infra/app:deploy_launcher_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
