// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"errors"
	"sync"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"
)

// Client implements bridgev2.NetworkAPI for a Google Chat UserLogin.
type Client struct {
	Main      *Connector
	UserLogin *bridgev2.UserLogin

	mu        sync.Mutex
	metaMu    sync.Mutex
	ffiClient *FFIClient
}

var _ bridgev2.NetworkAPI = (*Client)(nil)

func (c *Client) Connect(_ context.Context) {}

func (c *Client) Disconnect() {
	c.mu.Lock()
	ffi := c.ffiClient
	c.ffiClient = nil
	c.mu.Unlock()
	if ffi != nil {
		ffi.Close()
	}
}

func (c *Client) ensureFFIClient() (*FFIClient, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.ffiClient != nil {
		return c.ffiClient, nil
	}
	if c.UserLogin == nil {
		return nil, errors.New("gchat client has no UserLogin")
	}
	meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata)
	if !ok || meta == nil || len(meta.Cookies) == 0 {
		return nil, errors.New("gchat UserLogin has no stored cookies")
	}
	var baseURL string
	if c.Main != nil {
		baseURL = c.Main.baseURL
	}
	ffi, err := NewFFIClient(SessionConfig{
		CookieMap: meta.Cookies,
		UserAgent: meta.UserAgent,
		BaseURL:   baseURL,
	})
	if err != nil {
		return nil, err
	}
	c.ffiClient = ffi
	return ffi, nil
}

func (c *Client) rpcCall(_ context.Context, endpoint string, reqProto []byte) ([]byte, error) {
	ffi, err := c.ensureFFIClient()
	if err != nil {
		return nil, err
	}
	return ffi.RPCCall(endpoint, reqProto)
}

func (c *Client) ownUserID() networkid.UserID {
	if c.UserLogin == nil {
		return ""
	}
	return MakeUserID(string(c.UserLogin.ID))
}

func (c *Client) IsLoggedIn() bool {
	if c.UserLogin == nil {
		return false
	}
	meta, _ := c.UserLogin.Metadata.(*UserLoginMetadata)
	return meta != nil && len(meta.Cookies) > 0
}

func (c *Client) LogoutRemote(_ context.Context) {
	c.Disconnect()
	if c.UserLogin != nil {
		if meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata); ok && meta != nil {
			meta.Cookies = nil
		}
	}
}

func (c *Client) IsThisUser(_ context.Context, userID networkid.UserID) bool {
	return c.UserLogin != nil && string(userID) == string(c.UserLogin.ID)
}

func (c *Client) GetChatInfo(_ context.Context, portal *bridgev2.Portal) (*bridgev2.ChatInfo, error) {
	isDM, _, err := ParsePortalID(portal.ID)
	if err != nil {
		return nil, err
	}
	roomType := database.RoomTypeDefault
	if isDM {
		roomType = database.RoomTypeDM
	}
	return &bridgev2.ChatInfo{
		Type:        &roomType,
		CanBackfill: true,
	}, nil
}

func (c *Client) GetUserInfo(_ context.Context, ghost *bridgev2.Ghost) (*bridgev2.UserInfo, error) {
	name := string(ghost.ID)
	if ghost.Name != "" {
		name = ghost.Name
	}
	return &bridgev2.UserInfo{
		Name: &name,
	}, nil
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
