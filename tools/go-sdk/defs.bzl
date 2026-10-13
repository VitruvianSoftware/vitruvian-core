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

"""The registered Go SDK's own `go` command, as a file a test can run.

`@rules_go//go` is a runner for `bazel run`: it reads the workspace's go.work
and its modules before it starts `go`, so it fails inside a test's sandbox.
This hands a test the SDK's `go` itself, with the whole SDK in its runfiles.
The test sets GOROOT to the folder two above the file.
"""

def _go_sdk_go_impl(ctx):
    sdk = ctx.toolchains["@rules_go//go:toolchain"].sdk
    files = depset(
        [sdk.go, sdk.root_file],
        transitive = [sdk.libs, sdk.headers, sdk.srcs, sdk.tools],
    )
    return [DefaultInfo(
        files = depset([sdk.go]),
        runfiles = ctx.runfiles(transitive_files = files),
    )]

go_sdk_go = rule(
    implementation = _go_sdk_go_impl,
    toolchains = ["@rules_go//go:toolchain"],
    doc = "The registered Go SDK's `go` command, with the SDK in its runfiles.",
)
