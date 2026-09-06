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

# The repo version-conformance checker: `bazel run //tools/conformance:check`.

# Guards the shared Maven lock file against placeholder-version artifacts --
# published jars that deliberately contain no classes. See
# no_empty_placeholder_jars.sh for the full rationale; in short, one of these
# silently shipped an Android APK that crashed on launch on every device while
# every CI lane stayed green.

load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_test(
    name = "no_empty_placeholder_jars",
    size = "small",
    srcs = ["no_empty_placeholder_jars.sh"],
    data = ["//:maven_install.json"],
    env = {
        "LOCK_FILE": "$(rlocationpath //:maven_install.json)",
    },
    deps = ["@bazel_tools//tools/bash/runfiles"],
)
