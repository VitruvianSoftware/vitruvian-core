load("@rules_go//go:def.bzl", "go_library")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:prefix github.com/VitruvianSoftware/vitruvian-courier/engine
package(default_visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"])

# The networks test reads the bridge versions this go.mod pins (TestWhatsAppBridgeVersionIsTheOneCheckedForUnreadMarks).
exports_files(
    ["go.mod"],
    visibility = ["//apps/desktop/vitruvian-courier/engine/internal/networks:__pkg__"],
)

# The engine's tests on macOS. Signal links Signal's Rust library
# (//apps/desktop/vitruvian-courier/libsignal:signal_ffi), which builds only on macOS, so only a
# Mac runs the Signal registration and the link test
# (internal/networks/signal_link_test.go). The Linux lanes (ci.yaml's go-race
# and build-test) run the same go_tests without Signal.
#
# So this unit lists only the tests that reach the Signal code: the networks
# package and the engine binaries that link it. The engine's other go_tests
# have no macOS-only code and run on Linux in build-test when affected.
#
# 60 minutes: a cold libsignal build is about 2,000 to 2,700 actions
# (docs/m2-libsignal.md); the remote cache makes later runs much shorter.
pipeline_unit(
    name = "vitruvian-courier-engine-macos",
    persona = "backend",
    runner = "xcode-27",
    test_targets = [
        "//apps/desktop/vitruvian-courier/engine/cmd/vitruvian-courier-engine:vitruvian-courier-engine_seed_test",
        "//apps/desktop/vitruvian-courier/engine/cmd/vitruvian-courier-engine:vitruvian-courier-engine_test",
        "//apps/desktop/vitruvian-courier/engine/cmd/vitruvian-courier-engine-cli:vitruvian-courier-engine-cli_test",
        "//apps/desktop/vitruvian-courier/engine/internal/gchat:gchat_test",
        "//apps/desktop/vitruvian-courier/engine/internal/networks:gchat_link_test",
        "//apps/desktop/vitruvian-courier/engine/internal/networks:networks_test",
    ],
    tier = "L1",
    timeout_minutes = 60,
)

go_library(
    name = "engine",
    srcs = ["gomod.go"],
    embedsrcs = ["go.mod"],
    importpath = "github.com/VitruvianSoftware/vitruvian-courier/engine",
)
