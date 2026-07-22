// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package main

import "testing"

// The environment identity is pinned by the leaf directory, not by stack
// config (upstream business_unit_1/<env> layout). A wrong pin would deploy one
// environment's app identities into another environment's project.
func TestPinnedEnvironment(t *testing.T) {
	if pinnedEnv != "development" {
		t.Fatalf("pinnedEnv = %q, want %q", pinnedEnv, "development")
	}
}

func TestSplitListTrimsAndDropsEmpties(t *testing.T) {
	got := splitList(" a , ,b ")
	if len(got) != 2 || got[0] != "a" || got[1] != "b" {
		t.Fatalf("splitList = %#v, want [a b]", got)
	}
	if splitList("  ") != nil {
		t.Fatal("splitList(blank) should be nil")
	}
}

// The workload switch must stay FALSE until the live Cloud Run service has been
// imported into this stack. Flipping it without the import makes Pulumi try to
// CREATE a service that already exists: the apply fails, and on a stack that
// already owned traffic it would be a user-visible outage rather than a clean
// error. This test is the reminder that the config flip is step TWO of the
// cutover, never step one — see §7 of the core-vs-application doc.
func TestWorkloadCutoverSwitchDefaultsOff(t *testing.T) {
	a := AppConfig{Name: "tabula"}
	if a.WorkloadEnabled {
		t.Fatal("WorkloadEnabled must default to false; the cutover requires a pulumi import first")
	}
}
