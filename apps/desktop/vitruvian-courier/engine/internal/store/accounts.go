// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"errors"
)

// SubAccount is a workspace/community/forum space ("space") or bot DM ("bot") under a bridgev2 login.
type SubAccount struct {
	Network     string // e.g. "slack", "telegram", "whatsapp"
	LoginID     string // bridgev2 user_login.id
	SubID       string // room_id of the m.space portal or bot DM room
	Title       string
	AvatarURI   string
	Kind        string // "space" (Slack workspace, WA community, TG forum) | "bot" (bot DM)
	Enabled     bool
	ShowInInbox string // "all" | "dms" | "none"
}

func validSubAccountShowInInbox(v string) bool {
	return v == showAll || v == showDMs || v == showNone
}

// SetRoomSpace marks roomID as an m.space room (when isSpace is true) or updates its parent_space_id.
func (s *Store) SetRoomSpace(ctx context.Context, roomID string, isSpace bool, parentSpaceID string) error {
	sp := 0
	if isSpace {
		sp = 1
	}
	res, err := s.db.Exec(
		ctx, `
		UPDATE rooms
		SET is_space = CASE WHEN $1 = 1 THEN 1 ELSE is_space END,
		    parent_space_id = CASE WHEN $1 = 1 AND $2 = '' THEN parent_space_id ELSE $2 END
		WHERE room_id = $3`,
		sp, parentSpaceID, roomID,
	)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n > 0 {
		s.RoomChanged(roomID)
		s.SpacesChanged()
	}
	return nil
}

// UpsertSubAccount inserts or updates a sub-account's metadata, preserving existing enabled and show_in_inbox settings on conflict.
func (s *Store) UpsertSubAccount(ctx context.Context, sub SubAccount) error {
	if sub.Network == "" || sub.SubID == "" {
		return ErrBadValue
	}
	if sub.Kind == "" {
		sub.Kind = "space"
	}
	if sub.Kind != "space" && sub.Kind != "bot" {
		return ErrBadValue
	}
	if sub.ShowInInbox == "" {
		sub.ShowInInbox = showAll
	}
	if !validSubAccountShowInInbox(sub.ShowInInbox) {
		return ErrBadValue
	}
	_, err := s.db.Exec(
		ctx, `
		INSERT INTO sub_accounts (network, login_id, sub_id, title, avatar_uri, kind, enabled, show_in_inbox)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (network, sub_id) DO UPDATE SET
			login_id   = CASE WHEN excluded.login_id <> '' THEN excluded.login_id ELSE sub_accounts.login_id END,
			title      = CASE WHEN excluded.title <> '' THEN excluded.title ELSE sub_accounts.title END,
			avatar_uri = CASE WHEN excluded.avatar_uri <> '' THEN excluded.avatar_uri ELSE sub_accounts.avatar_uri END`,
		sub.Network, sub.LoginID, sub.SubID, sub.Title, sub.AvatarURI, sub.Kind, b2i(sub.Enabled), sub.ShowInInbox,
	)
	if err == nil {
		s.SpacesChanged()
	}
	return err
}

