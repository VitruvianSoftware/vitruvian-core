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

# //apps/mobile/android-remote/macagent: the Mac half of Vitruvian Remote.
#
# A read-only Rust daemon serving the machine's metrics over HTTP. Lives under
# the app it serves so it inherits the app's CODEOWNERS and the inter-app
# boundary (#82): nothing outside //apps/mobile/android-remote may depend on it.
#
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# `bazel run //apps/mobile/android-remote/macagent:install` -- install the agent
# the repo just built as a login item for the current user. No sudo; it is a
# user LaunchAgent because nothing it reads needs root. The script proves the
# agent answers before it reports success.
alias(
    name = "install",
    actual = ":install-rs",
)

# `bazel run //apps/mobile/android-remote/macagent:pair -- 482917` -- open a
# five-minute pairing window for the phone showing that code. Writes only to
# ~/.config/vitruvian-remote-agent; the installed agent picks it up with no
# restart, because it re-reads that directory on every request.
alias(
    name = "pair",
    actual = ":pair-rs",
)

# The parsers are pure and pinned by fixtures, so this runs on Linux. What
# the Linux runner cannot check is the macOS commands themselves; that needs
# `bazel run` on a Mac and a curl, and the README says so.
pipeline_unit(
    name = "remote-mac-agent",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = ["//apps/mobile/android-remote/macagent/..."],
    tier = "L1",
    timeout_minutes = 10,
)

rust_library(
    name = "macagent_scripts_lib",
    srcs = ["scripts/src/lib.rs"],
    crate_name = "macagent_scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/mobile/android-remote:__subpackages__"],
)

rust_binary(
    name = "install-rs",
    srcs = ["scripts/src/install_main.rs"],
    data = [
        "com.vitruvian.remote-agent.plist",
        ":macagent",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/mobile/android-remote:__subpackages__"],
    deps = [":macagent_scripts_lib"],
)

rust_binary(
    name = "pair-rs",
    srcs = ["scripts/src/pair_main.rs"],
    data = [":macagent"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/mobile/android-remote:__subpackages__"],
    deps = [":macagent_scripts_lib"],
)

rust_test(
    name = "macagent_scripts_lib_test",
    size = "small",
    crate = ":macagent_scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_library(
    name = "macagent_rs_lib",
    srcs = [
        "rs/src/antigravity.rs",
        "rs/src/exec.rs",
        "rs/src/homespeaker.rs",
        "rs/src/hook.rs",
        "rs/src/http_util.rs",
        "rs/src/lib.rs",
        "rs/src/mcp.rs",
        "rs/src/notify.rs",
        "rs/src/pair.rs",
        "rs/src/pairpage.rs",
        "rs/src/permission.rs",
        "rs/src/phone.rs",
        "rs/src/sampler.rs",
        "rs/src/server.rs",
        "rs/src/stream.rs",
        "rs/src/tailnet.rs",
        "rs/src/tv.rs",
    ],
    crate_name = "vitruvian_remote_macagent",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/mobile/android-remote:__subpackages__"],
    deps = ["//apps/mobile/android-remote/macagent/metrics:metrics_rs"],
)

alias(
    name = "macagent_lib",
    actual = ":macagent_rs_lib",
    visibility = ["//apps/mobile/android-remote:__subpackages__"],
)

rust_binary(
    name = "macagent",
    srcs = ["rs/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/mobile/android-remote:__subpackages__"],
    deps = [
        ":macagent_rs_lib",
        "//apps/mobile/android-remote/macagent/metrics:metrics_rs",
    ],
)

alias(
    name = "macagent-rs",
    actual = ":macagent",
    visibility = ["//apps/mobile/android-remote:__subpackages__"],
)

alias(
    name = "macagent_rs",
    actual = ":macagent",
    visibility = ["//apps/mobile/android-remote:__subpackages__"],
)

rust_test(
    name = "macagent_rs_test",
    size = "small",
    crate = ":macagent_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//apps/mobile/android-remote/macagent/metrics:metrics_rs"],
)

test_suite(
    name = "macagent_test",
    tests = [":macagent_rs_test"],
)
