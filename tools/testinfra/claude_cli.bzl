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

"""Pins the Claude Code CLI that runs plugin tests.

Only the current machine's build is downloaded. A plain http_archive per
platform would make CI's `bazel query deps(...)` fetch all of them (about
170 MB each), because a query follows every branch of a select().
"""

_VERSION = "2.1.331"

# `dist.integrity` from the npm registry for each platform package.
_INTEGRITY = {
    "darwin-arm64": "sha512-SVQmG05M7G/Lrbr3qUXDQXaV6+jEHudR9rSdsGjM0/zBjbZJh/mC812DwT3rHCA8rGlPC+HLfTwbvqmNQWNJZw==",
    "darwin-x64": "sha512-9UUbpdtrFXfQWXACwblqvPfKz5ZdtOtbiiwbRY3h1pzrqGcimLbUJUZty/SsHOXaTqSJQzFTuO6iSqZITyFKXQ==",
    "linux-arm64": "sha512-zy+OOB7i1J7rCjNoPB2ZBD7EAtT0Eus1wH+toklZGL2XpwHyw+POGUGOpEBBE6xe5EkAYWXzFSTQ3uD8UtWlRg==",
    "linux-x64": "sha512-IpvZ9c/NopO/sr8ThWLVAUDXVAFT3auLWrhbR6wq1dgkuJfZYdTtoXf6GajE5KL9R58iTt/86OPXrJAsM4+l8g==",
}

def _host_platform(rctx):
    name = rctx.os.name.lower()
    system = "darwin" if name.startswith("mac") else "linux" if name.startswith("linux") else name
    arch = {"aarch64": "arm64", "arm64": "arm64", "amd64": "x64", "x86_64": "x64"}.get(rctx.os.arch, rctx.os.arch)
    return "%s-%s" % (system, arch)

def _claude_cli_impl(rctx):
    platform = _host_platform(rctx)
    if platform not in _INTEGRITY:
        fail("No pinned Claude Code CLI for %s. Pinned: %s" % (platform, sorted(_INTEGRITY)))
    rctx.download_and_extract(
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code-{p}/-/claude-code-{p}-{v}.tgz".format(
            p = platform,
            v = _VERSION,
        ),
        integrity = _INTEGRITY[platform],
        stripPrefix = "package",
    )
    rctx.file("BUILD.bazel", 'exports_files(["claude"], visibility = ["//visibility:public"])\n')

claude_cli = repository_rule(
    implementation = _claude_cli_impl,
    doc = "The Claude Code CLI for the host platform, pinned by checksum.",
)
