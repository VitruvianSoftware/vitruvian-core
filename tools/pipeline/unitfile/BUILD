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

# Hand-written: gazelle would not generate the Rust targets.
# gazelle:ignore

load("@rules_go//go:def.bzl", "go_library", "go_test")
load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

go_library(
    name = "unitfile",
    srcs = [
        "scan.go",
        "unitfile.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/pipeline/unitfile",
    visibility = ["//tools/pipeline:__subpackages__"],
)

go_test(
    name = "unitfile_test",
    srcs = ["unitfile_test.go"],
    embed = [":unitfile"],
)

# The Rust port, for the Rust planner and verified-run. The Go library stays
# for //tools/pipeline/gen. src/gocompat holds the Go behaviour (quoting,
# flags, os/exec and encoding/json wording) both Rust tools reproduce.
# Optimised in every build mode.
rust_library(
    name = "unitfile_rs_lib",
    srcs = glob(["src/**/*.rs"]),
    crate_name = "unitfile",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//tools/pipeline:__subpackages__"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

# unitfile_test.go's cases, plus every BUILD file in the repo that declared a
# unit when this was written (testdata/real_units).
rust_test(
    name = "unitfile_rs_lib_test",
    size = "small",
    crate = ":unitfile_rs_lib",
    data = [":real_units"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Every BUILD file in the repo that declared a pipeline_unit when the Rust
# port was written, as <path with / as __>.txt. The plan parity test lays
# them out as a repo and runs both planners over it.
filegroup(
    name = "real_units",
    srcs = glob(["testdata/real_units/*"]),
    visibility = ["//tools/pipeline:__subpackages__"],
)
