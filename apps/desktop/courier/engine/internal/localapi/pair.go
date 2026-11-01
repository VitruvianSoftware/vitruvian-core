// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Pairing lets a client ask for a token instead of the person pasting one: POST /v0/pair {"clientName": "..."}.
// It needs no token, and the same guards as everything else apply (no Origin; with Remote Access off, a loopback
// Host), so it can be reached from another machine only with Remote Access on. The app shows the person the
// client's name (cleaned, and still untrusted) and asks; Allow answers 200 {"token": "<secret>"}, and Don't Allow, or
// no answer within PairTimeout, answers 403. One request waits at a time: another meanwhile is 429.
//
// So that a client can't keep a prompt in front of the person by asking, hanging up and asking again:
//   - a request holds the one slot until the person answers or PairTimeout passes, even after its client has gone
//     (and an Allow for a client that has gone makes no token);
//   - after a request ends without an Allow (Don't Allow, no answer, the client gone, no app to ask), new requests
//     are 429 for a cooldown: PairCooldown, doubling with each such request in a row, at most PairCooldownMax, and
//     back to none after an Allow;
//   - integrations.pairEnded tells the app as soon as a request is over for it (answered, timed out, or its client
//     gone), so it can take the prompt down.

const (
	// PairPath is where a client asks to be approved.
	PairPath = "/v0/pair"
	// PairTimeout is how long a pairing request waits for the person.
	PairTimeout = 120 * time.Second
	// NoticePairRequest is the notification that asks the app to show the prompt.
	NoticePairRequest = "integrations.pairRequest"
	// NoticePairEnded tells the app a request is over: answered, timed out, or its client gone.
	NoticePairEnded = "integrations.pairEnded"
	// PairCooldown is how long new requests are refused after one that ended without an Allow; it doubles with each
	// such request in a row, up to PairCooldownMax.
	PairCooldown    = 10 * time.Second
	PairCooldownMax = 5 * time.Minute
)

// PairEnded is the integrations.pairEnded notification's params.
type PairEnded struct {
	RequestID string `json:"requestID"`
}

// ErrNoSuchPairing is AnswerPairing's error for a request that isn't waiting (answered already, timed out, or never
// made).
var ErrNoSuchPairing = errors.New("no pairing request is waiting with that ID")

// PairRequest is the integrations.pairRequest notification's params.
type PairRequest struct {
	RequestID  string `json:"requestID"`
	ClientName string `json:"clientName"`
}

type pairAnswer struct{ allow, canSend bool }

type pendingPair struct {
	id     string
	answer chan pairAnswer // buffered 1: AnswerPairing never waits
	closed bool            // answered, or past its time: no more answers (guarded by pairing.mu)
}

type pairing struct {
	mu       sync.Mutex
	pending  *pendingPair
	timeout  time.Duration // PairTimeout unless a test sets it
	cooldown time.Duration // PairCooldown unless a test sets it
	refused  int           // requests in a row that ended without an Allow
	until    time.Time     // new requests are 429 until then
}

// SetPairTimeout changes how long a pairing request waits, for tests.
func (s *Server) SetPairTimeout(d time.Duration) {
	s.pairs.mu.Lock()
	s.pairs.timeout = d
	s.pairs.mu.Unlock()
}

// SetPairCooldown changes the first cooldown after a request without an Allow (it still doubles, up to
// PairCooldownMax), for tests.
func (s *Server) SetPairCooldown(d time.Duration) {
	s.pairs.mu.Lock()
	s.pairs.cooldown = d
	s.pairs.mu.Unlock()
}

// endPairing frees the slot p holds, if it still does, and starts or clears the cooldown: allowed resets it,
// anything else doubles it.
func (s *Server) endPairing(p *pendingPair, allowed bool) {
	s.pairs.mu.Lock()
	defer s.pairs.mu.Unlock()
	if s.pairs.pending == p {
		s.pairs.pending = nil
	}
	if allowed {
		s.pairs.refused, s.pairs.until = 0, time.Time{}
		return
	}
	base := s.pairs.cooldown
	if base <= 0 {
		base = PairCooldown
	}
	d := base
	for i := 0; i < s.pairs.refused && d < PairCooldownMax; i++ {
		d *= 2
	}
	s.pairs.refused++
	s.pairs.until = time.Now().Add(min(d, PairCooldownMax))
}

