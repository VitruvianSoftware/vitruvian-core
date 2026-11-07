// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

//go:build !courierseed

package main

// seedSetup is the released engine's: it never seeds, whatever the environment says, and links no seed code. The
// test copy's engine is built with the courierseed tag instead (seed_on.go).
func seedSetup(*config, func(string) string) (afterStart, error) { return nil, nil }
