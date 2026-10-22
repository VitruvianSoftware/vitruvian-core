// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// MaxPollQuestion is the most characters a poll's question may have.
const MaxPollQuestion = 300

// pollKindDisclosed is a poll whose results everyone sees as they come in (MSC3381). Courier makes no other kind:
// no bridge takes hidden results.
const pollKindDisclosed = "org.matrix.msc3381.poll.disclosed"

// CreatePoll starts a poll in a chat whose network takes polls (else ErrNotSupported) and returns the ID of the
// stored poll. The question, trimmed, has 1 to MaxPollQuestion characters; there are 2 to the chat's MaxOptions
// options, each trimmed, of 1 to its OptionMaxLength characters, no two the same ignoring case; anything else is
// ErrBadValue. With multiple a person may choose every option, else one. The options' IDs are "1" to "n", in order.
func (a *Actions) CreatePoll(ctx context.Context, roomID, question string, options []string, multiple bool) (string, error) {
	h, err := a.eng.HostForRoom(ctx, roomID)
	if err != nil {
		return "", err
	}
	f, err := a.Features(ctx, roomID)
	if err != nil {
		return "", err
	}
	// A network that advertises polls but no option limit has no Poll (FeaturesOf): refused, not guessed at. Both
	// bridges with polls (WhatsApp 12, Signal 10) advertise their limit, and a guess above the real one would only
	// turn into a poll the network fails after it was shown as sent; the app greys Polls out the same way.
	if f.Poll == nil {
		return "", ErrNotSupported
	}
	question = strings.TrimSpace(question)
	if n := utf8.RuneCountInString(question); n == 0 || n > MaxPollQuestion {
		return "", ErrBadValue
	}
	if len(options) < 2 || len(options) > f.Poll.MaxOptions {
		return "", ErrBadValue
	}
	answers := make([]event.PollOption, 0, len(options))
	for i, o := range options {
		o = strings.TrimSpace(o)
		n := utf8.RuneCountInString(o)
		if n == 0 || f.Poll.OptionMaxLength > 0 && n > f.Poll.OptionMaxLength {
			return "", ErrBadValue
		}
		for _, earlier := range answers {
			if strings.EqualFold(earlier.Text, o) {
				return "", ErrBadValue
			}
		}
		answers = append(answers, event.PollOption{ID: strconv.Itoa(i + 1), MSC1767Message: event.MSC1767Message{Text: o}})
	}
	maxSelections := 1
	if multiple {
		maxSelections = len(answers)
	}
	if err = WaitForLogin(ctx, h, a.LoginWait); err != nil {
		return "", err
	}
	return a.submit(ctx, h, roomID, event.EventUnstablePollStart, &event.PollStartEventContent{PollStart: event.PollStart{
		Kind: pollKindDisclosed, MaxSelections: maxSelections,
		Question: event.MSC1767Message{Text: question}, Answers: answers,
	}})
}

// pollOf reads a poll's option IDs and how many of them one person may choose (at least 1).
func pollOf(content json.RawMessage) (optionIDs []string, maxSelections int, ok bool) {
	var c event.PollStartEventContent
	if json.Unmarshal(content, &c) != nil || len(c.PollStart.Answers) == 0 {
		return nil, 0, false
	}
	for _, o := range c.PollStart.Answers {
		optionIDs = append(optionIDs, o.ID)
	}
	return optionIDs, max(c.PollStart.MaxSelections, 1), true
}

// Vote chooses options of a poll, by ID, and returns the ID of the stored vote. It names 0 to the poll's
// max_selections options it has, each once (else ErrBadValue); none takes my vote back. The poll must be one, in a
// chat that takes polls, not deleted and not ended (else ErrNotSupported).
func (a *Actions) Vote(ctx context.Context, pollEventID string, optionIDs []string) (string, error) {
	poll, redacted, err := a.stored(ctx, pollEventID)
	if err != nil {
		return "", err
	}
	if poll.Type != event.EventUnstablePollStart.Type || redacted {
		return "", ErrNotSupported
	}
	known, maxSelections, ok := pollOf(poll.Content)
	if !ok {
		return "", ErrNotSupported
	}
	if len(optionIDs) > maxSelections {
		return "", ErrBadValue
	}
	for i, o := range optionIDs {
		if !slices.Contains(known, o) || slices.Contains(optionIDs[:i], o) {
			return "", ErrBadValue
		}
	}
	h, err := a.eng.HostForRoom(ctx, poll.RoomID)
	if err != nil {
		return "", err
	}
	f, err := a.Features(ctx, poll.RoomID)
	if err != nil {
		return "", err
	}
	if f.Poll == nil {
		return "", ErrNotSupported
	}
	tallies, err := a.s.PollTallies(ctx, poll.RoomID, []string{pollEventID})
	if err != nil {
		return "", err
	}
	if tallies[pollEventID].Ended {
		return "", ErrNotSupported
	}
	if err = WaitForLogin(ctx, h, a.LoginWait); err != nil {
		return "", err
	}
	return a.submit(ctx, h, poll.RoomID, event.EventUnstablePollResponse, &event.PollResponseEventContent{
		RelatesTo: event.RelatesTo{Type: event.RelReference, EventID: id.EventID(pollEventID)},
		Response:  event.PollResponse{Answers: append([]string{}, optionIDs...)},
	})
}
