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

# Two kinds of test, deliberately:
#
#   main_test.go   — HERMETIC. Golden files, determinism, the kill switch, the
#                    Phase-1 job shape. `data` carries frozen fixture
#                    declarations, so a BUILD change elsewhere in the repo
#                    cannot flip these.
#   parity_test.go — DELIBERATELY NOT hermetic. It compares the REAL generated
#                    delivery.yaml against the REAL legacy workflow it took the
#                    development lane from; freezing copies of those two would
#                    let them drift apart while the guard stayed green, which
#                    is the failure it exists to catch (spec §6, Phase 1).
#                    Both are exported by the ROOT BUILD (.github/ has no
#                    package of its own) and reached by the relative path
#                    "../../../.github/workflows/..." — rules_go runs a test
#                    from its own package dir, so that path resolves against
#                    the runfiles tree here and against the checkout under a
#                    plain `GOWORK=off go test ./...`.
go_test(
    name = "gen_test",
    size = "small",
    srcs = [
        "main_test.go",
        "parity_test.go",
    ],
    data = glob(["testdata/**"]) + [
        # The whole workflow surface and every composite action, so the Phase-3
        # guards can prove what they claim: every `uses:` resolves, every
        # `with:` key is declared by its callee, and no workflow actively
        # references one of the eight deleted per-app lanes. A hand-listed
        # subset would make the "no workflow references a deleted one" scan
        # vacuous for any file not on the list.
        "//:composite_actions",
        "//:workflow_files",
        # The scripts the generated workflow shells out to: a `run:` naming a
        # missing file is a failed job, and for a soak gate that is a blocked
        # promotion.
        "//tabula/extension:publish-dev-latest.sh",
        "//tools/charts:publish.sh",
        "//tabula/infra/app:cmd/revname/main.go",
        "//tools/ci:require-dev-soak.sh",
        "//tools/ci:resolve-deploy-base.sh",
    ],
    embed = [":gen_lib"],
)
