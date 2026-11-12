// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"unicode/utf8"
)

// ErrNotFound is the answer for a chat or label the store doesn't have.
var ErrNotFound = errors.New("no such chat or label")

// Label is a name I give a group of chats ("Work", "Family"). It is also a space. Color is an index into the app's
// list of system colours (0–11) and Icon an SF Symbol name from the app's list. Muted and ShowInInbox are the
// label's space settings (UpdateSpace).
type Label struct {
	ID          int64
	Title       string
	Color       int
	Icon        string
	Muted       bool
	ShowInInbox string
}

// LabelUpdate names the fields UpdateLabel changes; nil leaves a field as it is.
type LabelUpdate struct {
	Title *string
	Color *int
	Icon  *string
}

const (
	maxLabelTitleChars = 40
	maxLabelColor      = 11
	maxLabelIconBytes  = 64
)

// checkLabelTitle trims title and checks it is 1–40 characters.
func checkLabelTitle(title string) (string, error) {
	title = strings.TrimSpace(title)
	if n := utf8.RuneCountInString(title); n < 1 || n > maxLabelTitleChars {
		return "", ErrBadValue
	}
	return title, nil
}

func checkLabelColor(color int) error {
	if color < 0 || color > maxLabelColor {
		return ErrBadValue
	}
	return nil
}

func checkLabelIcon(icon string) error {
	if icon == "" || len(icon) > maxLabelIconBytes {
		return ErrBadValue
	}
	return nil
}

func labelSpaceID(id int64) string { return "label:" + strconv.FormatInt(id, 10) }

// CreateLabel makes a label. The title is trimmed and must be 1–40 characters, the colour 0–11 and the icon a
// non-empty name of at most 64 bytes; anything else is ErrBadValue and nothing is stored.
func (s *Store) CreateLabel(ctx context.Context, title string, color int, icon string) (Label, error) {
	title, err := checkLabelTitle(title)
	if err != nil {
		return Label{}, err
	}
	if err = checkLabelColor(color); err != nil {
		return Label{}, err
	}
	if err = checkLabelIcon(icon); err != nil {
		return Label{}, err
	}
	l := Label{Title: title, Color: color, Icon: icon, ShowInInbox: showAll}
	err = s.db.QueryRow(ctx, `INSERT INTO labels (title, color, icon, created_at) VALUES ($1,$2,$3,$4) RETURNING label_id`,
		title, color, icon, s.now().UnixMilli()).Scan(&l.ID)
	if err != nil {
		return Label{}, err
	}
	s.publish(Change{Kind: "spaces"})
	return l, nil
}

// UpdateLabel changes a label's title, colour or icon, checked as CreateLabel checks them. A refused value
// changes nothing.
func (s *Store) UpdateLabel(ctx context.Context, id int64, u LabelUpdate) error {
	var title *string
	if u.Title != nil {
		t, err := checkLabelTitle(*u.Title)
		if err != nil {
			return err
		}
		title = &t
	}
	if u.Color != nil {
		if err := checkLabelColor(*u.Color); err != nil {
			return err
		}
	}
	if u.Icon != nil {
		if err := checkLabelIcon(*u.Icon); err != nil {
			return err
		}
	}
	res, err := s.db.Exec(ctx, `UPDATE labels SET title=COALESCE($2, title), color=COALESCE($3, color), icon=COALESCE($4, icon)
		WHERE label_id=$1`, id, title, u.Color, u.Icon)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	s.publish(Change{Kind: "spaces"})
	return nil
}

// DeleteLabel deletes a label. It comes off every chat, and its space goes with it: its auto-archive rules (and
// what they had scheduled) and its place in the spaces layout.
func (s *Store) DeleteLabel(ctx context.Context, id int64) error {
	var rooms []string
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		rows, err := s.db.Query(ctx, "SELECT room_id FROM room_labels WHERE label_id=$1 ORDER BY room_id", id)
		if err != nil {
			return err
		}
		for rows.Next() {
			var r string
			if err = rows.Scan(&r); err != nil {
				rows.Close()
				return err
			}
			rooms = append(rooms, r)
		}
		rows.Close()
		if err = rows.Err(); err != nil {
			return err
		}
		res, err := s.db.Exec(ctx, "DELETE FROM labels WHERE label_id=$1", id) // room_labels cascade
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return ErrNotFound
		}
		space := labelSpaceID(id)
		if _, err = s.db.Exec(ctx, "DELETE FROM auto_archive_rules WHERE scope=$1", space); err != nil { // archive_due cascades
			return err
		}
		_, err = s.db.Exec(ctx, "DELETE FROM space_layout WHERE space_id=$1", space)
		return err
	})
	if err != nil {
		return err
	}
	for _, r := range rooms {
		s.publish(Change{Kind: "room", RoomID: r})
	}
	s.publish(Change{Kind: "spaces"})
	return nil
}

// SetLabel puts a label on chats (or takes it off), and returns the chats that changed. An unknown label or chat
// is ErrNotFound and changes none of them.
func (s *Store) SetLabel(ctx context.Context, roomIDs []string, labelID int64, on bool) ([]string, error) {
	var changed []string
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var n int
		if err := s.db.QueryRow(ctx, "SELECT COUNT(*) FROM labels WHERE label_id=$1", labelID).Scan(&n); err != nil {
			return err
		}
		if n == 0 {
			return ErrNotFound
		}
		for _, id := range distinct(roomIDs) {
			if err := s.db.QueryRow(ctx, "SELECT COUNT(*) FROM rooms WHERE room_id=$1", id).Scan(&n); err != nil {
				return err
			}
			if n == 0 {
				return ErrNotFound
			}
			q := "DELETE FROM room_labels WHERE room_id=$1 AND label_id=$2"
			if on {
				q = "INSERT INTO room_labels (room_id, label_id) VALUES ($1,$2) ON CONFLICT DO NOTHING"
			}
			res, err := s.db.Exec(ctx, q, id, labelID)
			if err != nil {
				return err
			}
			if k, _ := res.RowsAffected(); k == 1 {
				changed = append(changed, id)
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	for _, id := range changed {
		s.publish(Change{Kind: "room", RoomID: id})
	}
	return changed, nil
}

// Labels lists every label, oldest first.
func (s *Store) Labels(ctx context.Context) ([]Label, error) {
	rows, err := s.db.Query(ctx, "SELECT label_id, title, color, icon, muted, show_in_inbox FROM labels ORDER BY created_at, label_id")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Label
	for rows.Next() {
		var l Label
		var muted int
		if err := rows.Scan(&l.ID, &l.Title, &l.Color, &l.Icon, &muted, &l.ShowInInbox); err != nil {
			return nil, err
		}
		l.Muted = muted == 1
		out = append(out, l)
	}
	return out, rows.Err()
}
