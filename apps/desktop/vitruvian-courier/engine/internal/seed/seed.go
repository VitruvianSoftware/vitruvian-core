// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package seed plays a made-up scenario (apps/desktop/vitruvian-courier/seed/scenarios, README.md beside them) into fake
// networks, so the Vitruvian Courier Test Copy opens already full of chats. Only the test copy's engine links it: the
// vitruvian-courier-engine-seeded binary, built with the Go build tag courierseed (cmd/vitruvian-courier-engine/seed_on.go). The
// released engine is built without the tag and must not hold this package; the app's
// release_engine_has_no_seed_test looks for Marker in it.
package seed

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"time"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/fakenet"
)

// Marker is a string only this package's code holds, written into the played marker file (PlayedFile), so the
// linker keeps it: a binary that contains it links the seed player. The app's release_engine_has_no_seed_test
// fails when the released engine contains it, and when the test copy's engine doesn't.
const Marker = "courier-seed-player:9f3c1e7a"

// PlayedFile is the file in the data directory that says a scenario has been played into it.
const PlayedFile = "seeded"

// Me is the "from" of my own messages and reactions.
const Me = "me"

// Scenario is one scenario file.
type Scenario struct {
	Accounts []Account `json:"accounts"`
	People   []Person  `json:"people"`
	Chats    []Chat    `json:"chats"`
}

// Account is one sign-in: Network is a real network's name ("whatsapp"), Login the account's ID, Name what it is
// called.
type Account struct {
	Network string `json:"network"`
	Login   string `json:"login"`
	Name    string `json:"name"`
}

// Person is someone other than me, by the ID chats and messages use.
type Person struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// Chat is one chat on one account (Account names a Login).
type Chat struct {
	Account  string    `json:"account"`
	ID       string    `json:"id"`
	Name     string    `json:"name"`
	Direct   bool      `json:"direct"`
	Members  []string  `json:"members"`
	Pinned   bool      `json:"pinned"`
	Muted    bool      `json:"muted"`
	Unread   bool      `json:"unread"`
	Messages []Message `json:"messages"`
}

// Message is one text message. From is a person's ID or Me; ReplyTo and Thread (the thread's root) name earlier
// messages of the same chat.
type Message struct {
	ID         string     `json:"id"`
	From       string     `json:"from"`
	MinutesAgo int        `json:"minutesAgo"`
	Text       string     `json:"text"`
	ReplyTo    string     `json:"replyTo,omitempty"`
	Thread     string     `json:"thread,omitempty"`
	Reactions  []Reaction `json:"reactions,omitempty"`
}

// Reaction is one person's (or my) emoji on a message.
type Reaction struct {
	From  string `json:"from"`
	Emoji string `json:"emoji"`
}

// networkName is a network's name as the engine takes it (engine.validName).
var networkName = regexp.MustCompile(`^[a-z]+$`)

// Load reads and checks the scenario file at path.
func Load(path string) (*Scenario, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read the seed scenario: %w", err)
	}
	s, err := Parse(b)
	if err != nil {
		return nil, fmt.Errorf("seed scenario %s: %w", filepath.Base(path), err)
	}
	return s, nil
}

// Parse decodes a scenario, refusing unknown fields, and checks it (Check).
func Parse(b []byte) (*Scenario, error) {
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.DisallowUnknownFields()
	var s Scenario
	if err := dec.Decode(&s); err != nil {
		return nil, err
	}
	if err := s.Check(); err != nil {
		return nil, err
	}
	return &s, nil
}

