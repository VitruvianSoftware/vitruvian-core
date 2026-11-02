// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/VitruvianSoftware/courier/engine/internal/localapi"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Settings → Integrations (milestone 5): the local API's settings and status, its tokens, and the answer to a
// pairing request. A token's secret crosses the socket once, in integrations.createToken's answer; its hash never
// does. The new methods' keys are camelCase, as the milestone 5 plan names them.

// apiTokenJSON is an APIToken on the wire.
type apiTokenJSON struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	CanSend    bool   `json:"canSend"`
	CreatedMS  int64  `json:"createdMs"`
	LastUsedMS *int64 `json:"lastUsedMs"`
}

func toAPIToken(t store.APIToken) apiTokenJSON {
	out := apiTokenJSON{ID: t.ID, Name: t.Name, CanSend: t.CanSend, CreatedMS: t.Created.UnixMilli()}
	if !t.LastUsed.IsZero() {
		ms := t.LastUsed.UnixMilli()
		out.LastUsedMS = &ms
	}
	return out
}

func (d *Deps) localAPI() (*localapi.Server, error) {
	if d.LocalAPI == nil {
		return nil, errMissing
	}
	return d.LocalAPI, nil
}

func integrationsStatus(_ context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	api, err := d.localAPI()
	if err != nil {
		return nil, err
	}
	return api.Status(), nil
}

// integrationsUpdate changes the local API's settings, saves them and applies them at once: turning connections on
// or off, moving the port, or turning Remote Access on or off needs no relaunch. What is left out stays as it was.
func integrationsUpdate(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Enabled *bool `json:"enabled"`
		Port    *int  `json:"port"`
		Remote  *bool `json:"remote"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	api, err := d.localAPI()
	if err != nil {
		return nil, err
	}
	set, err := d.Store.LocalAPI(ctx)
	if err != nil {
		return nil, err
	}
	if p.Enabled != nil {
		set.Enabled = *p.Enabled
	}
	if p.Port != nil {
		if *p.Port < store.MinLocalAPIPort || *p.Port > store.MaxLocalAPIPort {
			return nil, invalidParams(fmt.Sprintf("port must be %d to %d", store.MinLocalAPIPort, store.MaxLocalAPIPort))
		}
		set.Port = *p.Port
	}
	if p.Remote != nil {
		set.Remote = *p.Remote
	}
	if err := d.Store.SetLocalAPI(ctx, set); err != nil {
		return nil, err
	}
	return api.Apply(ctx, localapi.Config{Enabled: set.Enabled, Port: set.Port, Remote: set.Remote}), nil
}

func integrationsTokens(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	toks, err := d.Store.ListAPITokens(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]apiTokenJSON, 0, len(toks))
	for _, t := range toks {
		out = append(out, toAPIToken(t))
	}
	return out, nil
}

func integrationsCreateToken(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Name    *string `json:"name"`
		CanSend bool    `json:"canSend"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if p.Name == nil {
		return nil, invalidParams("name is required")
	}
	tok, secret, err := d.Store.CreateAPIToken(ctx, *p.Name, p.CanSend)
	if err != nil {
		return nil, err
	}
	return struct {
		Token  apiTokenJSON `json:"token"`
		Secret string       `json:"secret"`
	}{toAPIToken(tok), secret}, nil
}

func integrationsRevokeToken(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		ID *string `json:"id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("id", p.ID); err != nil {
		return nil, err
	}
	return nil, d.Store.RevokeAPIToken(ctx, *p.ID)
}

func integrationsSetCanSend(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		ID      *string `json:"id"`
		CanSend *bool   `json:"canSend"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("id", p.ID); err != nil {
		return nil, err
	}
	if p.CanSend == nil {
		return nil, invalidParams("canSend is required")
	}
	return nil, d.Store.SetAPITokenCanSend(ctx, *p.ID, *p.CanSend)
}

func integrationsAnswerPairing(_ context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RequestID *string `json:"requestID"`
		Allow     *bool   `json:"allow"`
		CanSend   bool    `json:"canSend"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("requestID", p.RequestID); err != nil {
		return nil, err
	}
	if p.Allow == nil {
		return nil, invalidParams("allow is required")
	}
	api, err := d.localAPI()
	if err != nil {
		return nil, err
	}
	if err := api.AnswerPairing(*p.RequestID, *p.Allow, p.CanSend); errors.Is(err, localapi.ErrNoSuchPairing) {
		return nil, errNotFound
	} else if err != nil {
		return nil, err
	}
	return nil, nil
}

// appSetLocked is the app saying whether it is locked, at each connect and each time it locks or unlocks, so that
// focus_app tells its client the truth.
func appSetLocked(_ context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Locked *bool `json:"locked"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if p.Locked == nil {
		return nil, invalidParams("locked is required")
	}
	api, err := d.localAPI()
	if err != nil {
		return nil, err
	}
	api.SetAppLocked(*p.Locked)
	return nil, nil
}
