// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"

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

var (
	onRemoteEventQueued func(*Client, bridgev2.RemoteEvent)
	onFFIClientCreated  func(*Client, *FFIClient)
)

type Client struct {
	Main      *Connector
	UserLogin *bridgev2.UserLogin

	mu             sync.Mutex
	metaMu         sync.Mutex
	loggedOut      bool
	syncMu         sync.Mutex
	ffiClient      *FFIClient
	streamCtx      context.Context
	cancelStream   context.CancelFunc
	streamDone     chan struct{}
	streamCh       chan streamNotification
	portalQueues   map[networkid.PortalKey]chan bridgev2.RemoteEvent
	portalWG       sync.WaitGroup
	prewarmCh      chan networkid.UserID
	prewarmedUsers map[networkid.UserID]struct{}
	// ghostMu serializes every bridgev2 ghost access we cause: QueueRemoteEvent
	// runs synchronously, and bridgev2 shares ghosts across portals unlocked.
	ghostMu            sync.Mutex
	userInfoCache      map[networkid.UserID]*bridgev2.UserInfo
	prewarmWG          sync.WaitGroup
	mediaSem           chan struct{}
	initialSyncDone    bool
	dispatchedMsgIDs   map[string]struct{}
	dispatchedMsgOrder []string
	pendingLocalIDs    map[string]struct{}
	pendingLocalOrder  []string
	lastState          status.BridgeStateEvent
	lastBridgeStateObj status.BridgeState
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
	c.lastBridgeStateObj = st
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

func (c *Client) lastBridgeStateFull() status.BridgeState {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.lastBridgeStateObj
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
	prevCancel := c.cancelStream
	prevDone := c.streamDone
	prevFFI := c.ffiClient
	c.cancelStream = nil
	c.streamDone = nil
	c.mu.Unlock()
	if prevCancel != nil {
		prevCancel()
	}
	if prevFFI != nil {
		prevFFI.StopStream()
	}
	if prevDone != nil {
		<-prevDone
	}

	c.mu.Lock()
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
	prewarmCh := make(chan networkid.UserID, 1024)
	c.mu.Lock()
	c.streamCtx = streamCtx
	c.streamCh = streamCh
	c.portalQueues = make(map[networkid.PortalKey]chan bridgev2.RemoteEvent)
	c.prewarmCh = prewarmCh
	c.prewarmedUsers = make(map[networkid.UserID]struct{})
	c.mu.Unlock()
	for i := 0; i < 4; i++ {
		c.prewarmWG.Add(1)
		go c.runGhostPrewarmWorker(streamCtx, prewarmCh)
	}
	go func() {
		defer close(doneCh)
		defer func() {
			c.mu.Lock()
			for pk, q := range c.portalQueues {
				close(q)
				delete(c.portalQueues, pk)
			}
			c.portalQueues = nil
			c.streamCtx = nil
			c.mu.Unlock()
			c.portalWG.Wait()
			c.mu.Lock()
			if c.prewarmCh != nil {
				close(c.prewarmCh)
				c.prewarmCh = nil
			}
			c.mu.Unlock()
			c.prewarmWG.Wait()
		}()
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
		c.persistRotatedCookies(ctx, item.payload)
		c.sendBridgeState(status.BridgeState{StateEvent: status.StateConnected})
		c.mu.Lock()
		needInitial := !c.initialSyncDone
		if needInitial {
			c.initialSyncDone = true
		}
		c.mu.Unlock()
		if needInitial {
			// The world sync moves the stored user revision up to now, so read the one saved before
			// this connect (a restart, or a re-login) first and catch up from it once the chats exist.
			// Otherwise whatever arrived while Courier was closed is never fetched.
			savedRev := c.storedUserRevision()
			if err := c.syncWorld(ctx); err != nil && c.UserLogin != nil {
				c.UserLogin.Log.Warn().Err(err).Msg("gchat initial world sync failed")
			}
			if savedRev > 0 {
				if err := c.catchUpUserFrom(ctx, savedRev); err != nil && c.UserLogin != nil {
					c.UserLogin.Log.Warn().Err(err).Msg("gchat catch-up after connect failed")
				}
			}
		}
	case EventKindResync:
		if err := c.catchUpAfterReconnect(ctx); err != nil && c.UserLogin != nil {
			c.UserLogin.Log.Warn().Err(err).Msg("gchat reconnect catch-up failed")
		}
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
	case EventKindStreamError:
		msg := string(item.payload)
		if c.UserLogin != nil {
			c.UserLogin.Log.Warn().Str("message", msg).Msg("gchat stream error")
		}
		c.mu.Lock()
		connectedSinceConnect := c.initialSyncDone
		c.mu.Unlock()
		if !connectedSinceConnect {
			c.sendBridgeState(status.BridgeState{
				StateEvent: status.StateTransientDisconnect,
				Error:      "gchat-stream-error",
				Message:    msg,
			})
		}
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
	if evt.GetType() == bridgev2.RemoteEventMessage {
		if msgEvt, ok := evt.(bridgev2.RemoteMessage); ok && msgEvt.GetID() != "" {
			msgID := msgEvt.GetID()
			var txnID networkid.TransactionID
			if txnEvt, ok := evt.(bridgev2.RemoteMessageWithTransactionID); ok {
				txnID = txnEvt.GetTransactionID()
			}
			dedupKey := string(evt.GetPortalKey().ID) + "|" + string(msgID)
			c.mu.Lock()
			if txnID != "" && c.pendingLocalIDs != nil {
				if _, pending := c.pendingLocalIDs[string(txnID)]; pending {
					delete(c.pendingLocalIDs, string(txnID))
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
				if existing, err := c.UserLogin.Bridge.DB.Message.GetFirstPartByID(ctx, c.UserLogin.ID, msgID); err == nil && existing != nil {
					c.recordDispatchedLocked(dedupKey)
					c.mu.Unlock()
					return
				}
			}
			c.recordDispatchedLocked(dedupKey)
			c.mu.Unlock()
		}
	}
	if onRemoteEventQueued != nil {
		onRemoteEventQueued(c, evt)
	}
	c.dispatchRemoteEvent(ctx, evt)
}

func (c *Client) dispatchRemoteEvent(ctx context.Context, evt bridgev2.RemoteEvent) {
	c.mu.Lock()
	streamCtx := c.streamCtx
	queues := c.portalQueues
	if streamCtx == nil || streamCtx.Err() != nil || queues == nil || ctx != streamCtx {
		c.mu.Unlock()
		c.executeRemoteEvent(ctx, evt)
		return
	}
	pk := evt.GetPortalKey()
	q, ok := queues[pk]
	if !ok {
		q = make(chan bridgev2.RemoteEvent, 256)
		queues[pk] = q
		c.portalWG.Add(1)
		go func(ch chan bridgev2.RemoteEvent) {
			defer c.portalWG.Done()
			for {
				select {
				case <-streamCtx.Done():
					return
				case re, ok := <-ch:
					if !ok {
						return
					}
					if streamCtx.Err() != nil {
						return
					}
					c.executeRemoteEvent(streamCtx, re)
				}
			}
		}(q)
	}
	c.mu.Unlock()
	select {
	case <-streamCtx.Done():
	case <-ctx.Done():
	case q <- evt:
	}
}

func (c *Client) executeRemoteEvent(ctx context.Context, evt bridgev2.RemoteEvent) {
	if evt == nil || c.UserLogin == nil {
		return
	}
	if evt.GetType() == bridgev2.RemoteEventMessage {
		if msgEvt, ok := evt.(bridgev2.RemoteMessage); ok {
			_, _ = msgEvt.ConvertMessage(ctx, nil, nil)
		}
	}
	c.seedEventGhosts(ctx, evt)
	c.ghostMu.Lock()
	c.UserLogin.QueueRemoteEvent(evt)
	c.ghostMu.Unlock()
}

func (c *Client) seedAndEnqueueGhostPrewarm(ctx context.Context, uid networkid.UserID) {
	if uid == "" || uid == c.ownUserID() || c.UserLogin == nil || c.UserLogin.Bridge == nil {
		return
	}
	c.mu.Lock()
	streamCtx := c.streamCtx
	ch := c.prewarmCh
	if streamCtx == nil || streamCtx.Err() != nil || ch == nil {
		c.mu.Unlock()
		return
	}
	if c.prewarmedUsers == nil {
		c.prewarmedUsers = make(map[networkid.UserID]struct{})
	}
	if _, seen := c.prewarmedUsers[uid]; seen {
		c.mu.Unlock()
		return
	}
	// Mark the user only once it is queued, so a full queue leaves it eligible
	// for the next sync instead of silently never warming it.
	select {
	case ch <- uid:
		c.prewarmedUsers[uid] = struct{}{}
	default:
	}
	c.mu.Unlock()
}

func (c *Client) seedEventGhosts(ctx context.Context, evt bridgev2.RemoteEvent) {
	if evt == nil || c.UserLogin == nil || c.UserLogin.Bridge == nil {
		return
	}
	if sender := evt.GetSender().Sender; sender != "" {
		c.seedAndEnqueueGhostPrewarm(ctx, sender)
	}
	if resync, ok := evt.(*simplevent.ChatResync); ok && resync != nil && resync.ChatInfo != nil && resync.ChatInfo.Members != nil {
		if resync.ChatInfo.Members.OtherUserID != "" {
			c.seedAndEnqueueGhostPrewarm(ctx, resync.ChatInfo.Members.OtherUserID)
		}
		for uid := range resync.ChatInfo.Members.MemberMap {
			c.seedAndEnqueueGhostPrewarm(ctx, uid)
		}
	}
	if cic, ok := evt.(*simplevent.ChatInfoChange); ok && cic != nil && cic.ChatInfoChange != nil && cic.ChatInfoChange.MemberChanges != nil {
		for uid := range cic.ChatInfoChange.MemberChanges.MemberMap {
			c.seedAndEnqueueGhostPrewarm(ctx, uid)
		}
	}
}

func (c *Client) runGhostPrewarmWorker(streamCtx context.Context, ch <-chan networkid.UserID) {
	defer c.prewarmWG.Done()
	for {
		select {
		case <-streamCtx.Done():
			return
		case uid, ok := <-ch:
			if !ok {
				return
			}
			if streamCtx.Err() != nil || c.UserLogin == nil || c.UserLogin.Bridge == nil {
				return
			}
			// Fetch off the event path, then apply under ghostMu so the write
			// never overlaps bridgev2's event handling.
			info, err := c.cachedUserInfo(streamCtx, uid)
			if err != nil || info == nil || streamCtx.Err() != nil {
				continue
			}
			c.ghostMu.Lock()
			// Skip a ghost that already has this name (bridgev2 applied it from the
			// cache); a second
			// UpdateInfo races the DM-portal refresh bridgev2 spawns from the first.
			if ghost, gerr := c.UserLogin.Bridge.GetGhostByID(streamCtx, uid); gerr == nil && ghost != nil &&
				info.Name != nil && ghost.Name != *info.Name {
				ghost.UpdateInfo(streamCtx, info)
			}
			c.ghostMu.Unlock()
		}
	}
}

func (c *Client) Disconnect() {
	c.mu.Lock()
	cancel := c.cancelStream
	doneCh := c.streamDone
	c.cancelStream = nil
	c.streamDone = nil
	ffi := c.ffiClient
	c.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if ffi != nil {
		ffi.StopStream()
	}
	if doneCh != nil {
		<-doneCh
	}
	c.mu.Lock()
	if c.ffiClient == ffi {
		c.ffiClient = nil
	}
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
	if c.Main != nil {
		baseURL = c.Main.baseURL
	}
	ffi, err := NewFFIClient(SessionConfig{
		CookieMap: cookiesCopy,
		UserAgent: userAgent,
		BaseURL:   baseURL,
	})
	if err != nil {
		return nil, err
	}
	if onFFIClientCreated != nil {
		onFFIClientCreated(c, ffi)
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

// isPlaceholderChatName is whether name is no name at all: blank, or the portal ID an older build stored when it
// had none. A real name that merely starts with "space:" or "dm:" is a name.
func isPlaceholderChatName(portalID networkid.PortalID, name string) bool {
	trimmed := strings.TrimSpace(name)
	return trimmed == "" || trimmed == string(portalID)
}

func otherMemberIDs(memberGaiaIDs []string, own networkid.UserID) []networkid.UserID {
	seen := make(map[networkid.UserID]struct{}, len(memberGaiaIDs))
	var out []networkid.UserID
	for _, raw := range memberGaiaIDs {
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" {
			continue
		}
		uid := MakeUserID(trimmed)
		if uid == own {
			continue
		}
		if _, dup := seen[uid]; dup {
			continue
		}
		seen[uid] = struct{}{}
		out = append(out, uid)
	}
	return out
}

func (c *Client) composeGroupMemberName(ctx context.Context, otherIDs []networkid.UserID) string {
	const maxNames = 3
	names := make([]string, 0, min(len(otherIDs), maxNames))
	extra := 0
	for _, uid := range otherIDs {
		if len(names) >= maxNames {
			extra++
			continue
		}
		info, err := c.cachedUserInfo(ctx, uid)
		if err != nil || info == nil || info.Name == nil {
			continue
		}
		n := strings.TrimSpace(*info.Name)
		if n == "" || n == string(uid) {
			continue
		}
		names = append(names, n)
	}
	if len(names) == 0 {
		return ""
	}
	joined := strings.Join(names, ", ")
	if extra > 0 {
		return fmt.Sprintf("%s and %d others", joined, extra)
	}
	return joined
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
	storedName := strings.TrimSpace(portal.Name)
	if isPlaceholderChatName(portal.ID, storedName) {
		storedName = ""
	}
	name := storedName

	var topic *string
	var memberGaiaIDs []string
	c.metaMu.Lock()
	if meta, ok := portal.Metadata.(*PortalMetadata); ok && meta != nil && len(meta.MemberUserIDs) > 0 {
		memberGaiaIDs = append(memberGaiaIDs, meta.MemberUserIDs...)
	}
	c.metaMu.Unlock()

	own := c.ownUserID()
	otherIDs := otherMemberIDs(memberGaiaIDs, own)

	fetchedGroupMembers := false
	if rawID != "" && (!isDM || len(otherIDs) > 1) {
		reqBytes, mErr := pb.Marshal(&pb.GetGroupRequest{
			GroupId: pb.PartsToGroupID(rawID, isDM),
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
						if gName := strings.TrimSpace(g.GetName()); gName != "" && !isPlaceholderChatName(portal.ID, gName) {
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

	otherIDs = otherMemberIDs(memberGaiaIDs, own)
	isGroup := !isDM || len(otherIDs) > 1
	if isGroup && name == "" {
		name = c.composeGroupMemberName(ctx, otherIDs)
	}

	otherUserID := portal.OtherUserID
	if isDM && len(otherIDs) > 1 {
		otherUserID = ""
	}

	var namePtr *string
	if name != "" {
		namePtr = &name
	}

	return &bridgev2.ChatInfo{
		Name:        namePtr,
		Topic:       topic,
		Type:        &roomType,
		CanBackfill: true,
		Members:     c.buildChatMemberList(own, isDM, otherUserID, memberGaiaIDs, fetchedGroupMembers),
	}, nil
}

func (c *Client) GetUserInfo(ctx context.Context, ghost *bridgev2.Ghost) (*bridgev2.UserInfo, error) {
	if ghost == nil {
		return &bridgev2.UserInfo{}, nil
	}
	// bridgev2 calls this inline, under ghostMu, while handling an event. On a
	// cache miss with the stream up, hand the lookup to the prewarm workers
	// (they apply it themselves) rather than stall every portal on an RPC.
	c.mu.Lock()
	info, ok := c.userInfoCache[ghost.ID]
	streaming := c.streamCtx != nil && c.streamCtx.Err() == nil && c.prewarmCh != nil
	c.mu.Unlock()
	if ok {
		// Nothing new: returning it again would re-run UpdateInfo on every
		// event (an avatar that failed to settle keeps AvatarSet false), and
		// each run races the DM-portal refresh bridgev2 spawned from the last.
		if info.Name != nil && ghost.Name == *info.Name &&
			(info.Avatar == nil || info.Avatar.ID == ghost.AvatarID) {
			return nil, nil
		}
		return info, nil
	}
	if streaming {
		c.seedAndEnqueueGhostPrewarm(ctx, ghost.ID)
		return nil, nil
	}
	return c.cachedUserInfo(ctx, ghost.ID)
}

// userInfoLookupSem caps concurrent get_members lookups across all clients.
var userInfoLookupSem = make(chan struct{}, 4)

// cachedUserInfo returns the fetched info for uid, fetching it once on a miss.
func (c *Client) cachedUserInfo(ctx context.Context, uid networkid.UserID) (*bridgev2.UserInfo, error) {
	c.mu.Lock()
	info, ok := c.userInfoCache[uid]
	c.mu.Unlock()
	if ok {
		return info, nil
	}
	// One cap for every get_members lookup, inline or prewarm.
	select {
	case userInfoLookupSem <- struct{}{}:
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	info, err := c.fetchUserInfoByID(ctx, uid)
	<-userInfoLookupSem
	// A failed lookup falls back to the raw ID as the name; don't cache that,
	// so the next call retries instead of pinning the number for good.
	if err != nil || info == nil || info.Name == nil || *info.Name == string(uid) {
		return info, err
	}
	c.mu.Lock()
	if c.userInfoCache == nil {
		c.userInfoCache = make(map[networkid.UserID]*bridgev2.UserInfo)
	}
	c.userInfoCache[uid] = info
	c.mu.Unlock()
	return info, nil
}

func (c *Client) fetchUserInfoByID(ctx context.Context, uid networkid.UserID) (*bridgev2.UserInfo, error) {
	name := string(uid)
	var avatarURL string
	if gaiaID := strings.TrimSpace(string(uid)); gaiaID != "" {
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
	} else {
		// An explicit "no avatar" lets bridgev2 mark the avatar settled; left
		// nil, every later event re-runs UpdateInfo on this ghost.
		info.Avatar = &bridgev2.Avatar{Remove: true}
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
