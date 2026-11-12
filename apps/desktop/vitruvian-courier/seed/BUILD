# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later

# Made-up chats for the Vitruvian Courier Test Copy and the app's view tests (README.md). The seeded engine
# (//apps/desktop/vitruvian-courier/engine/cmd/vitruvian-courier-engine:vitruvian-courier-engine-seeded) plays one into an empty data folder;
# :run_test_copy -- --seed NAME picks it; VitruvianCourierViewTests renders a chat from one.
filegroup(
    name = "scenarios",
    srcs = glob(["scenarios/*.json"]),
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
)

exports_files(
    glob(["scenarios/*.json"]),
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
)
