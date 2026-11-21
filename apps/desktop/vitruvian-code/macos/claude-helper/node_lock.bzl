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

"""Expose rules_nodejs Darwin Node SHA-256 sums for node.lock verification."""

load("@rules_nodejs//nodejs/private:node_versions.bzl", "NODE_VERSIONS")

def _rules_nodejs_darwin_sums_impl(ctx):
    arm64 = {}
    amd64 = {}
    for key, val in NODE_VERSIONS.items():
        if key.endswith("-darwin_arm64"):
            ver = key[:-len("-darwin_arm64")]
            arm64[ver] = val[2]
        elif key.endswith("-darwin_amd64"):
            ver = key[:-len("-darwin_amd64")]
            amd64[ver] = val[2]

    out = {}
    for ver in sorted(arm64.keys()):
        if ver in amd64:
            out[ver] = {
                "darwin-arm64": arm64[ver],
                "darwin-x64": amd64[ver],
            }

    f = ctx.actions.declare_file(ctx.attr.name + ".json")
    ctx.actions.write(
        output = f,
        content = json.encode_indent(out, indent = "  ") + "\n",
    )
    return [DefaultInfo(files = depset([f]))]

rules_nodejs_darwin_sums = rule(
    implementation = _rules_nodejs_darwin_sums_impl,
    attrs = {},
)
