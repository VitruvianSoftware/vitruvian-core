// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

// The fan-control model is a module of its own so the privileged fan helper can
// link it without the rest of the app. Everything else reaches it through Core.
@_exported import FanControlKit
