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

// The case that matters is the refusal. This stack cannot be applied from a
// workstation and CI is the only path, so without this test the guard's
// behaviour would be asserted by nobody until the apply that depends on it.
func TestResolveGrantUserIDs(t *testing.T) {
	tests := []struct {
		name             string
		projectRoleCheck bool
		raw              string
		wantIDs          []string
		wantErr          bool
	}{
		{
			// THE COUPLING. Check on, nobody granted — refuse.
			name:             "check enabled with no grants is refused",
			projectRoleCheck: true,
			raw:              "",
			wantErr:          true,
		},
		{
			// Whitespace and empty elements must not read as a grant. A config
			// of "," would otherwise split into two empty strings, and a naive
			// length check on the split result would see 2 and let the apply
			// through with no actual grantee — the same fail-open shape this
			// stack already had once in cfg.GetBool.
			name:             "check enabled with only separators is refused",
			projectRoleCheck: true,
			raw:              " , ,, ",
			wantErr:          true,
		},
		{
			name:             "check enabled with a grant is allowed",
			projectRoleCheck: true,
			raw:              "378818267051722263",
			wantIDs:          []string{"378818267051722263"},
		},
		{
			// A grant with the check off is inert, not dangerous, so it is
			// allowed — grants are created ahead of the flip precisely so that
			// enabling the check later cannot introduce a gap.
			name:             "grants without the check are allowed",
			projectRoleCheck: false,
			raw:              "378818267051722263",
			wantIDs:          []string{"378818267051722263"},
		},
		{
			name:             "check disabled with no grants is allowed",
			projectRoleCheck: false,
			raw:              "",
		},
		{
			name:             "multiple ids are trimmed and split",
			projectRoleCheck: true,
			raw:              " 378818267051722263 , 379361013981513322 ",
			wantIDs:          []string{"378818267051722263", "379361013981513322"},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := resolveGrantUserIDs(tc.projectRoleCheck, tc.raw, "mcp-slack-user")
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected a refusal, got ids=%v and no error", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if len(got) != len(tc.wantIDs) {
				t.Fatalf("got %d ids %v, want %d %v", len(got), got, len(tc.wantIDs), tc.wantIDs)
			}
			for i := range got {
				if got[i] != tc.wantIDs[i] {
					t.Errorf("id[%d] = %q, want %q", i, got[i], tc.wantIDs[i])
				}
			}
		})
	}
}

// The refusal message is read by whoever is blocked by it, at the moment they
// are blocked, and it is the only place the coupling is explained at that
// point. An unhelpful message here turns a correct refusal into a confusing
// one, which is how guards get deleted rather than satisfied.
func TestRefusalMessageNamesTheFixAndTheRole(t *testing.T) {
	_, err := resolveGrantUserIDs(true, "", "mcp-slack-user")
	if err == nil {
		t.Fatal("expected a refusal")
	}
	for _, want := range []string{"grantUserIds", "mcp-slack-user", "SAME apply"} {
		if !contains(err.Error(), want) {
			t.Errorf("refusal message does not mention %q: %s", want, err)
		}
	}
}

func contains(haystack, needle string) bool {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}
