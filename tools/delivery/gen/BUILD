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

# The delivery workflow generator (spec §4.3). Run it as //tools/ci:gen (the
# alias the spec and tidy-check name); this is the implementation.
#
#   bazel run //tools/ci:gen
#
# Public visibility is required by the //tools/ci:gen alias, which lives in a
# different package.

load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "gen_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/delivery/gen",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "gen",
    embed = [":gen_lib"],
    visibility = ["//visibility:public"],
)

# Golden-file + determinism + kill-switch tests. `data` carries the fixture
# declarations and the golden; the test never reads the live tree, so a BUILD
# change elsewhere in the repo cannot flip it.
go_test(
    name = "gen_test",
    size = "small",
    srcs = ["main_test.go"],
    data = glob(["testdata/**"]),
    embed = [":gen_lib"],
)
