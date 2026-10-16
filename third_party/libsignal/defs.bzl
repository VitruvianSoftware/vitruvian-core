# Upstream: https://github.com/signalapp/libsignal (AGPL-3.0-only); this file
# is build glue for it, under the same licence.
# SPDX-License-Identifier: AGPL-3.0-only
"""Rules that build libsignal_ffi with its own Rust toolchain."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_FLAG = "//third_party/libsignal:rust_1_98_1"

def _rust_1_98_1_transition_impl(_settings, _attr):
    return {_FLAG: True}

_rust_1_98_1_transition = transition(
    implementation = _rust_1_98_1_transition_impl,
    inputs = [],
    outputs = [_FLAG],
)

def _with_rust_1_98_1_impl(ctx):
    dep = ctx.attr.dep[0]
    return [dep[CcInfo], dep[DefaultInfo]]

with_rust_1_98_1 = rule(
    doc = """Builds `dep` (and everything under it) with libsignal's Rust 1.98.1.

The toolchain is chosen by //third_party/libsignal:rust_1_98_1, which only this
rule sets, so the rest of the repository keeps the default Rust toolchain.
Forwards the dep's CcInfo so a cc_library can depend on the result.""",
    implementation = _with_rust_1_98_1_impl,
    attrs = {
        "dep": attr.label(cfg = _rust_1_98_1_transition, mandatory = True, providers = [CcInfo]),
    },
)

def _owned_static_libs(cc_info, names):
    libs = {}
    for linker_input in cc_info.linking_context.linker_inputs.to_list():
        if linker_input.owner.name not in names:
            continue
        for lib in linker_input.libraries:
            archive = lib.static_library or lib.pic_static_library
            if archive:
                libs[linker_input.owner.name] = archive
    return libs

def _boringssl_prefix_impl(ctx):
    crypto = ctx.attr.crypto[CcInfo]
    ssl = ctx.attr.ssl[CcInfo]
    libs = _owned_static_libs(crypto, ["crypto_internal"])
    libs.update(_owned_static_libs(ssl, ["ssl_internal"]))
    if sorted(libs.keys()) != ["crypto_internal", "ssl_internal"]:
        fail("expected BoringSSL's crypto_internal and ssl_internal archives, found %s" % sorted(libs.keys()))

    headers = (crypto.compilation_context.direct_public_headers +
               ssl.compilation_context.direct_public_headers)

    out = ctx.actions.declare_directory(ctx.label.name)
    commands = [
        'mkdir -p "$OUT/lib" "$OUT/include"',
        'cp "{}" "$OUT/lib/libcrypto.a"'.format(libs["crypto_internal"].path),
        'cp "{}" "$OUT/lib/libssl.a"'.format(libs["ssl_internal"].path),
    ]
    for hdr in headers:
        idx = hdr.path.find("/include/")
        if idx < 0:
            fail("BoringSSL header outside include/: " + hdr.path)
        rel = hdr.path[idx + len("/include/"):]
        commands.append('mkdir -p "$OUT/include/{}" && cp "{}" "$OUT/include/{}"'.format(
            rel.rpartition("/")[0],
            hdr.path,
            rel,
        ))
    ctx.actions.run_shell(
        inputs = [libs["crypto_internal"], libs["ssl_internal"]] + headers,
        outputs = [out],
        command = "set -eu\nOUT=\"{}\"\n".format(out.path) + "\n".join(commands),
        mnemonic = "BoringSslPrefix",
        progress_message = "Laying out BoringSSL for boring-sys",
    )
    return [DefaultInfo(files = depset([out]))]

def _protoc_dist_impl(ctx):
    protoc = ctx.executable.protoc
    out = ctx.actions.declare_directory(ctx.label.name)
    commands = [
        'mkdir -p "$OUT/bin" "$OUT/include"',
        'cp "{}" "$OUT/bin/protoc"'.format(protoc.path),
    ]
    for proto in ctx.files.well_known_protos:
        idx = proto.path.find("/google/protobuf/")
        if idx < 0:
            fail("well-known proto outside google/protobuf/: " + proto.path)
        rel = proto.path[idx + 1:]
        commands.append('mkdir -p "$OUT/include/{}" && cp "{}" "$OUT/include/{}"'.format(
            rel.rpartition("/")[0],
            proto.path,
            rel,
        ))
    ctx.actions.run_shell(
        inputs = [protoc] + ctx.files.well_known_protos,
        outputs = [out],
        command = "set -eu\nOUT=\"{}\"\n".format(out.path) + "\n".join(commands),
        mnemonic = "ProtocDist",
        progress_message = "Laying out protoc for libsignal's build scripts",
    )
    return [DefaultInfo(files = depset([out]))]

protoc_dist = rule(
    doc = """protoc laid out like a release: bin/protoc and include/google/protobuf.

libsignal's build scripts find protoc two ways: prost-build reads $PROTOC,
protobuf-codegen searches $PATH. Both need the well-known types; protoc adds
<its dir>/../include to the import path by itself once that holds
google/protobuf/descriptor.proto. ($PROTOC_INCLUDE is deliberately not used:
prost-build would pass it as -I, which drops protoc's implicit "." and breaks
libsignal-message-backup's relative proto paths.)""",
    implementation = _protoc_dist_impl,
    attrs = {
        "protoc": attr.label(mandatory = True, executable = True, cfg = "exec"),
        "well_known_protos": attr.label_list(mandatory = True, allow_files = [".proto"]),
    },
)

boringssl_prefix = rule(
    doc = """Lays BoringSSL out the way boring-sys's BORING_BSSL_PATH expects.

One directory: lib/libcrypto.a, lib/libssl.a and include/openssl/*.h, built by
Bazel from @signal_boringssl. boring-sys then skips CMake and only runs bindgen
over the headers, linking the two archives.""",
    implementation = _boringssl_prefix_impl,
    attrs = {
        "crypto": attr.label(mandatory = True, providers = [CcInfo]),
        "ssl": attr.label(mandatory = True, providers = [CcInfo]),
    },
)
