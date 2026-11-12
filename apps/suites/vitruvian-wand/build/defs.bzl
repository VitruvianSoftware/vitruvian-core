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

"""Transition rules and macros that build Vitruvian Wand targets with Rust 1.98.1."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(
    "@rules_rust//rust:defs.bzl",
    "rust_binary",
    "rust_clippy",
    "rust_library",
    "rust_shared_library",
    "rust_test",
)
load(
    "@rules_rust//rust:rust_common.bzl",
    "BuildInfo",
    "CrateGroupInfo",
    "CrateInfo",
    "DepInfo",
    "TestCrateInfo",
)

_FLAG = "//apps/desktop/vitruvian-courier/libsignal:rust_1_98_1"
_ENABLED = "//apps/suites/vitruvian-wand:rust_1_98_1_enabled"

# Inner targets are only compatible once transitioned onto Rust 1.98.1 so
# direct un-transitioned builds fail fast instead of using Rust 1.75.0.
ONLY_UNDER_VITRUVIAN_WAND_RUST = select({
    _ENABLED: [],
    "//conditions:default": ["@platforms//:incompatible"],
})

def _vitruvian_vitruvian_wand_rust_transition_impl(_settings, _attr):
    return {_FLAG: True}

_vitruvian_vitruvian_wand_rust_transition = transition(
    implementation = _vitruvian_vitruvian_wand_rust_transition_impl,
    inputs = [],
    outputs = [_FLAG],
)

# testing.TestEnvironment() constructs a RunEnvironmentInfo instance, so
# forwarding RunEnvironmentInfo, InstrumentedFilesInfo, and testing.ExecutionInfo
# preserves all test environment and coverage metadata across the transition.
_FORWARDED_PROVIDERS = [
    CcInfo,
    CrateInfo,
    DepInfo,
    BuildInfo,
    CrateGroupInfo,
    TestCrateInfo,
    OutputGroupInfo,
    RunEnvironmentInfo,
    InstrumentedFilesInfo,
    testing.ExecutionInfo,
]

def _forward_providers(dep, default_info):
    providers = [default_info]
    for p in _FORWARDED_PROVIDERS:
        if p in dep:
            providers.append(dep[p])
    return providers

def _with_vitruvian_vitruvian_wand_rust_impl(ctx):
    dep = ctx.attr.dep[0]
    default_info = DefaultInfo(
        files = dep[DefaultInfo].files,
        runfiles = dep[DefaultInfo].default_runfiles,
    )
    return _forward_providers(dep, default_info)

with_vitruvian_wand_rust = rule(
    doc = "Builds `dep` and its transitive dependencies under the Rust 1.98.1 toolchain.",
    implementation = _with_vitruvian_vitruvian_wand_rust_impl,
    attrs = {
        "dep": attr.label(cfg = _vitruvian_vitruvian_wand_rust_transition, mandatory = True),
    },
)

def _with_vitruvian_vitruvian_wand_rust_binary_impl(ctx):
    dep = ctx.attr.dep[0]
    src_exe = dep[DefaultInfo].files_to_run.executable
    out = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = out,
        target_file = src_exe,
        is_executable = True,
    )
    default_info = DefaultInfo(
        executable = out,
        files = depset([out]),
        runfiles = ctx.runfiles(files = [out]).merge(dep[DefaultInfo].default_runfiles),
    )
    return _forward_providers(dep, default_info)

with_vitruvian_vitruvian_wand_rust_binary = rule(
    doc = "Builds an executable `dep` under the Rust 1.98.1 toolchain.",
    implementation = _with_vitruvian_vitruvian_wand_rust_binary_impl,
    executable = True,
    attrs = {
        "dep": attr.label(cfg = _vitruvian_vitruvian_wand_rust_transition, mandatory = True),
    },
)

with_vitruvian_vitruvian_wand_rust_test = rule(
    doc = "Builds and runs a `rust_test` `dep` under the Rust 1.98.1 toolchain.",
    implementation = _with_vitruvian_vitruvian_wand_rust_binary_impl,
    test = True,
    attrs = {
        "dep": attr.label(cfg = _vitruvian_vitruvian_wand_rust_transition, mandatory = True),
    },
)

def _inner_compatible(target_compatible_with):
    if target_compatible_with == None:
        return ONLY_UNDER_VITRUVIAN_WAND_RUST
    return ONLY_UNDER_VITRUVIAN_WAND_RUST + target_compatible_with

def _inner_tags(tags):
    result = list(tags) if tags else []
    if "manual" not in result:
        result.append("manual")
    return result

def _inner_label(label):
    if label.endswith("_vitruvian_vitruvian_wand_rust_inner"):
        return label
    return label + "_vitruvian_vitruvian_wand_rust_inner"

def vitruvian_wand_rust_library(
        name,
        crate_name = None,
        edition = "2024",
        target_compatible_with = None,
        visibility = None,
        tags = None,
        testonly = None,
        **kwargs):
    """Defines a `rust_library` built with Vitruvian Wand's Rust 1.98.1 toolchain."""
    inner = name + "_vitruvian_vitruvian_wand_rust_inner"
    rust_library(
        name = inner,
        crate_name = crate_name or name.replace("-", "_"),
        edition = edition,
        target_compatible_with = _inner_compatible(target_compatible_with),
        tags = _inner_tags(tags),
        testonly = testonly,
        visibility = ["//visibility:private"],
        **kwargs
    )
    with_vitruvian_wand_rust(
        name = name,
        dep = ":" + inner,
        target_compatible_with = target_compatible_with,
        tags = tags,
        testonly = testonly,
        visibility = visibility,
    )

