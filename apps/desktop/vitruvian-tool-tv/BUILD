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

"""Vitruvian TV extension (dev.vitruvian.tv) for Sony Google TV control over ADB."""

# gazelle:ignore
# gazelle:exclude bin

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@bazel_lib//lib:copy_to_directory.bzl", "copy_to_directory")

package(default_visibility = ["//apps/desktop/vitruvian-tool-tv:__subpackages__"])

copy_to_directory(
    name = "tool-folder",
    srcs = [
        "bin/tool.py",
        "vitruvian-tool.json",
        "//packages/vitruvian-sdk:vitruvian_tool_kit",
    ],
    out = "built/vitruvian-tv",
    replace_prefixes = {
        "apps/desktop/vitruvian-tool-tv/": "",
        "kits/python/vitruvian_tool_kit/": "lib/vitruvian_tool_kit/",
        "packages/vitruvian-sdk/kits/python/vitruvian_tool_kit/": "lib/vitruvian_tool_kit/",
    },
    visibility = ["//visibility:public"],
)

py_test(
    name = "vitruvian_tv_test",
    size = "small",
    srcs = ["vitruvian_tv_test.py"],
    args = [
        "$(rootpath :tool-folder)/vitruvian-tool.json",
        "$(rootpath //packages/vitruvian-sdk:conformance/conformance.py)",
    ],
    data = [
        ":tool-folder",
        "//packages/vitruvian-sdk:conformance/conformance.py",
    ],
    main = "vitruvian_tv_test.py",
)
