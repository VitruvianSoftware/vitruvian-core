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

"""Android Wireless Debugging auto-discovery and connection tool."""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library", "py_test")

py_library(
    name = "lib",
    srcs = ["adb_connect.py"],
    imports = ["."],
    visibility = ["//visibility:public"],
)

py_binary(
    name = "adb-connect",
    srcs = ["adb_connect.py"],
    imports = ["."],
    main = "adb_connect.py",
    visibility = ["//visibility:public"],
    deps = [":lib"],
)

alias(
    name = "adb_connect",
    actual = ":adb-connect",
    visibility = ["//visibility:public"],
)

py_test(
    name = "adb_connect_test",
    size = "small",
    srcs = ["adb_connect_test.py"],
    imports = ["."],
    main = "adb_connect_test.py",
    deps = [
        ":lib",
    ],
)