// Check says what is wrong with the scenario, every problem joined, or nil: IDs unique within their kind, every
// reference to an account, person or message there, a direct chat with exactly one other member, no time in the
// future, and a reply or thread reply no older than what it answers.
func (s *Scenario) Check() error {
	var errs []error
	bad := func(format string, args ...any) { errs = append(errs, fmt.Errorf(format, args...)) }
	logins := map[string]bool{}
	for _, a := range s.Accounts {
		switch {
		case !networkName.MatchString(a.Network):
			bad("account %q: network %q must be lowercase letters only", a.Login, a.Network)
		case a.Login == "":
			bad("an account on %s has no login", a.Network)
		case logins[a.Login]:
			bad("account %q is listed twice", a.Login)
		}
		logins[a.Login] = true
	}
	people := map[string]bool{}
	for _, p := range s.People {
		switch {
		case p.ID == "" || p.ID == Me:
			bad("a person's id may be neither empty nor %q", Me)
		case people[p.ID]:
			bad("person %q is listed twice", p.ID)
		case p.Name == "":
			bad("person %q has no name", p.ID)
		}
		people[p.ID] = true
	}
	chats := map[string]bool{}
	for _, c := range s.Chats {
		where := fmt.Sprintf("chat %q", c.ID)
		key := c.Account + "\x00" + c.ID
		switch {
		case c.ID == "":
			bad("a chat on %q has no id", c.Account)
		case !logins[c.Account]:
			bad("%s: account %q is not in accounts", where, c.Account)
		case chats[key]:
			bad("%s is listed twice on %q", where, c.Account)
		}
		chats[key] = true
		for _, m := range c.Members {
			if !people[m] {
				bad("%s: member %q is not in people", where, m)
			}
		}
		if c.Direct && len(c.Members) != 1 {
			bad("%s is direct, so it needs exactly one member (the other person), not %d", where, len(c.Members))
		}
		if !c.Direct && c.Name == "" {
			bad("%s is a group and has no name", where)
		}
		ago := map[string]int{} // minutesAgo by message ID
		for _, m := range c.Messages {
			_, seen := ago[m.ID]
			switch {
			case m.ID == "":
				bad("%s: a message has no id", where)
			case seen:
				bad("%s: message %q is listed twice", where, m.ID)
			}
			ago[m.ID] = m.MinutesAgo
		}
		for _, m := range c.Messages {
			at := fmt.Sprintf("%s, message %q", where, m.ID)
			if m.From != Me && !people[m.From] {
				bad("%s: from %q is neither %q nor in people", at, m.From, Me)
			}
			if m.MinutesAgo < 0 {
				bad("%s: minutesAgo %d is in the future", at, m.MinutesAgo)
			}
			for _, ref := range [][2]string{{"replyTo", m.ReplyTo}, {"thread", m.Thread}} {
				field, target := ref[0], ref[1]
				if target == "" {
					continue
				}
				targetAgo, ok := ago[target]
				switch {
				case target == m.ID:
					bad("%s: %s names the message itself", at, field)
				case !ok:
					bad("%s: %s %q is not a message of this chat", at, field, target)
				case targetAgo < m.MinutesAgo:
					bad("%s: %s %q was sent after it", at, field, target)
				}
			}
			for _, r := range m.Reactions {
				if r.From != Me && !people[r.From] {
					bad("%s: a reaction from %q is neither %q nor in people", at, r.From, Me)
				}
				if r.Emoji == "" {
					bad("%s: a reaction from %q has no emoji", at, r.From)
				}
			}
		}
	}
	return errors.Join(errs...)
}

// Networks is the scenario's networks, each once, in the order its accounts first name them.
func (s *Scenario) Networks() []string {
	var out []string
	seen := map[string]bool{}
	for _, a := range s.Accounts {
		if !seen[a.Network] {
			seen[a.Network] = true
			out = append(out, a.Network)
		}
	}
	return out
}

// Name is the person's name, or the ID when the scenario doesn't name them.
func (s *Scenario) Name(personID string) string {
	for _, p := range s.People {
		if p.ID == personID {
			return p.Name
		}
	}
	return personID
}

func (s *Scenario) account(login string) Account {
	for _, a := range s.Accounts {
		if a.Login == login {
			return a
		}
	}
	return Account{}
}

// Ordered is the chat's messages oldest first; messages sent at the same minute keep the file's order.
func (c Chat) Ordered() []Message {
	out := append([]Message(nil), c.Messages...)
	sort.SliceStable(out, func(i, j int) bool { return out[i].MinutesAgo > out[j].MinutesAgo })
	return out
}

