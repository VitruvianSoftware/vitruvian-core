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

load("//tools/pytest:defs.bzl", "py_test")

# gazelle:ignore

py_test(
    name = "setup_go_cache_key_test",
    size = "small",
    srcs = [
        "cache_key.py",
        "setup_go_cache_key_test.py",
    ],
    # pytest skips directories whose name starts with a dot (.github), so name
    # the file, or it collects nothing and fails with exit code 5.
    args = ["$(rootpath setup_go_cache_key_test.py)"],
    data = [
        "action.yml",
        "//:.github/workflows/go-cache.yaml",
    ],
    env = {
        "SETUP_GO_ACTION_PATH": "$(rootpath action.yml)",
        "GO_CACHE_WORKFLOW_PATH": "$(rootpath //:.github/workflows/go-cache.yaml)",
    },
    deps = ["@pip//pyyaml"],
)

py_test(
    name = "go_cache_consistency_test",
    size = "small",
    srcs = [
        "cache_key.py",
        "go_cache_consistency_test.py",
    ],
    # pytest skips directories whose name starts with a dot (.github), so name
    # the file, or it collects nothing and fails with exit code 5.
    args = ["$(rootpath go_cache_consistency_test.py)"],
    data = [
        "action.yml",
        "//:go.mod",
        "//:workflow_files",
        "//apps/cli/vitruvian-devx:go.mod",
        "//apps/cli/vitruvian-devx:go.sum",
        "//apps/suites/vitruvian-tabs/infra/app:go.sum",
        "//infrastructure/pulumi/platform/pagerduty:go.mod",
        "//infrastructure/pulumi/platform/pagerduty:go.sum",
        "//infrastructure/pulumi/platform/sentry:go.mod",
        "//infrastructure/pulumi/platform/sentry:go.sum",
        "//infrastructure/pulumi/platform/sentry-pagerduty:go.sum",
        "//infrastructure/pulumi/platform/stripe:go.mod",
        "//infrastructure/pulumi/platform/stripe:go.sum",
        "//packages/pulumi/examples:go-foundation/1-org/modules/go.sum",
    ],
    env = {
        "SETUP_GO_ACTION_PATH": "$(rootpath action.yml)",
        "WORKFLOW_FILES": "$(rootpaths //:workflow_files)",
    },
)

py_test(
    name = "setup_go_key_repro_test",
    size = "small",
    srcs = [
        "cache_key.py",
        "setup_go_key_repro_test.py",
    ],
    args = [
        "-s",
        "$(rootpath setup_go_key_repro_test.py)",
    ],
    tags = [
        "local",
        "manual",
    ],
)
