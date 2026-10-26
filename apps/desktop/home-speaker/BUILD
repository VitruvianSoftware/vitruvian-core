load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("@build_bazel_rules_swift//swift:swift_binary.bzl", "swift_binary")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

swift_library(
    name = "HomeSpeakerCore",
    srcs = glob(["Sources/HomeSpeakerCore/**/*.swift"]),
    module_name = "HomeSpeakerCore",
    target_compatible_with = ["@platforms//os:macos"],
)

swift_library(
    name = "HomeSpeakerLib",
    srcs = glob(["Sources/HomeSpeaker/**/*.swift"]),
    module_name = "HomeSpeaker",
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":HomeSpeakerCore"],
)

swift_test(
    name = "HomeSpeakerTests",
    # The tool's tests are a target of their own, below: they link the
    # tool's core, which this target does not.
    srcs = glob(
        ["Tests/**/*.swift"],
        exclude = ["Tests/HomeSpeakerToolTests/**"],
    ),
    # ProductionReadinessTests reads these: no source ships a home-directory
    # path, and Info.plist tracks Version.swift.
    data = glob(["Sources/**/*.swift"]) + ["Resources/Info.plist"],
    # Never the real Beeper Desktop (23373): see scripts/test.sh.
    env = {"HOMESPEAKER_BEEPER_URL": "http://localhost:9"},
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":HomeSpeakerCore"],
)

