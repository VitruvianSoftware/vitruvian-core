// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func peopleContacts(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Network   *string `json:"network"`
		AccountID *string `json:"account_id"`
		Query     *string `json:"query"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	network := ""
	if p.Network != nil {
		network = *p.Network
	}
	accountID := ""
	if p.AccountID != nil {
		accountID = *p.AccountID
	}
	query := ""
	if p.Query != nil {
		query = *p.Query
	}
	contacts, err := d.Actions.ListContacts(ctx, network, accountID, query)
	if err != nil {
		return nil, err
	}
	if contacts == nil {
		contacts = []actions.ContactCandidate{}
	}
	return map[string]any{"contacts": contacts}, nil
}

func peopleResolve(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Network    *string `json:"network"`
		AccountID  *string `json:"account_id"`
		Identifier *string `json:"identifier"`
		StartChat  bool    `json:"start_chat"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("network", p.Network); err != nil {
		return nil, err
	}
	if err := required("identifier", p.Identifier); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	accountID := ""
	if p.AccountID != nil {
		accountID = *p.AccountID
	}
	return d.Actions.ResolveIdentifier(ctx, *p.Network, accountID, *p.Identifier, p.StartChat)
}

func roomCreateGroup(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Network   *string   `json:"network"`
		AccountID *string   `json:"account_id"`
		Name      *string   `json:"name"`
		UserIDs   *[]string `json:"user_ids"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("network", p.Network); err != nil {
		return nil, err
	}
	if err := required("name", p.Name); err != nil {
		return nil, err
	}
	if p.UserIDs == nil {
		return nil, invalidParams("user_ids is required")
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	accountID := ""
	if p.AccountID != nil {
		accountID = *p.AccountID
	}
	roomID, err := d.Actions.CreateGroup(ctx, *p.Network, accountID, *p.Name, *p.UserIDs)
	if err != nil {
		return nil, err
	}
	return roomResult{RoomID: roomID}, nil
}

func blastSend(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomIDs *[]string `json:"room_ids"`
		Text    *string   `json:"text"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	ids, err := roomIDList(p.RoomIDs, maxBulkRoomIDs)
	if err != nil {
		return nil, err
	}
	if err := textParam(p.Text, nil); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	evs, err := d.Actions.SendBlast(ctx, ids, *p.Text)
	if err != nil {
		return nil, err
	}
	senders := map[string]sender{}
	out := make([]eventJSON, 0, len(evs))
	for _, e := range evs {
		if e.EventID != "" {
			revs, err := d.toEvents(ctx, e.RoomID, []store.Event{e}, senders)
			if err != nil {
				return nil, err
			}
			if len(revs) > 0 {
				out = append(out, revs[0])
				continue
			}
		}
		ev, err := d.toEvent(ctx, e, senders)
		if err != nil {
			return nil, err
		}
		out = append(out, ev)
	}
	return map[string]any{"events": out}, nil
}
