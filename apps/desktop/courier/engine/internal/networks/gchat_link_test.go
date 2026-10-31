// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

//go:build darwin

package networks

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/gchat"
)

func TestGChatLinksGChatFFI(t *testing.T) {
	require.NoError(t, gchat.LinkCheck())
}
