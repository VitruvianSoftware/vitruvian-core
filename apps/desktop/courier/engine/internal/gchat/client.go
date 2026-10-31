// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"encoding/json"
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

	"github.com/VitruvianSoftware/courier/engine/internal/gchat/pb"
)

type streamNotification struct {
	kind    int32
	payload []byte
}

// Client implements bridgev2.NetworkAPI for a Google Chat UserLogin.
const (
	maxDispatchedMsgIDs = 2048
	maxPendingLocalIDs  = 256
)

var onRemoteEventQueued func(*Client, bridgev2.RemoteEvent)

type Client struct {
	Main      *Connector
	UserLogin *bridgev2.UserLogin

	mu                 sync.Mutex
	metaMu             sync.Mutex
	loggedOut          bool
	syncMu             sync.Mutex
	ffiClient          *FFIClient
	cancelStream       context.CancelFunc
	streamDone         chan struct{}
	streamCh           chan streamNotification
	initialSyncDone    bool
	useManualClock     bool
	manualJitter       float64
	dispatchedMsgIDs   map[string]struct{}
	dispatchedMsgOrder []string
	pendingLocalIDs    map[string]struct{}
	pendingLocalOrder  []string
	lastState          status.BridgeStateEvent
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
	c.metaMu.Lock()
	c.loggedOut = false
	meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata)
	hasCookies := ok && meta != nil && hasRequiredCookies(meta.Cookies)
	c.metaMu.Unlock()
	if !hasCookies {
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
	c.mu.Lock()
	c.streamCh = streamCh
	c.mu.Unlock()
	mediaSem := make(chan struct{}, 4)
	var mediaWG sync.WaitGroup
	go func() {
		defer close(doneCh)
		defer mediaWG.Wait()
		for {
			select {
			case <-streamCtx.Done():
				return
			case item, ok := <-streamCh:
				if !ok {
					return
				}
				if item.kind == EventKindEventProto && eventHasAttachmentDownload(item.payload) {
					mediaWG.Add(1)
					go func(it streamNotification) {
						defer mediaWG.Done()
						select {
						case <-streamCtx.Done():
							return
						case mediaSem <- struct{}{}:
							defer func() { <-mediaSem }()
						}
						c.processStreamNotification(streamCtx, it)
					}(item)
					continue
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
		c.persistRotatedCookies(ctx, item.payload)
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

func (c *Client) recordDispatchedLocked(dedupKey string) {
	if c.dispatchedMsgIDs == nil {
		c.dispatchedMsgIDs = make(map[string]struct{})
	}
	if _, exists := c.dispatchedMsgIDs[dedupKey]; exists {
		return
	}
	for len(c.dispatchedMsgIDs) >= maxDispatchedMsgIDs && len(c.dispatchedMsgOrder) > 0 {
		oldest := c.dispatchedMsgOrder[0]
		c.dispatchedMsgOrder = c.dispatchedMsgOrder[1:]
		delete(c.dispatchedMsgIDs, oldest)
	}
	c.dispatchedMsgIDs[dedupKey] = struct{}{}
	c.dispatchedMsgOrder = append(c.dispatchedMsgOrder, dedupKey)
}

func (c *Client) queueRemoteEvent(ctx context.Context, evt bridgev2.RemoteEvent) {
	if evt == nil || c.UserLogin == nil {
		return
	}
	if msgEvt, ok := evt.(*simplevent.PreConvertedMessage); ok && msgEvt.ID != "" {
		dedupKey := string(msgEvt.GetPortalKey().ID) + "|" + string(msgEvt.ID)
		c.mu.Lock()
		if msgEvt.TransactionID != "" && c.pendingLocalIDs != nil {
			if _, pending := c.pendingLocalIDs[string(msgEvt.TransactionID)]; pending {
				delete(c.pendingLocalIDs, string(msgEvt.TransactionID))
				c.recordDispatchedLocked(dedupKey)
				c.mu.Unlock()
				return
			}
		}
		if _, exists := c.dispatchedMsgIDs[dedupKey]; exists {
			c.mu.Unlock()
			return
		}
		if c.UserLogin.Bridge != nil && c.UserLogin.Bridge.DB != nil && c.UserLogin.Bridge.DB.Message != nil {
			if existing, err := c.UserLogin.Bridge.DB.Message.GetFirstPartByID(ctx, c.UserLogin.ID, msgEvt.ID); err == nil && existing != nil {
				c.recordDispatchedLocked(dedupKey)
				c.mu.Unlock()
				return
			}
		}
		c.recordDispatchedLocked(dedupKey)
		c.mu.Unlock()
	}
	if onRemoteEventQueued != nil {
		onRemoteEventQueued(c, evt)
	}
	c.UserLogin.QueueRemoteEvent(evt)
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
	c.metaMu.Lock()
	meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata)
	var cookiesCopy map[string]string
	var userAgent string
	if ok && meta != nil && len(meta.Cookies) > 0 {
		cookiesCopy = make(map[string]string, len(meta.Cookies))
		for k, v := range meta.Cookies {
			cookiesCopy[k] = v
		}
		userAgent = meta.UserAgent
	}
	c.metaMu.Unlock()
	if len(cookiesCopy) == 0 {
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
		CookieMap: cookiesCopy,
		UserAgent: userAgent,
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
	c.metaMu.Lock()
	defer c.metaMu.Unlock()
	if c.loggedOut {
		return false
	}
	meta, _ := c.UserLogin.Metadata.(*UserLoginMetadata)
	return meta != nil && hasRequiredCookies(meta.Cookies)
}

func (c *Client) persistRotatedCookies(ctx context.Context, payload []byte) {
	if c.UserLogin == nil || len(payload) == 0 {
		return
	}
	var rotated map[string]string
	if err := json.Unmarshal(payload, &rotated); err != nil || len(rotated) == 0 {
		return
	}
	c.metaMu.Lock()
	defer c.metaMu.Unlock()
	if c.loggedOut {
		return
	}
	meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata)
	if !ok || meta == nil {
		return
	}
	if meta.Cookies == nil {
		meta.Cookies = make(map[string]string, len(rotated))
	}
	changed := false
	for k, v := range rotated {
		if v == "" {
			continue
		}
		if meta.Cookies[k] != v {
			meta.Cookies[k] = v
			changed = true
		}
	}
	if changed && c.UserLogin.Bridge != nil && c.UserLogin.Bridge.DB != nil {
		_ = c.UserLogin.Save(ctx)
	}
}

func (c *Client) LogoutRemote(ctx context.Context) {
	c.Disconnect()
	c.metaMu.Lock()
	c.loggedOut = true
	if c.UserLogin != nil {
		if meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata); ok && meta != nil {
			meta.Cookies = nil
		}
		if c.UserLogin.Bridge != nil && c.UserLogin.Bridge.DB != nil {
			_ = c.UserLogin.Save(ctx)
		}
	}
	c.metaMu.Unlock()
}

func (c *Client) IsThisUser(_ context.Context, userID networkid.UserID) bool {
	return c.UserLogin != nil && string(userID) == string(c.UserLogin.ID)
}

func (c *Client) buildChatMemberList(
	own networkid.UserID,
	isDM bool,
	otherUserID networkid.UserID,
	memberGaiaIDs []string,
	fetchedGroupMembers bool,
) *bridgev2.ChatMemberList {
	level := 50
	var senderLogin networkid.UserLoginID
	if c.UserLogin != nil {
		senderLogin = c.UserLogin.ID
	}
	memberMap := bridgev2.ChatMemberMap{
		"": {
			EventSender: bridgev2.EventSender{
				IsFromMe:    true,
				SenderLogin: senderLogin,
				Sender:      own,
			},
			Membership: event.MembershipJoin,
			PowerLevel: &level,
		},
	}
	if otherUserID != "" {
		memberMap[otherUserID] = bridgev2.ChatMember{
			EventSender: bridgev2.EventSender{Sender: otherUserID},
			Membership:  event.MembershipJoin,
			PowerLevel:  &level,
		}
	}
	for _, rawID := range memberGaiaIDs {
		uid := MakeUserID(strings.TrimSpace(rawID))
		if uid == "" || uid == own {
			continue
		}
		memberMap[uid] = bridgev2.ChatMember{
			EventSender: bridgev2.EventSender{Sender: uid},
			Membership:  event.MembershipJoin,
			PowerLevel:  &level,
		}
	}
	isFull := (isDM && otherUserID != "") || fetchedGroupMembers || len(memberMap) > 1
	return &bridgev2.ChatMemberList{
		IsFull:      isFull,
		OtherUserID: otherUserID,
		MemberMap:   memberMap,
		PowerLevels: &bridgev2.PowerLevelOverrides{
			Invite:       &level,
			Kick:         &level,
			StateDefault: &level,
		},
	}
}

func (c *Client) GetChatInfo(ctx context.Context, portal *bridgev2.Portal) (*bridgev2.ChatInfo, error) {
	isDM, rawID, err := ParsePortalID(portal.ID)
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
	var topic *string
	var memberGaiaIDs []string
	c.metaMu.Lock()
	if meta, ok := portal.Metadata.(*PortalMetadata); ok && meta != nil && len(meta.MemberUserIDs) > 0 {
		memberGaiaIDs = append(memberGaiaIDs, meta.MemberUserIDs...)
	}
	c.metaMu.Unlock()

	fetchedGroupMembers := false
	if !isDM && rawID != "" {
		reqBytes, mErr := pb.Marshal(&pb.GetGroupRequest{
			GroupId: pb.SpaceGroupID(rawID),
			FetchOptions: []pb.GetGroupRequest_FetchOptions{
				pb.GetGroupRequest_MEMBERS,
				pb.GetGroupRequest_INCLUDE_DYNAMIC_GROUP_NAME,
			},
			IncludeInviteDms: pb.Bool(true),
		})
		if mErr == nil {
			if respBytes, rpcErr := c.rpcCall(ctx, "get_group", reqBytes); rpcErr == nil && len(respBytes) > 0 {
				var resp pb.GetGroupResponse
				if pb.Unmarshal(respBytes, &resp) == nil {
					if g := resp.GetGroup(); g != nil {
						if gName := strings.TrimSpace(g.GetName()); gName != "" && portal.Name == "" {
							name = gName
						}
						if desc := strings.TrimSpace(g.GetGroupDetails().GetDescription()); desc != "" {
							topic = &desc
						}
					}
					for _, m := range resp.GetMemberships() {
						state := m.GetMembershipState()
						if m.MembershipState != nil && state != pb.MembershipState_MEMBER_JOINED {
							continue
						}
						if uid := strings.TrimSpace(m.GetId().GetMemberId().GetUserId().GetId()); uid != "" {
							memberGaiaIDs = append(memberGaiaIDs, uid)
							fetchedGroupMembers = true
						}
					}
				}
			}
		}
	}

	return &bridgev2.ChatInfo{
		Name:        &name,
		Topic:       topic,
		Type:        &roomType,
		CanBackfill: true,
		Members:     c.buildChatMemberList(c.ownUserID(), isDM, portal.OtherUserID, memberGaiaIDs, fetchedGroupMembers),
	}, nil
}

func (c *Client) GetUserInfo(ctx context.Context, ghost *bridgev2.Ghost) (*bridgev2.UserInfo, error) {
	if ghost == nil {
		return &bridgev2.UserInfo{}, nil
	}
	name := string(ghost.ID)
	if ghost.Name != "" {
		name = ghost.Name
	}
	var avatarURL string
	if gaiaID := strings.TrimSpace(string(ghost.ID)); gaiaID != "" {
		reqBytes, err := pb.Marshal(&pb.GetMembersRequest{
			MemberIds: []*pb.MemberId{pb.UserMemberID(gaiaID)},
		})
		if err == nil {
			if respBytes, rpcErr := c.rpcCall(ctx, "get_members", reqBytes); rpcErr == nil && len(respBytes) > 0 {
				var resp pb.GetMembersResponse
				if pb.Unmarshal(respBytes, &resp) == nil {
					applyUser := func(u *pb.User) {
						if u == nil {
							return
						}
						if s := strings.TrimSpace(u.GetName()); s != "" {
							name = s
						}
						if s := strings.TrimSpace(u.GetAvatarUrl()); s != "" {
							avatarURL = s
						}
					}
					for _, m := range resp.GetMembers() {
						applyUser(m.GetUser())
					}
					for _, mp := range resp.GetMemberProfiles() {
						applyUser(mp.GetMember().GetUser())
					}
				}
			}
		}
	}
	info := &bridgev2.UserInfo{
		Name: &name,
	}
	if avatarURL != "" {
		info.Avatar = &bridgev2.Avatar{
			ID: networkid.AvatarID(avatarURL),
			Get: func(ctx context.Context) ([]byte, error) {
				return c.downloadAvatar(ctx, avatarURL)
			},
		}
	}
	return info, nil
}

func (c *Client) GetCapabilities(_ context.Context, portal *bridgev2.Portal) *event.RoomFeatures {
	if c != nil {
		c.metaMu.Lock()
		defer c.metaMu.Unlock()
	}
	return defaultRoomCapabilities(portal)
}

func (c *Client) FillBridgeState(state status.BridgeState) status.BridgeState {
	return state
}
