// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"strconv"
	"strings"
	"time"
	"unicode"
)

// The local API (milestone 5) lets MCP clients use Courier with a bearer token. A token is 32 random bytes, shown
// once as TokenPrefix followed by their base64url; courier.db keeps only the SHA-256 of that whole string, so the
// database alone can't be used to connect.
const (
	// TokenPrefix begins every token's secret, so one is easy to recognise (and to scrub) wherever it turns up.
	TokenPrefix = "courier_"
	// MaxClientNameRunes is the longest a token's name can be, after cleaning (CleanClientName).
	MaxClientNameRunes = 64
	// UnnamedClient is the name of a token whose name is empty after cleaning.
	UnnamedClient = "Unnamed client"
	// tokenBytes is how much randomness a token's secret carries.
	tokenBytes = 32
	// lastUsedEvery is how often, at most, a lookup stamps a token's last use: a busy client doesn't write to
	// courier.db on every request.
	lastUsedEvery = time.Minute
)

// APIToken is one token an MCP client connects with. Neither its secret nor its hash ever leaves the store.
type APIToken struct {
	ID      string
	Name    string
	CanSend bool // may send messages (send_message): off unless turned on
	Created time.Time
	// LastUsed is when a request last came with it (to the minute); zero when none has.
	LastUsed time.Time
}

// CleanClientName is name as the local API keeps and shows it: control and format characters removed, spaces
// trimmed, at most MaxClientNameRunes runes, and UnnamedClient when nothing is left. A client's name is whatever
// the client says, so it is never trusted to be tidy.
func CleanClientName(name string) string {
	name = strings.Map(func(r rune) rune {
		// Control characters, and format characters such as the bidirectional overrides, which could make a name
		// shown in a prompt read as something else.
		if unicode.IsControl(r) || unicode.Is(unicode.Cf, r) {
			return -1
		}
		return r
	}, strings.ToValidUTF8(name, ""))
	name = strings.TrimSpace(name)
	if r := []rune(name); len(r) > MaxClientNameRunes {
		name = strings.TrimSpace(string(r[:MaxClientNameRunes]))
	}
	if name == "" {
		return UnnamedClient
	}
	return name
}

// tokenHash is what courier.db keeps of a token's secret.
func tokenHash(secret string) []byte {
	sum := sha256.Sum256([]byte(secret))
	return sum[:]
}

func newTokenID() (string, error) {
	b := make([]byte, 12)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return "tok_" + hex.EncodeToString(b), nil
}

// CreateAPIToken makes a token named name (cleaned by CleanClientName) and returns it with its secret, which is
// never available again.
func (s *Store) CreateAPIToken(ctx context.Context, name string, canSend bool) (APIToken, string, error) {
	raw := make([]byte, tokenBytes)
	if _, err := rand.Read(raw); err != nil {
		return APIToken{}, "", err
	}
	secret := TokenPrefix + base64.RawURLEncoding.EncodeToString(raw)
	id, err := newTokenID()
	if err != nil {
		return APIToken{}, "", err
	}
	now := s.now()
	tok := APIToken{ID: id, Name: CleanClientName(name), CanSend: canSend, Created: time.UnixMilli(now.UnixMilli())}
	if _, err = s.db.Exec(ctx, `INSERT INTO api_tokens (id, name, hash, can_send, created_ms) VALUES ($1, $2, $3, $4, $5)`,
		tok.ID, tok.Name, tokenHash(secret), b2i(canSend), now.UnixMilli()); err != nil {
		return APIToken{}, "", err
	}
	return tok, secret, nil
}

// LookupAPIToken is the token whose secret is secret: ErrNotFound when there is none or it was revoked. It stamps
// the token's last use, at most once a minute.
func (s *Store) LookupAPIToken(ctx context.Context, secret string) (APIToken, error) {
	if !strings.HasPrefix(secret, TokenPrefix) {
		return APIToken{}, ErrNotFound
	}
	want := tokenHash(secret)
	var (
		tok       APIToken
		hash      []byte
		canSend   int
		createdMS int64
		lastUsed  sql.NullInt64
	)
	err := s.db.QueryRow(ctx, `SELECT id, name, hash, can_send, created_ms, last_used_ms FROM api_tokens
WHERE hash = $1 AND revoked_ms IS NULL`, want).Scan(&tok.ID, &tok.Name, &hash, &canSend, &createdMS, &lastUsed)
	if errors.Is(err, sql.ErrNoRows) {
		return APIToken{}, ErrNotFound
	}
	if err != nil {
		return APIToken{}, err
	}
	// The row was found by its hash; the comparison is made again in constant time all the same, so nothing about
	// how a secret is checked depends on how much of it is right.
	if subtle.ConstantTimeCompare(hash, want) != 1 {
		return APIToken{}, ErrNotFound
	}
	tok.CanSend = canSend != 0
	tok.Created = time.UnixMilli(createdMS)
	now := s.now()
	if lastUsed.Valid {
		tok.LastUsed = time.UnixMilli(lastUsed.Int64)
	}
	if !lastUsed.Valid || now.Sub(tok.LastUsed) >= lastUsedEvery {
		if _, err = s.db.Exec(ctx, `UPDATE api_tokens SET last_used_ms = $2 WHERE id = $1`, tok.ID, now.UnixMilli()); err != nil {
			return APIToken{}, err
		}
		tok.LastUsed = time.UnixMilli(now.UnixMilli())
	}
	return tok, nil
}