// AnswerPairing is the person's answer to the waiting pairing request requestID: allow, and whether the new token
// may send messages.
func (s *Server) AnswerPairing(requestID string, allow, canSend bool) error {
	s.pairs.mu.Lock()
	defer s.pairs.mu.Unlock()
	p := s.pairs.pending
	if p == nil || p.id != requestID || p.closed {
		return ErrNoSuchPairing
	}
	// The slot stays taken until the request's handler has ended it and set the cooldown (endPairing), so no new
	// request slips in between.
	p.closed = true
	p.answer <- pairAnswer{allow: allow, canSend: canSend}
	return nil
}

func (s *Server) servePair(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	var body struct {
		ClientName string `json:"clientName"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			writeError(w, http.StatusRequestEntityTooLarge, "request too large")
			return
		}
		writeError(w, http.StatusBadRequest, "bad request")
		return
	}
	idBytes := make([]byte, 12)
	if _, err := rand.Read(idBytes); err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	p := &pendingPair{id: "pair_" + hex.EncodeToString(idBytes), answer: make(chan pairAnswer, 1)}
	name := store.CleanClientName(body.ClientName)

	s.pairs.mu.Lock()
	if s.pairs.pending != nil || time.Now().Before(s.pairs.until) {
		wait := time.Until(s.pairs.until)
		s.pairs.mu.Unlock()
		if wait > 0 {
			w.Header().Set("Retry-After", strconv.Itoa(int(wait.Round(time.Second)/time.Second)+1))
		}
		writeError(w, http.StatusTooManyRequests, "try again later")
		return
	}
	s.pairs.pending = p
	timeout := s.pairs.timeout
	s.pairs.mu.Unlock()
	if timeout <= 0 {
		timeout = PairTimeout
	}
	allowed := false
	defer func() { s.endPairing(p, allowed) }()

	if s.pub == nil || s.pub.Publish(NoticePairRequest, PairRequest{RequestID: p.id, ClientName: name}) == 0 {
		s.log.Info().Str("outcome", "no_app").Msg("pairing request")
		writeError(w, http.StatusForbidden, "denied")
		return
	}
	ended := false // integrations.pairEnded has gone out
	end := func() {
		if !ended {
			ended = true
			s.pub.Publish(NoticePairEnded, PairEnded{RequestID: p.id})
		}
	}
	defer end()
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	gone := r.Context().Done()
	var a pairAnswer
wait:
	for {
		select {
		case a = <-p.answer:
			break wait
		case <-timer.C:
			s.closePairing(p) // an answer from now on is too late
			s.log.Info().Str("outcome", "timeout").Msg("pairing request")
			writeError(w, http.StatusForbidden, "denied")
			return
		case <-gone:
			// The client hung up. The prompt comes down, but the slot stays taken until the person answers or the
			// time is up, so hanging up and asking again doesn't put a new prompt up.
			gone = nil
			end()
		}
	}
	end()
	if r.Context().Err() != nil {
		s.log.Info().Str("outcome", "client_gone").Msg("pairing request")
		return // nobody to give a token to: none is made
	}
	if !a.allow {
		s.log.Info().Str("outcome", "denied").Msg("pairing request")
		writeError(w, http.StatusForbidden, "denied")
		return
	}
	_, secret, err := s.store.CreateAPIToken(context.WithoutCancel(r.Context()), name, a.canSend)
	if err != nil {
		s.log.Warn().Msg("couldn't make a token for a pairing request")
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	allowed = true
	s.log.Info().Str("outcome", "allowed").Bool("can_send", a.canSend).Msg("pairing request")
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(map[string]string{"token": secret})
}

// closePairing takes no more answers for p.
func (s *Server) closePairing(p *pendingPair) {
	s.pairs.mu.Lock()
	p.closed = true
	s.pairs.mu.Unlock()
}
