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

# //mobile/android/remote/macagent: the Mac half of Vitruvian Remote.
#
# A read-only Go daemon serving the machine's metrics over HTTP. Lives under
# the app it serves so it inherits the app's CODEOWNERS and the inter-app
# boundary (#82): nothing outside //mobile/android/remote may depend on it.
#
# gazelle manages the go_* rules; the rest is hand-authored.
# gazelle:go_visibility //mobile/android/remote:__subpackages__

load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

go_library(
    name = "macagent_lib",
    srcs = [
        "main.go",
        "sampler.go",
        "server.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/mobile/android/remote/macagent",
    visibility = ["//mobile/android/remote:__subpackages__"],
    deps = ["//mobile/android/remote/macagent/metrics"],
)

go_binary(
    name = "macagent",
    embed = [":macagent_lib"],
    visibility = ["//mobile/android/remote:__subpackages__"],
)

# `bazel run //mobile/android/remote/macagent:install` -- install the agent
# the repo just built as a login item for the current user. No sudo; it is a
# user LaunchAgent because nothing it reads needs root. The script proves the
# agent answers before it reports success.
sh_binary(
    name = "install",
    srcs = ["install.sh"],
    data = [
        "com.vitruvian.remote-agent.plist",
        ":macagent",
    ],
)

# The parsers are pure and pinned by fixtures, so this runs on Linux. What
# the Linux runner cannot check is the macOS commands themselves; that needs
# `bazel run` on a Mac and a curl, and the README says so.
pipeline_unit(
    name = "remote-mac-agent",
    persona = "backend",
    runner = "ubuntu-latest",
    test_targets = ["//mobile/android/remote/macagent/..."],
    tier = "L1",
    timeout_minutes = 10,
)

go_test(
    name = "macagent_test",
    srcs = ["server_test.go"],
    embed = [":macagent_lib"],
    deps = ["//mobile/android/remote/macagent/metrics"],
)