// ListAPITokens is every token not revoked, oldest first.
func (s *Store) ListAPITokens(ctx context.Context) ([]APIToken, error) {
	rows, err := s.db.Query(ctx, `SELECT id, name, can_send, created_ms, last_used_ms FROM api_tokens
WHERE revoked_ms IS NULL ORDER BY created_ms, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []APIToken{}
	for rows.Next() {
		var (
			tok       APIToken
			canSend   int
			createdMS int64
			lastUsed  sql.NullInt64
		)
		if err = rows.Scan(&tok.ID, &tok.Name, &canSend, &createdMS, &lastUsed); err != nil {
			return nil, err
		}
		tok.CanSend = canSend != 0
		tok.Created = time.UnixMilli(createdMS)
		if lastUsed.Valid {
			tok.LastUsed = time.UnixMilli(lastUsed.Int64)
		}
		out = append(out, tok)
	}
	return out, rows.Err()
}

// RevokeAPIToken ends a token: its very next request is refused. ErrNotFound when there is no such token, or it
// was revoked already.
func (s *Store) RevokeAPIToken(ctx context.Context, id string) error {
	res, err := s.db.Exec(ctx, `UPDATE api_tokens SET revoked_ms = $2 WHERE id = $1 AND revoked_ms IS NULL`, id, s.now().UnixMilli())
	if err != nil {
		return err
	}
	return oneRow(res)
}

// SetAPITokenCanSend lets a token send messages, or stops it. ErrNotFound when there is no such token or it was
// revoked.
func (s *Store) SetAPITokenCanSend(ctx context.Context, id string, canSend bool) error {
	res, err := s.db.Exec(ctx, `UPDATE api_tokens SET can_send = $2 WHERE id = $1 AND revoked_ms IS NULL`, id, b2i(canSend))
	if err != nil {
		return err
	}
	return oneRow(res)
}

func oneRow(res sql.Result) error {
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// The local API's settings. They are kept in courier.db, so they survive restarts.
const (
	settingLocalAPIEnabled = "localapi.enabled"
	settingLocalAPIPort    = "localapi.port"
	settingLocalAPIRemote  = "localapi.remote"

	// DefaultLocalAPIPort is the local API's port until it is changed.
	DefaultLocalAPIPort = 23390
	// MinLocalAPIPort and MaxLocalAPIPort bound the port that can be chosen: no privileged port.
	MinLocalAPIPort = 1024
	MaxLocalAPIPort = 65535
)

// LocalAPISettings is how the local API is set up: off, on the default port and on this Mac only until changed.
type LocalAPISettings struct {
	Enabled bool // Allow connections
	Port    int
	Remote  bool // Remote Access: listen on every address, not only 127.0.0.1
}

// Setting is the value of key, and whether it is set.
func (s *Store) Setting(ctx context.Context, key string) (string, bool, error) {
	var v string
	err := s.db.QueryRow(ctx, `SELECT value FROM settings WHERE key = $1`, key).Scan(&v)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	return v, err == nil, err
}

// SetSetting sets key to value.
func (s *Store) SetSetting(ctx context.Context, key, value string) error {
	_, err := s.db.Exec(ctx, `INSERT INTO settings (key, value) VALUES ($1, $2)
ON CONFLICT (key) DO UPDATE SET value = excluded.value`, key, value)
	return err
}

// LocalAPI is the local API's settings, with the defaults for any not set: off, port DefaultLocalAPIPort, Remote
// Access off. A stored value that can't be read is taken as its default.
func (s *Store) LocalAPI(ctx context.Context) (LocalAPISettings, error) {
	out := LocalAPISettings{Port: DefaultLocalAPIPort}
	for key, dst := range map[string]*bool{settingLocalAPIEnabled: &out.Enabled, settingLocalAPIRemote: &out.Remote} {
		v, ok, err := s.Setting(ctx, key)
		if err != nil {
			return LocalAPISettings{}, err
		}
		*dst = ok && v == "true"
	}
	v, ok, err := s.Setting(ctx, settingLocalAPIPort)
	if err != nil {
		return LocalAPISettings{}, err
	}
	if p, perr := strconv.Atoi(v); ok && perr == nil && p >= MinLocalAPIPort && p <= MaxLocalAPIPort {
		out.Port = p
	}
	return out, nil
}

// SetLocalAPI saves the local API's settings. A port outside MinLocalAPIPort to MaxLocalAPIPort is ErrBadValue,
// and nothing is saved.
func (s *Store) SetLocalAPI(ctx context.Context, set LocalAPISettings) error {
	if set.Port < MinLocalAPIPort || set.Port > MaxLocalAPIPort {
		return ErrBadValue
	}
	return s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		for key, value := range map[string]string{
			settingLocalAPIEnabled: strconv.FormatBool(set.Enabled),
			settingLocalAPIPort:    strconv.Itoa(set.Port),
			settingLocalAPIRemote:  strconv.FormatBool(set.Remote),
		} {
			if err := s.SetSetting(ctx, key, value); err != nil {
				return err
			}
		}
		return nil
	})
}
