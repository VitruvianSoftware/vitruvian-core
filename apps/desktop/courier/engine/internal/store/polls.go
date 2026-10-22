// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"strings"
)

// Polls (MSC3381): a poll is an org.matrix.msc3381.poll.start event; each vote is a poll.response and the end a
// poll.end, both pointing at the poll through m.relates_to.event_id, which events_refs indexes.
const (
	pollStartType    = "org.matrix.msc3381.poll.start"
	pollResponseType = "org.matrix.msc3381.poll.response"
	pollEndType      = "org.matrix.msc3381.poll.end"
)

// PollOption is one answer of a poll and how many people chose it.
type PollOption struct {
	ID, Text string
	Votes    int
}

// PollTally is a poll as it stands: its question and options with their votes, how many answers one person may
// choose, how many people voted, my own choices (option IDs) and whether it has ended.
type PollTally struct {
	Question      string
	Options       []PollOption
	MaxSelections int
	Voters        int
	Mine          []string
	Ended         bool
}

// extensibleText is MSC1767 text: org.matrix.msc1767.text, else the first plain-text entry of
// org.matrix.msc1767.message, else a plain body.
type extensibleText struct {
	Text    string `json:"org.matrix.msc1767.text"`
	Message []struct {
		MimeType string `json:"mimetype"`
		Body     string `json:"body"`
	} `json:"org.matrix.msc1767.message"`
	Body string `json:"body"`
}

func (t extensibleText) String() string {
	if t.Text != "" {
		return t.Text
	}
	for _, m := range t.Message {
		if m.MimeType == "" || m.MimeType == "text/plain" {
			return m.Body
		}
	}
	return t.Body
}

// pollStart is what a poll.start's content says.
type pollStart struct {
	Start *struct {
		MaxSelections int            `json:"max_selections"`
		Question      extensibleText `json:"question"`
		Answers       []struct {
			ID string `json:"id"`
			extensibleText
		} `json:"answers"`
	} `json:"org.matrix.msc3381.poll.start"`
}

func parsePoll(content json.RawMessage) (pollStart, bool) {
	var p pollStart
	return p, json.Unmarshal(content, &p) == nil && p.Start != nil
}

// pollText is a poll's searchable text: the question, then each option on its own line.
func pollText(content json.RawMessage) (string, bool) {
	p, ok := parsePoll(content)
	if !ok {
		return "", false
	}
	lines := []string{p.Start.Question.String()}
	for _, a := range p.Start.Answers {
		lines = append(lines, a.String())
	}
	return strings.Join(lines, "\n"), true
}

// pollRefsSQL lists the votes and ends of the polls in the JSON array $1, oldest first, through events_refs (its
// WHERE is repeated so the planner can use it). Failed and deleted ones are left out. The chat is checked in Go, as
// CurrentText does, so that nothing tempts the planner onto events_room_ts instead.
var pollRefsSQL = `SELECT room_id, ` + editTargetSQL("content") + `, sender, type, content FROM events
WHERE type IN ('` + pollResponseType + `', '` + pollEndType + `')
  AND ` + editTargetSQL("content") + ` IN (SELECT value FROM json_each($1))
  AND status <> 'failed' AND redacted = 0
ORDER BY ts, seq`

// PollTallies counts the votes of the polls pollIDs in roomID, keyed by poll ID; an ID that isn't a poll of that chat
// is left out. Each person's newest vote counts (a later vote replaces an earlier one), only options the poll has,
// and at most max_selections of them (at least 1). A vote that failed to send, or was deleted, doesn't count. A
// poll.end from the poll's own sender ends it, and a vote cast after that end doesn't count (MSC3381).
func (s *Store) PollTallies(ctx context.Context, roomID string, pollIDs []string) (map[string]PollTally, error) {
	out := map[string]PollTally{}
	ids := distinct(pollIDs)
	if len(ids) == 0 {
		return out, nil
	}
	type poll struct {
		sender  string
		tally   PollTally
		options map[string]int // option ID → index in tally.Options
		votes   map[string][]string
	}
	polls := map[string]*poll{}
	for _, id := range ids {
		e, ok, err := s.GetEvent(ctx, id)
		if err != nil {
			return nil, err
		}
		if !ok || e.RoomID != roomID || e.Type != pollStartType {
			continue
		}
		p, ok := parsePoll(e.Content)
		if !ok {
			continue
		}
		pl := &poll{sender: e.Sender, options: map[string]int{}, votes: map[string][]string{}}
		pl.tally.Question, pl.tally.MaxSelections = p.Start.Question.String(), max(p.Start.MaxSelections, 1)
		for _, a := range p.Start.Answers {
			if _, dup := pl.options[a.ID]; dup || a.ID == "" {
				continue
			}
			pl.options[a.ID] = len(pl.tally.Options)
			pl.tally.Options = append(pl.tally.Options, PollOption{ID: a.ID, Text: a.String()})
		}
		polls[id] = pl
	}
	if len(polls) == 0 {
		return out, nil
	}
	list := make([]string, 0, len(polls))
	for id := range polls {
		list = append(list, id)
	}
	b, _ := json.Marshal(list)
	rows, err := s.db.Query(ctx, pollRefsSQL, string(b))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var room, target, sender, typ, content string
		if err := rows.Scan(&room, &target, &sender, &typ, &content); err != nil {
			return nil, err
		}
		pl := polls[target]
		switch {
		case pl == nil, room != roomID:
		case pl.tally.Ended: // MSC3381: nothing after the end counts (rows come oldest first)
		case typ == pollEndType:
			pl.tally.Ended = pl.tally.Ended || sender == pl.sender
		default:
			var r struct {
				Response struct {
					Answers []string `json:"answers"`
				} `json:"org.matrix.msc3381.poll.response"`
			}
			_ = json.Unmarshal([]byte(content), &r) // a vote we can't read chooses nothing
			var chosen []string
			seen := map[string]bool{}
			for _, a := range r.Response.Answers {
				if _, known := pl.options[a]; known && !seen[a] && len(chosen) < pl.tally.MaxSelections {
					seen[a] = true
					chosen = append(chosen, a)
				}
			}
			pl.votes[sender] = chosen // oldest first, so the newest vote is the one left
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for id, pl := range polls {
		for sender, chosen := range pl.votes {
			if len(chosen) == 0 {
				continue // a vote with no option this poll has is no vote
			}
			pl.tally.Voters++
			for _, a := range chosen {
				pl.tally.Options[pl.options[a]].Votes++
			}
			if sender == myID {
				pl.tally.Mine = chosen
			}
		}
		out[id] = pl.tally
	}
	return out, nil
}
