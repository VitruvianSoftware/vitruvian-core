# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# Lets the connector's defaults_match_relay_stack test read the live values.
# Argo CD's directory source loads only .yaml/.yml/.json, so this file is
# invisible to it.
exports_files(
    ["values.yaml"],
    visibility = ["//apps/suites/vitruvian-relay/connector:__pkg__"],
)