// Prepare tells each network, before its bridge starts, what it needs to describe the scenario's chats and people
// whenever the bridge asks, on this start or a later one: every person's name (fakenet's People) and every chat's
// name, members, pin and mute (SetChat). nets holds a fake per network the scenario names.
func (s *Scenario) Prepare(nets map[string]*fakenet.Network) error {
	people := make(map[string]string, len(s.People))
	for _, p := range s.People {
		people[p.ID] = p.Name
	}
	for _, name := range s.Networks() {
		n, ok := nets[name]
		if !ok {
			return fmt.Errorf("no fake network for %s", name)
		}
		n.People = people
	}
	for _, c := range s.Chats {
		n := nets[s.account(c.Account).Network]
		name := c.Name
		if name == "" && c.Direct {
			name = s.Name(c.Members[0])
		}
		direct := c.Direct
		ch := fakenet.Chat{Name: &name, Direct: &direct, Members: append([]string{}, c.Members...)}
		if c.Pinned {
			tag := event.RoomTagFavourite
			ch.Tag = &tag
		}
		if c.Muted {
			until := event.MutedForever
			ch.MutedUntil = &until
		}
		n.SetChat(c.ID, ch)
	}
	return nil
}

// Play signs in each account (connected) and queues every chat's messages, oldest first, each at its own past time (now less
// minutesAgo), then the reactions, then, for a chat that isn't unread, my read receipt up to its last message. The
// bridges handle what is queued in order, chat by chat, after Play returns. bridges and nets hold each network the
// scenario names, already started, with Prepare done.
func (s *Scenario) Play(ctx context.Context, bridges map[string]*bridgev2.Bridge, nets map[string]*fakenet.Network, now time.Time) error {
	logins := map[string]*bridgev2.UserLogin{}
	for _, a := range s.Accounts {
		br, n := bridges[a.Network], nets[a.Network]
		if br == nil || n == nil {
			return fmt.Errorf("account %q: %s is not running", a.Login, a.Network)
		}
		l, err := n.LoginAs(ctx, br, a.Login, a.Name)
		if err != nil {
			return fmt.Errorf("sign in account %q: %w", a.Login, err)
		}
		// Say it is connected, as a real login's first state does: the app lists the account by its name from that.
		n.SetLoggedIn(l, true)
		logins[a.Login] = l
	}
	for _, c := range s.Chats {
		n, login := nets[s.account(c.Account).Network], logins[c.Account]
		ordered := c.Ordered()
		for _, m := range ordered {
			n.IncomingMessage(login, c.ID, fakenet.Message{
				ID: m.ID, Body: m.Text, SenderID: m.From, FromMe: m.From == Me,
				At:      now.Add(-time.Duration(m.MinutesAgo) * time.Minute),
				ReplyTo: m.ReplyTo, ThreadRoot: m.Thread,
			})
		}
		for _, m := range ordered {
			for i, r := range m.Reactions {
				// A reaction lands just after its message, in the file's order.
				at := now.Add(-time.Duration(m.MinutesAgo)*time.Minute + time.Duration(i+1)*time.Second)
				n.IncomingReaction(login, c.ID, r.From, m.ID, r.Emoji, at)
			}
		}
		if !c.Unread && len(ordered) > 0 {
			n.Receipt(login, c.ID, Me, []string{ordered[len(ordered)-1].ID}, false)
		}
	}
	return nil
}

// Played says whether a scenario has been played into dataDir (its PlayedFile is there).
func Played(dataDir string) (bool, error) {
	_, err := os.Stat(filepath.Join(dataDir, PlayedFile))
	if err == nil {
		return true, nil
	}
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	return false, err
}

// MarkPlayed writes dataDir's PlayedFile, naming the scenario played.
func MarkPlayed(dataDir, scenario string) error {
	body := fmt.Sprintf("%s\nscenario: %s\n", Marker, filepath.Base(scenario))
	return os.WriteFile(filepath.Join(dataDir, PlayedFile), []byte(body), 0o600)
}