// SubAccounts returns the sub-accounts for (network, loginID) ordered by kind ("space" first), title, and sub_id.
// When loginID is "", all sub-accounts on network are returned.
func (s *Store) SubAccounts(ctx context.Context, network, loginID string) ([]SubAccount, error) {
	rows, err := s.db.Query(
		ctx, `
		SELECT network, login_id, sub_id, title, avatar_uri, kind, enabled, show_in_inbox
		FROM sub_accounts
		WHERE network = $1 AND ($2 = '' OR login_id = $2 OR login_id = '')
		ORDER BY CASE WHEN kind = 'space' THEN 0 ELSE 1 END, title ASC, sub_id ASC`,
		network, loginID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []SubAccount{}
	for rows.Next() {
		var sub SubAccount
		var en int
		if err := rows.Scan(&sub.Network, &sub.LoginID, &sub.SubID, &sub.Title, &sub.AvatarURI, &sub.Kind, &en, &sub.ShowInInbox); err != nil {
			return nil, err
		}
		sub.Enabled = en == 1
		out = append(out, sub)
	}
	return out, rows.Err()
}

// UpdateSubAccount updates enabled and/or show_in_inbox for an existing sub-account.
func (s *Store) UpdateSubAccount(ctx context.Context, network, loginID, subID string, enabled *bool, showInInbox *string) error {
	if showInInbox != nil && !validSubAccountShowInInbox(*showInInbox) {
		return ErrBadValue
	}
	if enabled == nil && showInInbox == nil {
		return nil
	}
	var curEnabled int
	var curShow, actualLoginID string
	err := s.db.QueryRow(
		ctx, `
		SELECT login_id, enabled, show_in_inbox
		FROM sub_accounts
		WHERE network = $1 AND sub_id = $2 AND ($3 = '' OR login_id = $3 OR login_id = '')
		ORDER BY CASE WHEN login_id = $3 THEN 0 ELSE 1 END
		LIMIT 1`,
		network, subID, loginID,
	).Scan(&actualLoginID, &curEnabled, &curShow)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if enabled != nil {
		curEnabled = b2i(*enabled)
	}
	if showInInbox != nil {
		curShow = *showInInbox
	}
	if _, err := s.db.Exec(
		ctx, `
		UPDATE sub_accounts
		SET enabled = $1, show_in_inbox = $2
		WHERE network = $3 AND login_id = $4 AND sub_id = $5`,
		curEnabled, curShow, network, actualLoginID, subID,
	); err != nil {
		return err
	}
	s.SpacesChanged()
	s.publish(Change{Kind: ChangeResync})
	return nil
}

// SyncBotSubAccounts discovers DM rooms on (network, loginID) whose other member has profiles.is_bot = 1,
// upserts them as kind="bot" sub-accounts (preserving existing enabled/show_in_inbox settings),
// and returns the resulting sub-accounts list for (network, loginID).
func (s *Store) SyncBotSubAccounts(ctx context.Context, network, loginID string) ([]SubAccount, error) {
	rows, err := s.db.Query(
		ctx, `
		SELECT r.room_id, r.login_id,
		       COALESCE(NULLIF(r.name, ''), p.display_name, ''),
		       COALESCE(NULLIF(r.avatar_uri, ''), p.avatar_uri, '')
		FROM rooms r
		JOIN members m ON m.room_id = r.room_id AND m.user_id <> $3
		JOIN profiles p ON p.user_id = m.user_id AND p.is_bot = 1
		WHERE r.network = $1
		  AND ($2 = '' OR r.login_id = $2 OR r.login_id = '')
		  AND r.is_direct = 1
		  AND r.is_space = 0
		ORDER BY r.room_id`,
		network, loginID, myID,
	)
	if err != nil {
		return nil, err
	}
	type botRoom struct {
		roomID, loginID, title, avatarURI string
	}
	var found []botRoom
	for rows.Next() {
		var b botRoom
		if err := rows.Scan(&b.roomID, &b.loginID, &b.title, &b.avatarURI); err != nil {
			rows.Close()
			return nil, err
		}
		found = append(found, b)
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for _, b := range found {
		lid := loginID
		if lid == "" {
			lid = b.loginID
		}
		if err := s.UpsertSubAccount(ctx, SubAccount{
			Network:     network,
			LoginID:     lid,
			SubID:       b.roomID,
			Title:       b.title,
			AvatarURI:   b.avatarURI,
			Kind:        "bot",
			Enabled:     true,
			ShowInInbox: showAll,
		}); err != nil {
			return nil, err
		}
	}
	return s.SubAccounts(ctx, network, loginID)
}

// RemoveAccountData removes login_state and sub_accounts for (network, loginID).
// When deleteChats is true, it also deletes all rooms (and cascading events/members/state/reads/FTS)
// belonging to (network, loginID), and if no logins remain on network, deletes rooms with login_id=”
// on that network plus account_prefs and space_layout entries for account:<network>.
func (s *Store) RemoveAccountData(ctx context.Context, network, loginID string, deleteChats bool) error {
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		if _, err := s.db.Exec(ctx, `DELETE FROM login_state WHERE network = $1 AND login_id = $2`, network, loginID); err != nil {
			return err
		}
		if _, err := s.db.Exec(ctx, `DELETE FROM sub_accounts WHERE network = $1 AND login_id = $2`, network, loginID); err != nil {
			return err
		}
		var remaining int
		if err := s.db.QueryRow(ctx, `SELECT COUNT(*) FROM login_state WHERE network = $1 AND login_id <> ''`, network).Scan(&remaining); err != nil {
			return err
		}
		if remaining == 0 {
			if _, err := s.db.Exec(ctx, `DELETE FROM sub_accounts WHERE network = $1`, network); err != nil {
				return err
			}
			if _, err := s.db.Exec(ctx, `DELETE FROM login_state WHERE network = $1`, network); err != nil {
				return err
			}
		}
		if deleteChats {
			roomQuery := `SELECT room_id FROM rooms WHERE network = $1 AND login_id = $2`
			roomArgs := []any{network, loginID}
			if remaining == 0 {
				roomQuery = `SELECT room_id FROM rooms WHERE network = $1 AND (login_id = $2 OR login_id = '')`
			}
			rows, err := s.db.Query(ctx, roomQuery, roomArgs...)
			if err != nil {
				return err
			}
			var roomIDs []string
			for rows.Next() {
				var rid string
				if err := rows.Scan(&rid); err != nil {
					rows.Close()
					return err
				}
				roomIDs = append(roomIDs, rid)
			}
			if err := rows.Close(); err != nil {
				return err
			}
			if err := rows.Err(); err != nil {
				return err
			}
			peopleSet := make(map[string]struct{})
			for _, rid := range roomIDs {
				members, err := s.memberIDs(ctx, rid)
				if err != nil {
					return err
				}
				for _, u := range members {
					peopleSet[u] = struct{}{}
				}
				if _, err := s.db.Exec(ctx, `DELETE FROM media_played WHERE room_id = $1`, rid); err != nil {
					return err
				}
				if _, err := s.db.Exec(ctx, `DELETE FROM rooms WHERE room_id = $1`, rid); err != nil {
					return err
				}
			}
			for u := range peopleSet {
				if err := s.indexPerson(ctx, u); err != nil {
					return err
				}
			}
			if _, err := s.db.Exec(
				ctx, `
				DELETE FROM merged_chats
				WHERE (SELECT COUNT(*) FROM merged_chat_rooms mcr WHERE mcr.merge_id = merged_chats.merge_id) < 2`,
			); err != nil {
				return err
			}
			if remaining == 0 {
				if _, err := s.db.Exec(ctx, `DELETE FROM account_prefs WHERE network = $1`, network); err != nil {
					return err
				}
				if _, err := s.db.Exec(ctx, `DELETE FROM space_layout WHERE space_id = 'account:' || $1`, network); err != nil {
					return err
				}
			}
		}
		return nil
	})
	if err == nil {
		s.NetworkChanged(network)
		s.SpacesChanged()
		s.publish(Change{Kind: ChangeResync})
	}
	return err
}
