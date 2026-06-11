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

# Platform config_settings + aliases for hermetic test-service binaries
# (PostgreSQL from theseus-rs/postgresql-binaries; see MODULE.bazel).

config_setting(
    name = "linux_amd64",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
)

config_setting(
    name = "linux_arm64",
    constraint_values = [
        "@platforms//cpu:arm64",
        "@platforms//os:linux",
    ],
)

config_setting(
    name = "darwin_amd64",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:macos",
    ],
)

config_setting(
    name = "darwin_arm64",
    constraint_values = [
        "@platforms//cpu:arm64",
        "@platforms//os:macos",
    ],
)

_PG_SELECT = {
    ":darwin_amd64": "@postgresql_darwin_amd64",
    ":darwin_arm64": "@postgresql_darwin_arm64",
    ":linux_amd64": "@postgresql_linux_amd64",
    ":linux_arm64": "@postgresql_linux_arm64",
}

[
    alias(
        name = alias_name,
        actual = select({k: v + "//:" + tgt for k, v in _PG_SELECT.items()}),
        visibility = ["//visibility:public"],
    )
    for alias_name, tgt in [
        ("pg_dist", "dist"),
        ("pg_initdb_bin", "initdb_bin"),
        ("pg_postgres_bin", "postgres_bin"),
        ("pg_isready_bin", "pg_isready_bin"),
    ]
]

exports_files(["playwright-browsers-1.57.0.json"])

exports_files(["patches/redis-atomic-fnptr-clang15.patch"])
