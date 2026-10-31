// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"errors"
	"strings"
	"sync"
	"time"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"
)

type streamNotification struct {
	kind    int32
	payload []byte
}

// Client implements bridgev2.NetworkAPI for a Google Chat UserLogin.
type Client struct {
	Main      *Connector
	UserLogin *bridgev2.UserLogin

	mu               sync.Mutex
	metaMu           sync.Mutex
	syncMu           sync.Mutex
	ffiClient        *FFIClient
	cancelStream     context.CancelFunc
	streamDone       chan struct{}
	initialSyncDone  bool
	useManualClock   bool
	manualJitter     float64
	dispatchedMsgIDs map[string]struct{}
	emittedEvents    []bridgev2.RemoteEvent
	lastState        status.BridgeStateEvent
}

var _ bridgev2.NetworkAPI = (*Client)(nil)

func hasRequiredCookies(cookies map[string]string) bool {
	if len(cookies) == 0 {
		return false
	}
	for _, k := range []string{"COMPASS", "OSID", "SID", "HSID", "SSID"} {
		if strings.TrimSpace(cookies[k]) == "" {
			return false
		}
	}
	return true
}

func (c *Client) sendBridgeState(st status.BridgeState) {
	c.mu.Lock()
	c.lastState = st.StateEvent
	c.mu.Unlock()
	if c.UserLogin != nil {
		c.UserLogin.BridgeState.Send(st)
	}
}

func (c *Client) lastBridgeState() status.BridgeStateEvent {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.lastState
}

func (c *Client) Connect(ctx context.Context) {
	if c.UserLogin == nil {
		return
	}
	meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata)
	if !ok || meta == nil || !hasRequiredCookies(meta.Cookies) {
		c.sendBridgeState(status.BridgeState{
			StateEvent: status.StateBadCredentials,
			Error:      "gchat-missing-cookies",
			UserAction: status.UserActionRelogin,
		})
		return
	}

	c.mu.Lock()
	if c.cancelStream != nil {
		c.cancelStream()
		c.cancelStream = nil
	}
	streamCtx, cancel := context.WithCancel(context.Background())
	doneCh := make(chan struct{})
	c.cancelStream = cancel
	c.streamDone = doneCh
	c.initialSyncDone = false
	if c.dispatchedMsgIDs == nil {
		c.dispatchedMsgIDs = make(map[string]struct{})
	}
	c.mu.Unlock()

	ffi, err := c.ensureFFIClient()
	if err != nil {
		cancel()
		close(doneCh)
		c.sendBridgeState(status.BridgeState{
			StateEvent: status.StateBadCredentials,
			Error:      "gchat-bad-credentials",
			Message:    err.Error(),
			UserAction: status.UserActionRelogin,
		})
		return
	}

	streamCh := make(chan streamNotification, 256)
	go func() {
		defer close(doneCh)
		for {
			select {
			case <-streamCtx.Done():
				return
			case item, ok := <-streamCh:
				if !ok {
					return
				}
				c.processStreamNotification(streamCtx, item)
			}
		}
	}()

	if err := ffi.StartStream(func(eventKind int32, payload []byte) {
		select {
		case <-streamCtx.Done():
		case streamCh <- streamNotification{kind: eventKind, payload: payload}:
		}
	}); err != nil {
		cancel()
		c.sendBridgeState(status.BridgeState{
			StateEvent: status.StateTransientDisconnect,
			Message:    err.Error(),
		})
	}
}

func (c *Client) processStreamNotification(ctx context.Context, item streamNotification) {
	if ctx.Err() != nil {
		return
	}
	switch item.kind {
	case EventKindConnected:
		c.sendBridgeState(status.BridgeState{StateEvent: status.StateConnected})
		c.mu.Lock()
		needInitial := !c.initialSyncDone
		if needInitial {
			c.initialSyncDone = true
		}
		c.mu.Unlock()
		if needInitial {
			_ = c.syncWorld(ctx)
		}
	case EventKindResync:
		_ = c.catchUpAfterReconnect(ctx)
	case EventKindEventProto:
		evts, err := c.translateWebChannelEvent(ctx, item.payload)
		if err != nil {
			return
		}
		for _, re := range evts {
			c.queueRemoteEvent(ctx, re)
		}
	case EventKindAuthExpired:
		c.sendBridgeState(status.BridgeState{
			StateEvent: status.StateBadCredentials,
			Error:      "gchat-bad-credentials",
			Message:    string(item.payload),
			UserAction: status.UserActionRelogin,
		})
	}
}

