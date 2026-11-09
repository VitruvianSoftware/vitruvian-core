# Copyright (c) 2026 VitruvianSoftware

"""Multi-ABI Android APK packaging transition for Wand (`arm64-v8a` + `armeabi-v7a`)."""

load("@rules_android//providers:providers.bzl", "ApkInfo")

def _multi_abi_android_transition_impl(_settings, _attr):
    return {
        "//command_line_option:android_platforms": [
            Label("@rules_android//:arm64-v8a"),
            Label("@rules_android//:armeabi-v7a"),
        ],
    }

_multi_abi_android_transition = transition(
    implementation = _multi_abi_android_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:android_platforms"],
)

def _wand_multi_abi_apk_impl(ctx):
    dep = ctx.attr.apk[0]
    apk_info = dep[ApkInfo]
    out_apk = ctx.outputs.out_apk
    ctx.actions.symlink(
        output = out_apk,
        target_file = apk_info.signed_apk,
    )
    return [
        DefaultInfo(files = depset([out_apk])),
        apk_info,
    ]

wand_multi_abi_apk = rule(
    implementation = _wand_multi_abi_apk_impl,
    attrs = {
        "apk": attr.label(
            mandatory = True,
            cfg = _multi_abi_android_transition,
            providers = [ApkInfo],
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    outputs = {
        "out_apk": "%{name}.apk",
    },
)