# The HomeSpeaker tool for the Vitruvian app (docs/superpowers/plans/2026-10-12-vitruvian-tools-for-everyone-stage-f.md):
# a second door to this app. What it knows, apart from the link to the
# app: the settings file both share, HomeSpeaker's program and its flags,
# the two pages, and the state machine behind a link protocol, so the tests
# drive it without a process. It links the MIT kit and protocol
# (packages/vitruvian-sdk) and HomeSpeakerCore, for the settings' shape.
swift_library(
    name = "HomeSpeakerToolCore",
    srcs = glob(["Sources/HomeSpeakerToolCore/**/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "HomeSpeakerToolCore",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":HomeSpeakerCore",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

# Against a settings file in the temporary folder, a driver that answers
# itself and a link that records. Nothing here starts HomeSpeaker.
swift_test(
    name = "HomeSpeakerToolTests",
    size = "small",
    srcs = glob(["Tests/HomeSpeakerToolTests/**/*.swift"]),
    # Never the real Beeper Desktop (23373): see scripts/test.sh.
    env = {"HOMESPEAKER_BEEPER_URL": "http://localhost:9"},
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":HomeSpeakerCore",
        ":HomeSpeakerToolCore",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

# The tool's program: the kit's loop around HomeSpeakerToolCore, and
# nothing else.
swift_binary(
    name = "homespeaker-tool",
    srcs = glob(["Sources/HomeSpeakerTool/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "HomeSpeakerToolProgram",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":HomeSpeakerCore",
        ":HomeSpeakerToolCore",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

# The tool as a folder the app can add: the manifest and bin/tool, as the
# release zips them (scripts/publish.sh). Without google-oauth-client.json,
# which only the release's zip holds (scripts/zip-tool.sh): CI has no
# secrets, and the tests need no sign-in client.
#
#   bazel build --config=macos-app //apps/desktop/home-speaker:tool-folder
#
# leaves bazel-bin/apps/desktop/home-speaker/built/homespeaker/.
genrule(
    name = "tool-folder",
    srcs = [
        "tool/vitruvian-tool.json",
        ":homespeaker-tool",
    ],
    outs = [
        "built/homespeaker/vitruvian-tool.json",
        "built/homespeaker/bin/tool",
    ],
    cmd = "cp $(location tool/vitruvian-tool.json) $(RULEDIR)/built/homespeaker/vitruvian-tool.json && cp $(location :homespeaker-tool) $(RULEDIR)/built/homespeaker/bin/tool",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# The built folder through `vitruvian-tool validate` and the conformance
# script, in a scratch folder of its own: its home, its data folder
# (HOMESPEAKER_DATA_FOLDER), no HomeSpeaker app (HOMESPEAKER_PROGRAM empty)
# and messages under a prefix of its own. The program's `--where` must name
# that data folder first. Then the handshake, a command refused as not set
# up, an unknown command, the island panel opened and tapped, refusals, a
# status, and a clean exit. Then end to end over the same JSON-RPC: the
# island and all five settings sections drawn within the protocol's limits,
# changes read back from the settings and secrets files in the data folder,
# and the island's More settings button answered with `open` (a caption, and
# no `open`, for an app without ui.open.settings). Then none of the app's files in the scratch home's .gemini. Last,
# in a second scratch home, the chat monitor started from settings with
# Slack on and the extension chosen: the program must still answer seconds
# later (1.19.0 crashed there), and `bin/tool --claude-stop-hook` must answer
# `{}` and exit 0. It starts the real program (bin/tool, from :tool-folder
# below).
py_test(
    name = "tool_conformance_test",
    size = "medium",
    srcs = ["tool/conformance_test.py"],
    args = [
        "$(rootpath built/homespeaker/vitruvian-tool.json)",
        "$(rootpath //packages/vitruvian-sdk:conformance/conformance.py)",
        "$(rootpath //packages/vitruvian-sdk:vitruvian-tool)",
    ],
    data = [
        "built/homespeaker/vitruvian-tool.json",
        ":tool-folder",
        "//packages/vitruvian-sdk:conformance/conformance.py",
        "//packages/vitruvian-sdk:vitruvian-tool",
    ],
    main = "tool/conformance_test.py",
    tags = [
        "block-network",
        "manual",
    ],
    target_compatible_with = ["@platforms//os:macos"],
)

# The tool's version is the app's, in the manifest, the tool's Version.swift
# and the app's; and release-please writes all three. Not tied to macOS.
py_test(
    name = "tool_version_test",
    size = "small",
    srcs = ["tool/version_test.py"],
    data = [
        "Package.swift",
        "Sources/HomeSpeakerCore/Version.swift",
        "Sources/HomeSpeakerToolCore/Version.swift",
        "release-please-config.json",
        "tool/vitruvian-tool.json",
    ],
    main = "tool/version_test.py",
)

macos_application(
    name = "HomeSpeaker",
    bundle_id = "com.vitruviansoftware.homespeaker",
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = "14.0",
    resources = ["Resources/AppIcon.icns"],
    tags = ["manual"],
    visibility = ["//visibility:public"],
    deps = [":HomeSpeakerLib"],
)

# The release's zip of the tool (scripts/zip-tool.sh), against a stand-in
# binary: what it holds, what it is called, and the version it refuses.
# macOS-only and `manual`, as sync_secrets_test is, for the same reasons.
sh_test(
    name = "zip_tool_test",
    size = "small",
    srcs = ["scripts/zip-tool_test.sh"],
    data = [
        "scripts/zip-tool.sh",
        "tool/vitruvian-tool.json",
    ],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# publish.sh must fail when the packaging helper fails, or exits 0 having made
# nothing (HomeSpeaker 1.12.0 and 1.13.0 shipped with no files that way). The
# real publish.sh, with stand-ins for swift, lipo, ditto and the helper, so
# unlike its neighbours it needs no Mac and is NOT `manual`: the Linux lane
# runs it on every change. The macOS lane in ci.yaml also names it, with
# REQUIRE_BASH32=1, because only there is /bin/bash the 3.2 the release
# runner uses.
sh_test(
    name = "publish_test",
    size = "small",
    srcs = ["scripts/publish_test.sh"],
    data = ["scripts/publish.sh"],
)

# `bazel run //apps/desktop/home-speaker:sync-secrets` -- put HomeSpeaker's
# Slack user token on this Mac from Bitwarden, so the vault is the only place
# it lives. Uses the session //tools/sync-env-secrets:unlock caches.
sh_binary(
    name = "sync-secrets",
    srcs = ["scripts/sync-secrets.sh"],
)

# Runs against a fake `bw` and a temp secrets file: no vault, no real app.
# macOS-only, like HomeSpeakerTests above: it needs jq, which the Linux remote
# executors do not have, and the script it tests only makes sense on a Mac.
# `manual` keeps it out of //tools/pipeline:plan's affected-test query (which
# excludes manual) so the Linux lane never names it; the macOS lane in ci.yaml
# runs it by explicit label, which ignores `manual`.
sh_test(
    name = "sync_secrets_test",
    size = "small",
    srcs = ["scripts/sync-secrets_test.sh"],
    data = ["scripts/sync-secrets.sh"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# --- Rust ports ---------------------------------------------------------------

rust_library(
    name = "zip_tool_lib",
    srcs = ["scripts/src/zip_tool/lib.rs"],
    crate_name = "zip_tool_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "zip-tool-rs",
    srcs = ["scripts/src/zip_tool/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":zip_tool_lib"],
)

rust_test(
    name = "zip_tool_lib_test",
    size = "small",
    crate = ":zip_tool_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_library(
    name = "sync_secrets_lib",
    srcs = ["scripts/src/sync_secrets/lib.rs"],
    crate_name = "sync_secrets_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "sync-secrets-rs",
    srcs = ["scripts/src/sync_secrets/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":sync_secrets_lib"],
)

rust_test(
    name = "sync_secrets_lib_test",
    size = "small",
    crate = ":sync_secrets_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_library(
    name = "publish_lib",
    srcs = ["scripts/src/publish/lib.rs"],
    crate_name = "publish_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "publish-rs",
    srcs = ["scripts/src/publish/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":publish_lib"],
)

rust_test(
    name = "publish_lib_test",
    size = "small",
    crate = ":publish_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)
