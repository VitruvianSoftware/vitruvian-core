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

# gazelle:ignore

load("@rules_python//python:defs.bzl", "py_binary")

package(default_visibility = ["//packages/design-system-android:__subpackages__"])

# Emits VitruvianTokens.kt from //packages/design-system's tokens.json.
#
# `bazel run //packages/design-system-android/tools:gen_tokens -- \
#   --tokens packages/design-system/src/tokens.json \
#   --header packages/design-system-android/tools/kt_license_header.txt \
#   --out packages/design-system-android/src/main/kotlin/dev/vitruvian/design/VitruvianTokens.kt`
py_binary(
    name = "gen_tokens",
    srcs = ["gen_tokens.py"],
    data = ["kt_license_header.txt"],
    visibility = ["//visibility:public"],
)

exports_files([
    "gen_tokens.py",
    "kt_license_header.txt",
    "tokens_are_current.sh",
])