def vitruvian_wand_rust_binary(
        name,
        edition = "2024",
        target_compatible_with = None,
        visibility = None,
        tags = None,
        testonly = None,
        **kwargs):
    """Defines a `rust_binary` built with Vitruvian Wand's Rust 1.98.1 toolchain."""
    inner = name + "_vitruvian_vitruvian_wand_rust_inner"
    rust_binary(
        name = inner,
        edition = edition,
        target_compatible_with = _inner_compatible(target_compatible_with),
        tags = _inner_tags(tags),
        testonly = testonly,
        visibility = ["//visibility:private"],
        **kwargs
    )
    with_vitruvian_vitruvian_wand_rust_binary(
        name = name,
        dep = ":" + inner,
        target_compatible_with = target_compatible_with,
        tags = tags,
        testonly = testonly,
        visibility = visibility,
    )

def vitruvian_wand_rust_shared_library(
        name,
        crate_name = None,
        edition = "2024",
        target_compatible_with = None,
        visibility = None,
        tags = None,
        testonly = None,
        **kwargs):
    """Defines a `rust_shared_library` built with Vitruvian Wand's Rust 1.98.1 toolchain."""
    inner = name + "_vitruvian_vitruvian_wand_rust_inner"
    rust_shared_library(
        name = inner,
        crate_name = crate_name or name.replace("-", "_"),
        edition = edition,
        target_compatible_with = _inner_compatible(target_compatible_with),
        tags = _inner_tags(tags),
        testonly = testonly,
        visibility = ["//visibility:private"],
        **kwargs
    )
    with_vitruvian_wand_rust(
        name = name,
        dep = ":" + inner,
        target_compatible_with = target_compatible_with,
        tags = tags,
        testonly = testonly,
        visibility = visibility,
    )

def vitruvian_wand_rust_test(
        name,
        crate_name = None,
        edition = "2024",
        target_compatible_with = None,
        visibility = None,
        tags = None,
        **kwargs):
    """Defines a `rust_test` built with Vitruvian Wand's Rust 1.98.1 toolchain."""
    inner = name + "_vitruvian_vitruvian_wand_rust_inner"
    wrapper_kwargs = {
        k: kwargs[k]
        for k in ["size", "timeout", "flaky", "local", "shard_count", "args"]
        if k in kwargs
    }
    if crate_name != None:
        kwargs["crate_name"] = crate_name
    elif "crate" not in kwargs:
        kwargs["crate_name"] = name.replace("-", "_")
    rust_test(
        name = inner,
        edition = edition,
        target_compatible_with = _inner_compatible(target_compatible_with),
        tags = _inner_tags(tags),
        visibility = ["//visibility:private"],
        **kwargs
    )
    with_vitruvian_vitruvian_wand_rust_test(
        name = name,
        dep = ":" + inner,
        target_compatible_with = target_compatible_with,
        tags = tags,
        visibility = visibility,
        **wrapper_kwargs
    )

def vitruvian_wand_rust_clippy(
        name,
        deps = [],
        target_compatible_with = None,
        visibility = None,
        tags = None,
        testonly = True,
        **kwargs):
    """Defines a `rust_clippy` target built with Vitruvian Wand's Rust 1.98.1 toolchain."""
    inner = name + "_vitruvian_vitruvian_wand_rust_inner"
    rust_clippy(
        name = inner,
        deps = [_inner_label(d) for d in deps],
        target_compatible_with = _inner_compatible(target_compatible_with),
        tags = _inner_tags(tags),
        testonly = testonly,
        visibility = ["//visibility:private"],
        **kwargs
    )
    with_vitruvian_wand_rust(
        name = name,
        dep = ":" + inner,
        target_compatible_with = target_compatible_with,
        tags = tags,
        testonly = testonly,
        visibility = visibility,
    )
