// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// A token's secret is shown once and never kept: no column of any token row holds it, or any part of its random
// half long enough to matter.
func TestAPITokenStoredOnlyAsHash(t *testing.T) {
	s, ctx := open(t), context.Background()
	tok, secret, err := s.CreateAPIToken(ctx, "Test client", false)
	require.NoError(t, err)
	require.True(t, strings.HasPrefix(secret, TokenPrefix))
	require.Len(t, secret, len(TokenPrefix)+43, "32 bytes of base64url, unpadded")
	random := strings.TrimPrefix(secret, TokenPrefix)

	rows, err := s.db.Query(ctx, `SELECT id, name, hash, can_send, created_ms, last_used_ms, revoked_ms FROM api_tokens`)
	require.NoError(t, err)
	defer rows.Close()
	n := 0
	for rows.Next() {
		n++
		var (
			id, name          string
			hash              []byte
			canSend           int
			created           int64
			lastUsed, revoked sql.NullInt64
		)
		require.NoError(t, rows.Scan(&id, &name, &hash, &canSend, &created, &lastUsed, &revoked))
		for _, col := range []string{id, name, string(hash)} {
			require.NotContains(t, col, secret)
			require.NotContains(t, col, random[:16])
		}
		require.Equal(t, tokenHash(secret), hash, "the hash is the SHA-256 of the whole secret")
		require.Equal(t, tok.ID, id)
	}
	require.NoError(t, rows.Err())
	require.Equal(t, 1, n)

	got, err := s.LookupAPIToken(ctx, secret)
	require.NoError(t, err)
	require.Equal(t, tok.ID, got.ID)
	_, err = s.LookupAPIToken(ctx, secret+"x")
	require.ErrorIs(t, err, ErrNotFound)
	_, err = s.LookupAPIToken(ctx, "")
	require.ErrorIs(t, err, ErrNotFound)
}

func TestAPITokenLookupRejectsRevoked(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_700_000_000_000)
	clock := clockAt(s, t0)
	a, secretA, err := s.CreateAPIToken(ctx, "A", true)
	require.NoError(t, err)
	b, secretB, err := s.CreateAPIToken(ctx, "B", false)
	require.NoError(t, err)
	require.True(t, a.CanSend)
	require.False(t, b.CanSend)

	got, err := s.LookupAPIToken(ctx, secretA)
	require.NoError(t, err)
	require.Equal(t, t0, got.LastUsed, "a lookup stamps the last use")
	clock.set(t0.Add(30 * time.Second))
	got, err = s.LookupAPIToken(ctx, secretA)
	require.NoError(t, err)
	require.Equal(t, t0, got.LastUsed, "at most once a minute")
	clock.set(t0.Add(2 * time.Minute))
	got, err = s.LookupAPIToken(ctx, secretA)
	require.NoError(t, err)
	require.Equal(t, t0.Add(2*time.Minute), got.LastUsed)

	require.NoError(t, s.SetAPITokenCanSend(ctx, b.ID, true))
	got, err = s.LookupAPIToken(ctx, secretB)
	require.NoError(t, err)
	require.True(t, got.CanSend)

	require.NoError(t, s.RevokeAPIToken(ctx, a.ID))
	_, err = s.LookupAPIToken(ctx, secretA)
	require.ErrorIs(t, err, ErrNotFound, "a revoked token is refused")
	require.ErrorIs(t, s.RevokeAPIToken(ctx, a.ID), ErrNotFound, "revoked already")
	require.ErrorIs(t, s.SetAPITokenCanSend(ctx, a.ID, false), ErrNotFound)
	require.ErrorIs(t, s.RevokeAPIToken(ctx, "tok_none"), ErrNotFound)

	list, err := s.ListAPITokens(ctx)
	require.NoError(t, err)
	require.Len(t, list, 1, "no revoked ones")
	require.Equal(t, b.ID, list[0].ID)
	require.True(t, list[0].CanSend)
	require.Equal(t, t0.Add(2*time.Minute), list[0].LastUsed)
}

func TestAPITokenNamesAreTrimmedAndCapped(t *testing.T) {
	s, ctx := open(t), context.Background()
	long := strings.Repeat("é", 70)
	for in, want := range map[string]string{
		"  Test client \n":         "Test client",
		"Te\x00st\tcli\x1bent":     "Testclient",
		"‮evil‬ name":              "evil name",
		"":                         UnnamedClient,
		" \t\r\n ":                 UnnamedClient,
		long:                       strings.Repeat("é", MaxClientNameRunes),
		"bad\xffutf8":              "badutf8",
		"Claude Code (MCP client)": "Claude Code (MCP client)",
	} {
		tok, _, err := s.CreateAPIToken(ctx, in, false)
		require.NoError(t, err)
		require.Equal(t, want, tok.Name, "%q", in)
		require.Equal(t, want, CleanClientName(in))
	}
	list, err := s.ListAPITokens(ctx)
	require.NoError(t, err)
	for _, tok := range list {
		require.LessOrEqual(t, len([]rune(tok.Name)), MaxClientNameRunes)
		require.NotEmpty(t, tok.Name)
	}
}

func TestLocalAPISettingsDefaults(t *testing.T) {
	s, ctx := open(t), context.Background()
	got, err := s.LocalAPI(ctx)
	require.NoError(t, err)
	require.Equal(t, LocalAPISettings{Enabled: false, Port: 23390, Remote: false}, got, "off, port 23390, this Mac only")

	want := LocalAPISettings{Enabled: true, Port: 24000, Remote: true}
	require.NoError(t, s.SetLocalAPI(ctx, want))
	got, err = s.LocalAPI(ctx)
	require.NoError(t, err)
	require.Equal(t, want, got)

	for _, port := range []int{0, 80, 1023, 65536} {
		require.ErrorIs(t, s.SetLocalAPI(ctx, LocalAPISettings{Port: port}), ErrBadValue, "port %d", port)
	}
	got, err = s.LocalAPI(ctx)
	require.NoError(t, err)
	require.Equal(t, want, got, "a refused port saves nothing")

	// A stored port that can't be read is taken as the default.
	require.NoError(t, s.SetSetting(ctx, settingLocalAPIPort, "nonsense"))
	got, err = s.LocalAPI(ctx)
	require.NoError(t, err)
	require.Equal(t, DefaultLocalAPIPort, got.Port)
}

// The settings and the tokens are in courier.db, so they are there after a restart.
func TestLocalAPISettingsSurviveReopening(t *testing.T) {
	path := t.TempDir() + "/courier.db"
	ctx := context.Background()
	s, err := Open(path)
	require.NoError(t, err)
	require.NoError(t, s.SetLocalAPI(ctx, LocalAPISettings{Enabled: true, Port: 25000}))
	_, secret, err := s.CreateAPIToken(ctx, "Kept", false)
	require.NoError(t, err)
	require.NoError(t, s.Close())

	s, err = Open(path)
	require.NoError(t, err)
	defer s.Close()
	got, err := s.LocalAPI(ctx)
	require.NoError(t, err)
	require.Equal(t, LocalAPISettings{Enabled: true, Port: 25000}, got)
	tok, err := s.LookupAPIToken(ctx, secret)
	require.NoError(t, err)
	require.Equal(t, "Kept", tok.Name)
}
