// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

/*
extern void gchat_test_only_set_allow_loopback(int allow);
*/
import "C"

import "testing"

func enableTestLoopback(t *testing.T) {
	t.Helper()
	C.gchat_test_only_set_allow_loopback(1)
	t.Cleanup(func() {
		C.gchat_test_only_set_allow_loopback(0)
	})
}
