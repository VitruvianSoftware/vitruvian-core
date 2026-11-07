# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later

# Made-up chats for the Courier Test Copy and the app's view tests (README.md). The seeded engine
# (//apps/desktop/courier/engine/cmd/courier-engine:courier-engine-seeded) plays one into an empty data folder;
# :run_test_copy -- --seed NAME picks it; CourierViewTests renders a chat from one.
filegroup(
    name = "scenarios",
    srcs = glob(["scenarios/*.json"]),
    visibility = ["//apps/desktop/courier:__subpackages__"],
)

exports_files(
    glob(["scenarios/*.json"]),
    visibility = ["//apps/desktop/courier:__subpackages__"],
)
