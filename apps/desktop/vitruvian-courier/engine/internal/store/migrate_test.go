// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"crypto/sha256"
	"encoding/hex"
	"testing"
)

// The migrations that have shipped (1 to 4, on main since milestone 4.2; 5 since milestone 4.3; 6 since the call
// notices; 7 since milestone 4.4; 8 since milestone 4.5a) run on databases already on people's disks, and an existing
// database never runs them again, so their SQL must stay exactly as it shipped: a change to a shared definition they
// are built from (what counts as a message, say) belongs to the runtime only. These are the SHA-256 sums of their text
// as shipped. A new migration is a new entry, never an edit of one of these.
func TestShippedMigrationsAreUnchanged(t *testing.T) {
	shipped := []string{
		"25d7da8b37da95db54ebbf1457c4d686aa792bb8d1ab82d5997d43faf6068c77", // 1
		"cd3c5c97e06c14e5e032768f445f71b3ef75dac51496edca87862422226bec0f", // 2
		"a4c1893a23bac916c75b76c9196d59b367e20b430bf79204719a887d6b442134", // 3
		"e8d9f2b6c76aa7169ba5c14832ca68136f57b3f81a73d2ec3d148556593cc0e3", // 4
		"6ea69d0dbaae91657119b73542f151ad3206f6a939d71aac298acc0aeb99158a", // 5
		"c4981b6d91385f22edb826cfa056706ef31523bd4f1c4bf37b75ceaac1d3da47", // 6
		"1a6ee8818fceb69daf61b57f324cb186d53aaf233664986091d4aad8579dcf15", // 7
		"dc167f67c7688bfdb43c1e5cab3bf11518a9df29d85d7ded9d59244963fde860", // 8
		"bb47b07faf0cba8d70f273e6c55be4b9090efa43d8931a78efef05bcc4794d93", // 9
	}
	for i, want := range shipped {
		sum := sha256.Sum256([]byte(migrations[i]))
		if got := hex.EncodeToString(sum[:]); got != want {
			t.Errorf("migration %d's SQL changed after it shipped: sha256 %s, shipped %s", i+1, got, want)
		}
	}
}
