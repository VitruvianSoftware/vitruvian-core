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

# Shared library filegroups for infrastructure/pulumi sub-modules.
#
# The root infrastructure/pulumi/ directory is a namespace only — it no longer
# hosts a Pulumi project. The copybara sync auth functionality was consolidated
# into //infrastructure/pulumi/platform/repo_config.

# platform/pkg/secrets has no BUILD file of its own, so it's part of THIS package.
# Exported so sibling Pulumi projects whose go.mod has
# `replace .../pkg/secrets => ../pkg/secrets` (e.g. repo_config) can pull it
# into their pulumi_go_test() sandbox via extra_data — the replace directive
# resolves to a real path on disk, so `go test` needs the files there, not
# just the module declared.
filegroup(
    name = "pkg_secrets_files",
    srcs = glob(["platform/pkg/secrets/**"]),
    visibility = ["//visibility:public"],
)

# Same pattern for pkg/copybara_sync — repo_config's go.mod has
# `replace .../pkg/copybara_sync => ../../pkg/copybara_sync`.
filegroup(
    name = "pkg_copybara_sync_files",
    srcs = glob(["pkg/copybara_sync/**"]),
    visibility = ["//visibility:public"],
)
