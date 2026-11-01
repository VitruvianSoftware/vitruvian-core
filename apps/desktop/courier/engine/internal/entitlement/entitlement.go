// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package entitlement is the seam where a plan decides which features a person may use (spec §3). Its only
// Provider today says yes to everything; the subscription screen and a real provider arrive in part 4.7. A
// feature that is not allowed leaves its data alone: reminders and auto-archive rows wait, untouched, until it is.
package entitlement

// Feature names a feature a plan can include. The value is its name on the wire.
type Feature string

const (
	Reminders   Feature = "reminders"
	SendLater   Feature = "send_later"
	UndoSend    Feature = "undo_send"
	Incognito   Feature = "incognito"
	LowPriority Feature = "low_priority"
	AutoArchive Feature = "auto_archive"
)

// Features is every Feature, in the order above.
var Features = []Feature{Reminders, SendLater, UndoSend, Incognito, LowPriority, AutoArchive}

// Provider says whether a feature is allowed now. It is asked every time, so an answer can change while the
// engine runs.
type Provider interface{ Allowed(Feature) bool }

// Always allows every feature.
type Always struct{}

// Allowed is always true.
func (Always) Allowed(Feature) bool { return true }

// UnavailableMessage is the calm message returned when a feature requires a plan.
const UnavailableMessage = "Available with a plan"

// NoPlan denies every feature so unconfigured or free-tier callers fail closed.
type NoPlan struct{}

// Allowed is always false.
func (NoPlan) Allowed(Feature) bool { return false }
