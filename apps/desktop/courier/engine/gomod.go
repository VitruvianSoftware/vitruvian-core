// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package engine exposes the engine module's go.mod for build-time dependency version reporting.
package engine

import _ "embed"

// GoMod is the raw contents of apps/desktop/courier/engine/go.mod embedded at compile time.
//
//go:embed go.mod
var GoMod string
