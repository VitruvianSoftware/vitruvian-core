# The one definition of the protocol between Courier.app and courier-engine, and
# its examples. The engine's Go tests (engine/internal/rpc) and the app's Swift
# tests both read these files as test data and check against them, so the two
# sides cannot drift.
filegroup(
    name = "protocol",
    srcs = ["protocol.json"] + glob(["examples/*.json"]),
    visibility = [
        "//apps/desktop/courier/app:__subpackages__",
        "//apps/desktop/courier/engine:__subpackages__",
    ],
)