func (c *Client) queueRemoteEvent(ctx context.Context, evt bridgev2.RemoteEvent) {
	if evt == nil || c.UserLogin == nil {
		return
	}
	if msgEvt, ok := evt.(*simplevent.PreConvertedMessage); ok && msgEvt.ID != "" {
		dedupKey := string(msgEvt.GetPortalKey().ID) + "|" + string(msgEvt.ID)
		c.mu.Lock()
		if c.dispatchedMsgIDs == nil {
			c.dispatchedMsgIDs = make(map[string]struct{})
		}
		if _, exists := c.dispatchedMsgIDs[dedupKey]; exists {
			c.mu.Unlock()
			return
		}
		if c.UserLogin.Bridge != nil && c.UserLogin.Bridge.DB != nil && c.UserLogin.Bridge.DB.Message != nil {
			if existing, err := c.UserLogin.Bridge.DB.Message.GetFirstPartByID(ctx, c.UserLogin.ID, msgEvt.ID); err == nil && existing != nil {
				c.dispatchedMsgIDs[dedupKey] = struct{}{}
				c.mu.Unlock()
				return
			}
		}
		c.dispatchedMsgIDs[dedupKey] = struct{}{}
		c.emittedEvents = append(c.emittedEvents, evt)
		c.mu.Unlock()
	} else {
		c.mu.Lock()
		c.emittedEvents = append(c.emittedEvents, evt)
		c.mu.Unlock()
	}
	c.UserLogin.QueueRemoteEvent(evt)
}

func (c *Client) recordedRemoteEvents() []bridgev2.RemoteEvent {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]bridgev2.RemoteEvent, len(c.emittedEvents))
	copy(out, c.emittedEvents)
	return out
}

func (c *Client) advanceManualClock(delta time.Duration) int {
	c.mu.Lock()
	ffi := c.ffiClient
	c.mu.Unlock()
	if ffi == nil {
		return 0
	}
	return ffi.AdvanceManualClock(delta)
}

func (c *Client) Disconnect() {
	c.mu.Lock()
	cancel := c.cancelStream
	doneCh := c.streamDone
	c.cancelStream = nil
	c.streamDone = nil
	ffi := c.ffiClient
	c.ffiClient = nil
	c.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if ffi != nil {
		ffi.Close()
	}
	if doneCh != nil {
		<-doneCh
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
	useManual := c.useManualClock
	jitter := c.manualJitter
	if c.Main != nil {
		baseURL = c.Main.baseURL
		if c.Main.useManualClock {
			useManual = true
			jitter = c.Main.manualJitter
		}
	}
	ffi, err := NewFFIClient(SessionConfig{
		CookieMap: meta.Cookies,
		UserAgent: meta.UserAgent,
		BaseURL:   baseURL,
	})
	if err != nil {
		return nil, err
	}
	if useManual {
		ffi.UseManualClock(jitter)
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
	if c.lastBridgeState() == status.StateBadCredentials {
		return false
	}
	meta, _ := c.UserLogin.Metadata.(*UserLoginMetadata)
	return meta != nil && hasRequiredCookies(meta.Cookies)
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
	name := string(portal.ID)
	if portal.Name != "" {
		name = portal.Name
	}
	level := 50
	memberMap := bridgev2.ChatMemberMap{
		"": {
			EventSender: bridgev2.EventSender{
				IsFromMe:    true,
				SenderLogin: c.UserLogin.ID,
				Sender:      c.ownUserID(),
			},
			Membership: event.MembershipJoin,
			PowerLevel: &level,
		},
	}
	if portal.OtherUserID != "" {
		memberMap[portal.OtherUserID] = bridgev2.ChatMember{
			EventSender: bridgev2.EventSender{Sender: portal.OtherUserID},
			Membership:  event.MembershipJoin,
			PowerLevel:  &level,
		}
	}
	return &bridgev2.ChatInfo{
		Name:        &name,
		Type:        &roomType,
		CanBackfill: true,
		Members: &bridgev2.ChatMemberList{
			IsFull:      isDM && portal.OtherUserID != "",
			OtherUserID: portal.OtherUserID,
			MemberMap:   memberMap,
			PowerLevels: &bridgev2.PowerLevelOverrides{
				Invite:       &level,
				Kick:         &level,
				StateDefault: &level,
			},
		},
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
