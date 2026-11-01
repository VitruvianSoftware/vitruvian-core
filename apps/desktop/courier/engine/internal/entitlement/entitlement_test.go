// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package entitlement

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestEveryFeatureIsAllowedByDefault(t *testing.T) {
	want := []Feature{"reminders", "send_later", "undo_send", "incognito", "low_priority", "auto_archive"}
	require.Equal(t, want, Features, "the features, by their wire names")
	var p Provider = Always{}
	for _, f := range Features {
		require.True(t, p.Allowed(f), f)
	}
	require.True(t, p.Allowed("a_feature_added_later"), "Always says yes to anything")

	var denied Provider = NoPlan{}
	for _, f := range Features {
		require.False(t, denied.Allowed(f), f)
	}
	require.Equal(t, "Available with a plan", UnavailableMessage)
}
