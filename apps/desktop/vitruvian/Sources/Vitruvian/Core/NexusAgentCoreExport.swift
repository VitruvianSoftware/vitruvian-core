// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

// Nexus Agent's rules live in the standalone app's folder so both apps build
// from one copy (apps/desktop/nexus-agent/macos/Sources/NexusAgentCore, MIT).
// Everything else reaches them through Core, as it did when they lived here.
@_exported import NexusAgentCore
