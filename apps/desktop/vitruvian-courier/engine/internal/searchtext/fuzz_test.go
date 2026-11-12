// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package searchtext

import "testing"

// FuzzMatchExpr is Review Focus 2 over random input: whatever is typed parses into at most 16 terms whose
// expressions are only quoted words, the real FTS5 runs them without a syntax error, and a snippet of the
// text is well formed. The seeds are testdata/queries.txt.
func FuzzMatchExpr(f *testing.F) {
	for _, q := range readCorpus(f) {
		f.Add(q)
	}
	db := openFTS(f)
	f.Fuzz(func(t *testing.T, q string) {
		checkQuery(t, db, q)
	})
}
