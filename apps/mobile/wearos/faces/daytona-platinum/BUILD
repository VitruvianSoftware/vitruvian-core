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

# //apps/mobile/wearos/faces/daytona-platinum: Rolex Cosmograph Daytona Platinum
# (Ref. 126506) Declarative Watch Face Format (WFF) package for Pixel Watch 4.
#
# gazelle:ignore

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pytest:defs.bzl", "py_test")

package(default_visibility = ["//apps/mobile/wearos:__subpackages__"])

filegroup(
    name = "wff_sources",
    srcs = glob([
        "src/main/AndroidManifest.xml",
        "src/main/res/**",
    ]),
)

py_test(
    name = "watchface_test",
    srcs = ["watchface_test.py"],
    data = [":wff_sources"],
)

sh_binary(
    name = "build_apk",
    srcs = ["scripts/build_wff_apk.sh"],
    data = [":wff_sources"],
)

sh_binary(
    name = "install",
    srcs = ["scripts/install.sh"],
    data = [
        "scripts/build_wff_apk.sh",
        ":wff_sources",
    ],
)

doctor(
    name = "doctor",
    label = "daytona-platinum (Wear OS Watch Face)",
    required = [
        "bazel",
        "git",
    ],
)
