// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"
)

// articleRead is article.read: the main text of a web page, for "Summarize" on a link card (protocol 14). The page
// is fetched with the link-preview client's limits (actions.ReadArticle). A page that can't be read is an answer
// (needs_browser), not an error; an address that isn't an https link is -32014.
func articleRead(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		URL *string `json:"url"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("url", p.URL); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return d.Actions.ReadArticle(ctx, *p.URL)
}
