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
	"sync"
	"time"

	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Pairing lets a client ask for a token instead of the person pasting one: POST /v0/pair {"clientName": "..."}.
// It needs no token, and the same guards as everything else apply (no Origin; with Remote Access off, a loopback
// Host), so it can be reached from another machine only with Remote Access on. The app shows the person the
// client's name (cleaned, and still untrusted) and asks; Allow answers 200 {"token": "<secret>"}, and Don't Allow, or
// no answer within PairTimeout, answers 403. One request waits at a time: another meanwhile is 429.

const (
	// PairPath is where a client asks to be approved.
	PairPath = "/v0/pair"
	// PairTimeout is how long a pairing request waits for the person.
	PairTimeout = 120 * time.Second
	// NoticePairRequest is the notification that asks the app to show the prompt.
	NoticePairRequest = "integrations.pairRequest"
)

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
}

type pairing struct {
	mu      sync.Mutex
	pending *pendingPair
	timeout time.Duration // PairTimeout unless a test sets it
}

// SetPairTimeout changes how long a pairing request waits, for tests.
func (s *Server) SetPairTimeout(d time.Duration) {
	s.pairs.mu.Lock()
	s.pairs.timeout = d
	s.pairs.mu.Unlock()
}

// AnswerPairing is the person's answer to the waiting pairing request requestID: allow, and whether the new token
// may send messages.
func (s *Server) AnswerPairing(requestID string, allow, canSend bool) error {
	s.pairs.mu.Lock()
	defer s.pairs.mu.Unlock()
	p := s.pairs.pending
	if p == nil || p.id != requestID {
		return ErrNoSuchPairing
	}
	s.pairs.pending = nil
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
	if s.pairs.pending != nil {
		s.pairs.mu.Unlock()
		writeError(w, http.StatusTooManyRequests, "another pairing request is waiting")
		return
	}
	s.pairs.pending = p
	timeout := s.pairs.timeout
	s.pairs.mu.Unlock()
	if timeout <= 0 {
		timeout = PairTimeout
	}
	defer s.dropPairing(p)

	if s.pub == nil || s.pub.Publish(NoticePairRequest, PairRequest{RequestID: p.id, ClientName: name}) == 0 {
		s.log.Info().Str("outcome", "no_app").Msg("pairing request")
		writeError(w, http.StatusForbidden, "denied")
		return
	}
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	var a pairAnswer
	select {
	case a = <-p.answer:
	case <-timer.C:
		s.log.Info().Str("outcome", "timeout").Msg("pairing request")
		writeError(w, http.StatusForbidden, "denied")
		return
	case <-r.Context().Done():
		return // the client gave up
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
	s.log.Info().Str("outcome", "allowed").Bool("can_send", a.canSend).Msg("pairing request")
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(map[string]string{"token": secret})
}

// dropPairing forgets p if it is still the request waiting.
func (s *Server) dropPairing(p *pendingPair) {
	s.pairs.mu.Lock()
	if s.pairs.pending == p {
		s.pairs.pending = nil
	}
	s.pairs.mu.Unlock()
}
