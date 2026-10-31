// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"errors"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"
)

// Client implements bridgev2.NetworkAPI for a Google Chat UserLogin.
type Client struct {
	Main      *Connector
	UserLogin *bridgev2.UserLogin
}

var _ bridgev2.NetworkAPI = (*Client)(nil)

func (c *Client) Connect(_ context.Context) {}

func (c *Client) Disconnect() {}

func (c *Client) IsLoggedIn() bool {
	if c.UserLogin == nil {
		return false
	}
	meta, _ := c.UserLogin.Metadata.(*UserLoginMetadata)
	return meta != nil && len(meta.Cookies) > 0
}

func (c *Client) LogoutRemote(_ context.Context) {
	if c.UserLogin != nil {
		if meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata); ok && meta != nil {
			meta.Cookies = nil
		}
	}
}

func (c *Client) IsThisUser(_ context.Context, userID networkid.UserID) bool {
	return c.UserLogin != nil && string(userID) == string(c.UserLogin.ID)
}

func (c *Client) GetChatInfo(_ context.Context, _ *bridgev2.Portal) (*bridgev2.ChatInfo, error) {
	return nil, errors.New("not implemented")
}

func (c *Client) GetUserInfo(_ context.Context, _ *bridgev2.Ghost) (*bridgev2.UserInfo, error) {
	return nil, errors.New("not implemented")
}

func (c *Client) GetCapabilities(_ context.Context, _ *bridgev2.Portal) *event.RoomFeatures {
	return &event.RoomFeatures{}
}

func (c *Client) HandleMatrixMessage(_ context.Context, _ *bridgev2.MatrixMessage) (*bridgev2.MatrixMessageResponse, error) {
	return nil, errors.New("not implemented")
}

func (c *Client) FillBridgeState(state status.BridgeState) status.BridgeState {
	return state
}
