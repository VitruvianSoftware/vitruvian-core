load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:prefix github.com/VitruvianSoftware/courier/engine
package(default_visibility = ["//apps/desktop/courier:__subpackages__"])

# The networks test reads the bridge versions this go.mod pins (TestWhatsAppBridgeVersionIsTheOneCheckedForUnreadMarks).
exports_files(
    ["go.mod"],
    visibility = ["//apps/desktop/courier/engine/internal/networks:__pkg__"],
)

# The engine's tests on macOS. Signal links Signal's Rust library
# (//apps/desktop/courier/libsignal:signal_ffi), which builds only on macOS, so only a
# Mac runs the Signal registration and the link test
# (internal/networks/signal_link_test.go). The Linux lanes (ci.yaml's go-race
# and build-test) run the same go_tests without Signal.
#
# 60 minutes: a cold libsignal build is about 2,000 to 2,700 actions
# (docs/m2-libsignal.md); the remote cache makes later runs much shorter.
pipeline_unit(
    name = "courier-engine-macos",
    persona = "backend",
    runner = "xcode-27",
    test_targets = ["//apps/desktop/courier/engine/..."],
    tier = "L1",
    timeout_minutes = 60,
)
