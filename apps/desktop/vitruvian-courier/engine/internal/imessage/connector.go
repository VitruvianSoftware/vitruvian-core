// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package imessage

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"slices"
	"strings"
	"sync"
	"time"

	"go.mau.fi/util/configupgrade"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

const (
	NetworkID      = "imessage"
	DisplayName    = "iMessage"
	FlowLocal      = "local"
	DefaultLoginID = networkid.UserLoginID("local")
	SelfUserID     = networkid.UserID("me")

	defaultPollInterval = 1500 * time.Millisecond
	initialChatSyncCap  = 50
	pollBatchSize       = 200
	maxDispatchedGUIDs  = 2048
)

// UserLoginMetadata persists the incremental chat.db ROWID cursor on the UserLogin row.
type UserLoginMetadata struct {
	LastRowID  int64  `json:"last_row_id,omitempty"`
	ChatDBPath string `json:"chat_db_path,omitempty"`
}

// PortalMetadata stores per-portal iMessage conversation metadata.
type PortalMetadata struct {
	ServiceName    string   `json:"service_name,omitempty"`
	ChatIdentifier string   `json:"chat_identifier,omitempty"`
	Style          int      `json:"style,omitempty"`
	Participants   []string `json:"participants,omitempty"`
	LastRowID      int64    `json:"last_row_id,omitempty"`
}

// GhostMetadata stores per-ghost iMessage contact metadata.
type GhostMetadata struct {
	Service string `json:"service,omitempty"`
}

// MessageMetadata stores per-message iMessage row and GUID metadata.
type MessageMetadata struct {
	RowID   int64  `json:"row_id,omitempty"`
	GUID    string `json:"guid,omitempty"`
	Service string `json:"service,omitempty"`
}

// ReactionMetadata stores per-reaction iMessage tapback metadata.
type ReactionMetadata struct {
	RowID          int64  `json:"row_id,omitempty"`
	GUID           string `json:"guid,omitempty"`
	AssociatedType int    `json:"associated_type,omitempty"`
}

// Connector implements bridgev2.NetworkConnector for macOS iMessage.
type Connector struct {
	Bridge       *bridgev2.Bridge
	ChatDBPath   string
	HomeDir      string
	Sender       Sender
	PollInterval time.Duration
}

var _ bridgev2.NetworkConnector = (*Connector)(nil)

// NewConnector creates a new macOS iMessage NetworkConnector reading ~/Library/Messages/chat.db.
func NewConnector() bridgev2.NetworkConnector {
	return &Connector{}
}

// NewConnectorWithConfig creates a new iMessage NetworkConnector with an explicit chat.db path and Sender.
func NewConnectorWithConfig(chatDBPath string, sender Sender) *Connector {
	return &Connector{
		ChatDBPath: chatDBPath,
		Sender:     sender,
	}
}

func (c *Connector) Init(bridge *bridgev2.Bridge) {
	c.Bridge = bridge
}

func (c *Connector) Start(_ context.Context) error {
	return nil
}

func (c *Connector) resolveChatDBPath(login *bridgev2.UserLogin) string {
	if login != nil {
		if meta, ok := login.Metadata.(*UserLoginMetadata); ok && meta != nil && strings.TrimSpace(meta.ChatDBPath) != "" {
			return strings.TrimSpace(meta.ChatDBPath)
		}
	}
	if strings.TrimSpace(c.ChatDBPath) != "" {
		return strings.TrimSpace(c.ChatDBPath)
	}
	if envPath := strings.TrimSpace(os.Getenv("VITRUVIAN_COURIER_IMESSAGE_CHAT_DB")); envPath != "" {
		return envPath
	}
	return DefaultChatDBPath()
}

func (c *Connector) pollInterval() time.Duration {
	if c != nil && c.PollInterval > 0 {
		return c.PollInterval
	}
	return defaultPollInterval
}

func (c *Connector) GetName() bridgev2.BridgeName {
	return bridgev2.BridgeName{
		DisplayName:          DisplayName,
		NetworkURL:           "https://support.apple.com/messages",
		NetworkIcon:          "mxc://maunium.net/iMessage",
		NetworkID:            NetworkID,
		BeeperBridgeType:     "imessage",
		DefaultPort:          29331,
		DefaultCommandPrefix: "!imessage",
	}
}

func (c *Connector) GetDBMetaTypes() database.MetaTypes {
	return database.MetaTypes{
		Portal:    func() any { return &PortalMetadata{} },
		Ghost:     func() any { return &GhostMetadata{} },
		Message:   func() any { return &MessageMetadata{} },
		Reaction:  func() any { return &ReactionMetadata{} },
		UserLogin: func() any { return &UserLoginMetadata{} },
	}
}

func (c *Connector) GetCapabilities() *bridgev2.NetworkGeneralCapabilities {
	return &bridgev2.NetworkGeneralCapabilities{
		Provisioning: bridgev2.ProvisioningCapabilities{
			ResolveIdentifier: bridgev2.ResolveIdentifierCapabilities{
				CreateDM:    true,
				LookupPhone: true,
				LookupEmail: true,
				ContactList: true,
			},
		},
	}
}

func (c *Connector) GetBridgeInfoVersion() (info, capabilities int) {
	return 1, 1
}

func (c *Connector) GetConfig() (example string, data any, upgrader configupgrade.Upgrader) {
	return "", nil, configupgrade.NoopUpgrader
}

func (c *Connector) LoadUserLogin(_ context.Context, login *bridgev2.UserLogin) error {
	login.Client = NewClient(c, login)
	return nil
}

func (c *Connector) GetLoginFlows() []bridgev2.LoginFlow {
	return []bridgev2.LoginFlow{{
		Name:        "Messages on this Mac",
		Description: "Connect to your local macOS Messages database (requires Full Disk Access and Automation permissions)",
		ID:          FlowLocal,
	}}
}

func (c *Connector) CreateLogin(_ context.Context, user *bridgev2.User, flowID string) (bridgev2.LoginProcess, error) {
	if flowID != FlowLocal {
		return nil, fmt.Errorf("invalid iMessage login flow %q", flowID)
	}
	return &LocalLogin{
		User: user,
		Main: c,
	}, nil
}

// LocalLogin implements bridgev2.LoginProcess for on-device macOS iMessage.
type LocalLogin struct {
	User *bridgev2.User
	Main *Connector
}

var (
	_ bridgev2.LoginProcess             = (*LocalLogin)(nil)
	_ bridgev2.LoginProcessWithOverride = (*LocalLogin)(nil)
)

func (ll *LocalLogin) Start(ctx context.Context) (*bridgev2.LoginStep, error) {
	return ll.StartWithOverride(ctx, nil)
}

func (ll *LocalLogin) StartWithOverride(ctx context.Context, _ *bridgev2.UserLogin) (*bridgev2.LoginStep, error) {
	if ll.Main == nil || ll.User == nil {
		return nil, errors.New("iMessage login is missing connector or user")
	}
	dbPath := ll.Main.resolveChatDBPath(nil)
	chatDB, err := OpenChatDB(ctx, dbPath)
	if err != nil {
		return nil, err
	}
	err = chatDB.CheckAccess(ctx)
	_ = chatDB.Close()
	if err != nil {
		return nil, fmt.Errorf("cannot read Messages database at %s: %w", dbPath, err)
	}

	remoteName := "Messages on this Mac"
	ul, err := ll.User.NewLogin(ctx, &database.UserLogin{
		ID:         DefaultLoginID,
		RemoteName: remoteName,
		RemoteProfile: status.RemoteProfile{
			Name: remoteName,
		},
		Metadata: &UserLoginMetadata{},
	}, &bridgev2.NewLoginParams{
		DeleteOnConflict: true,
	})
	if err != nil {
		return nil, fmt.Errorf("create iMessage user login: %w", err)
	}

	if ll.Main.Bridge != nil {
		_, _ = ll.Main.Bridge.GetGhostByID(ctx, SelfUserID)
	}

	ul.Client.Connect(ul.Log.WithContext(ctx))

	return &bridgev2.LoginStep{
		Type:         bridgev2.LoginStepTypeComplete,
		StepID:       "com.apple.imessage.login.complete",
		Instructions: "Connected to Messages on this Mac",
		CompleteParams: &bridgev2.LoginCompleteParams{
			UserLoginID: ul.ID,
			UserLogin:   ul,
		},
	}, nil
}

func (ll *LocalLogin) Cancel() {}

func defaultRoomCapabilities(_ *bridgev2.Portal) *event.RoomFeatures {
	return &event.RoomFeatures{
		MaxTextLength: MaxOutboundTextLength,
		File: event.FileFeatureMap{
			event.MsgImage: {
				MimeTypes:        map[string]event.CapabilitySupportLevel{"image/*": event.CapLevelFullySupported},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: MaxOutboundTextLength,
				MaxSize:          MaxAttachmentBytes,
			},
			event.MsgVideo: {
				MimeTypes:        map[string]event.CapabilitySupportLevel{"video/*": event.CapLevelFullySupported},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: MaxOutboundTextLength,
				MaxSize:          MaxAttachmentBytes,
			},
			event.MsgAudio: {
				MimeTypes:        map[string]event.CapabilitySupportLevel{"audio/*": event.CapLevelFullySupported},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: MaxOutboundTextLength,
				MaxSize:          MaxAttachmentBytes,
			},
			event.CapMsgVoice: {
				MimeTypes:        map[string]event.CapabilitySupportLevel{"audio/*": event.CapLevelFullySupported},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: MaxOutboundTextLength,
				MaxSize:          MaxAttachmentBytes,
			},
			event.MsgFile: {
				MimeTypes:        map[string]event.CapabilitySupportLevel{"*/*": event.CapLevelFullySupported},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: MaxOutboundTextLength,
				MaxSize:          MaxAttachmentBytes,
			},
			event.CapMsgGIF: {
				MimeTypes:        map[string]event.CapabilitySupportLevel{"image/gif": event.CapLevelFullySupported},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: MaxOutboundTextLength,
				MaxSize:          MaxAttachmentBytes,
			},
		},
		Reply:                event.CapLevelFullySupported,
		Reaction:             event.CapLevelFullySupported,
		ReactionCount:        1,
		AllowedReactions:     []string{"❤️", "👍", "👎", "😂", "‼️", "❓"},
		CustomEmojiReactions: true,
		ReadReceipts:         true,
	}
}

// ParseChatGUID splits an iMessage chat GUID ("iMessage;-;+15551234567" or "iMessage;+;chat123")
// into service, chatIdentifier, and isGroup.
func ParseChatGUID(guid string) (service, identifier string, isGroup bool) {
	s := strings.TrimSpace(guid)
	if before, after, ok := strings.Cut(s, ";-;"); ok {
		return before, after, false
	}
	if before, after, ok := strings.Cut(s, ";+;"); ok {
		return before, after, true
	}
	return "iMessage", s, strings.HasPrefix(s, "chat")
}

// MakeDMChatGUID formats a 1:1 iMessage chat GUID for a handle.
func MakeDMChatGUID(service, handle string) string {
	svc := strings.TrimSpace(service)
	if svc == "" {
		svc = "iMessage"
	}
	return svc + ";-;" + strings.TrimSpace(handle)
}

// Client implements bridgev2.NetworkAPI for an iMessage UserLogin.
type Client struct {
	Main      *Connector
	UserLogin *bridgev2.UserLogin

	mu                  sync.Mutex
	metaMu              sync.Mutex
	pollMu              sync.Mutex
	ghostMu             sync.Mutex
	loggedOut           bool
	connected           bool
	chatDB              *ChatDB
	pollCtx             context.Context
	cancelPoll          context.CancelFunc
	pollDone            chan struct{}
	syncedPortals       map[networkid.PortalID]bool
	dispatchedGUIDs     map[string]struct{}
	dispatchedGUIDOrder []string
	pendingOutbounds    []pendingOutboundEcho
	lastState           status.BridgeStateEvent
}

var (
	_ bridgev2.NetworkAPI                    = (*Client)(nil)
	_ bridgev2.BackfillingNetworkAPI         = (*Client)(nil)
	_ bridgev2.IdentifierResolvingNetworkAPI = (*Client)(nil)
	_ bridgev2.GhostDMCreatingNetworkAPI     = (*Client)(nil)
	_ bridgev2.ContactListingNetworkAPI      = (*Client)(nil)
	_ bridgev2.UserSearchingNetworkAPI       = (*Client)(nil)
)

// NewClient constructs a new Client for the given Connector and UserLogin.
func NewClient(main *Connector, login *bridgev2.UserLogin) *Client {
	return &Client{
		Main:            main,
		UserLogin:       login,
		syncedPortals:   make(map[networkid.PortalID]bool),
		dispatchedGUIDs: make(map[string]struct{}),
	}
}

func (c *Client) sender() Sender {
	if c != nil && c.Main != nil && c.Main.Sender != nil {
		return c.Main.Sender
	}
	return NewOSAScriptSender()
}

func (c *Client) homeDir() string {
	if c != nil && c.Main != nil && strings.TrimSpace(c.Main.HomeDir) != "" {
		return strings.TrimSpace(c.Main.HomeDir)
	}
	h, _ := os.UserHomeDir()
	return h
}

func (c *Client) sendBridgeState(st status.BridgeState) {
	c.mu.Lock()
	c.lastState = st.StateEvent
	c.mu.Unlock()
	if c.UserLogin != nil {
		c.UserLogin.BridgeState.Send(st)
	}
}

func (c *Client) Connect(ctx context.Context) {
	if c.UserLogin == nil || c.Main == nil {
		return
	}
	c.Disconnect()

	dbPath := c.Main.resolveChatDBPath(c.UserLogin)
	chatDB, err := OpenChatDB(ctx, dbPath)
	if err != nil {
		c.sendBridgeState(status.BridgeState{
			StateEvent: status.StateBadCredentials,
			Error:      "imessage-chatdb-unavailable",
			Message:    err.Error(),
			UserAction: status.UserActionRelogin,
		})
		return
	}
	if err := chatDB.CheckAccess(ctx); err != nil {
		_ = chatDB.Close()
		c.sendBridgeState(status.BridgeState{
			StateEvent: status.StateBadCredentials,
			Error:      "imessage-chatdb-access-denied",
			Message:    err.Error(),
			UserAction: status.UserActionRelogin,
		})
		return
	}

	if c.UserLogin.Bridge != nil {
		_, _ = c.UserLogin.Bridge.GetGhostByID(ctx, SelfUserID)
	}

	pollCtx, cancel := context.WithCancel(context.Background())
	doneCh := make(chan struct{})

	c.mu.Lock()
	c.loggedOut = false
	c.connected = true
	c.chatDB = chatDB
	c.pollCtx = pollCtx
	c.cancelPoll = cancel
	c.pollDone = doneCh
	if c.syncedPortals == nil {
		c.syncedPortals = make(map[networkid.PortalID]bool)
	}
	if c.dispatchedGUIDs == nil {
		c.dispatchedGUIDs = make(map[string]struct{})
	}
	c.mu.Unlock()

	c.sendBridgeState(status.BridgeState{StateEvent: status.StateConnected})

	// Run initial chat and message sync synchronously on Connect so callers and tests
	// immediately observe the seeded conversations and messages.
	if err := c.SyncNow(pollCtx); err != nil && c.UserLogin != nil {
		c.UserLogin.Log.Warn().Err(err).Msg("imessage initial sync failed")
	}

	interval := c.Main.pollInterval()
	go func() {
		defer close(doneCh)
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-pollCtx.Done():
				return
			case <-ticker.C:
				if pollCtx.Err() != nil {
					return
				}
				if err := c.SyncNow(pollCtx); err != nil && c.UserLogin != nil {
					c.UserLogin.Log.Warn().Err(err).Msg("imessage poll cycle failed")
				}
			}
		}
	}()
}

func (c *Client) Disconnect() {
	c.mu.Lock()
	cancel := c.cancelPoll
	doneCh := c.pollDone
	chatDB := c.chatDB
	c.cancelPoll = nil
	c.pollDone = nil
	c.chatDB = nil
	c.connected = false
	c.mu.Unlock()

	if cancel != nil {
		cancel()
	}
	if doneCh != nil {
		<-doneCh
	}
	if chatDB != nil {
		_ = chatDB.Close()
	}
}

func (c *Client) IsLoggedIn() bool {
	if c == nil || c.UserLogin == nil {
		return false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.loggedOut || c.lastState == status.StateBadCredentials {
		return false
	}
	return c.connected
}

func (c *Client) LogoutRemote(ctx context.Context) {
	c.Disconnect()
	c.mu.Lock()
	c.loggedOut = true
	c.mu.Unlock()
	if c.UserLogin != nil && c.UserLogin.Bridge != nil && c.UserLogin.Bridge.DB != nil {
		_ = c.UserLogin.Save(ctx)
	}
}

func (c *Client) IsThisUser(_ context.Context, userID networkid.UserID) bool {
	if userID == SelfUserID {
		return true
	}
	return c != nil && c.UserLogin != nil && string(userID) == string(c.UserLogin.ID)
}

func (c *Client) GetCapabilities(_ context.Context, portal *bridgev2.Portal) *event.RoomFeatures {
	return defaultRoomCapabilities(portal)
}

func (c *Client) FillBridgeState(state status.BridgeState) status.BridgeState {
	return state
}

// SyncNow executes one immediate sync of chats and new message rows from chat.db.
func (c *Client) SyncNow(ctx context.Context) error {
	c.pollMu.Lock()
	defer c.pollMu.Unlock()

	c.mu.Lock()
	db := c.chatDB
	c.mu.Unlock()
	if db == nil {
		return errors.New("iMessage chat.db is not connected")
	}

	if err := c.syncChats(ctx, db); err != nil {
		return err
	}
	return c.pollMessages(ctx, db)
}

func (c *Client) syncChats(ctx context.Context, db *ChatDB) error {
	chats, err := db.ListChats(ctx, initialChatSyncCap)
	if err != nil {
		return err
	}
	for _, rec := range chats {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err := c.syncSingleChatRecord(ctx, rec); err != nil {
			return err
		}
	}
	return nil
}

func (c *Client) syncSingleChatRecord(ctx context.Context, rec ChatRecord) error {
	if rec.GUID == "" || c.UserLogin == nil || c.UserLogin.Bridge == nil {
		return nil
	}
	portalID := networkid.PortalID(rec.GUID)
	c.mu.Lock()
	alreadySynced := c.syncedPortals[portalID]
	c.mu.Unlock()

	portalKey := networkid.PortalKey{
		ID:       portalID,
		Receiver: c.UserLogin.ID,
	}
	portal, err := c.UserLogin.Bridge.GetPortalByKey(ctx, portalKey)
	if err != nil {
		return fmt.Errorf("get portal %q: %w", portalID, err)
	}

	isDM := rec.IsDM()
	if isDM {
		portal.RoomType = database.RoomTypeDM
		if len(rec.Participants) > 0 {
			portal.OtherUserID = networkid.UserID(rec.Participants[0])
		} else if rec.ChatIdentifier != "" {
			portal.OtherUserID = networkid.UserID(rec.ChatIdentifier)
		}
	} else {
		portal.RoomType = database.RoomTypeDefault
		if rec.DisplayName != "" {
			portal.Name = rec.DisplayName
			portal.NameSet = true
		}
	}

	c.metaMu.Lock()
	meta, ok := portal.Metadata.(*PortalMetadata)
	if !ok || meta == nil {
		meta = &PortalMetadata{}
		portal.Metadata = meta
	}
	meta.ServiceName = rec.ServiceName
	meta.ChatIdentifier = rec.ChatIdentifier
	meta.Style = rec.Style
	if len(rec.Participants) > 0 {
		meta.Participants = slices.Clone(rec.Participants)
	}
	saveErr := portal.Save(ctx)
	c.metaMu.Unlock()
	if saveErr != nil {
		return fmt.Errorf("save portal %q: %w", portalID, saveErr)
	}

	if !alreadySynced || portal.MXID == "" {
		c.mu.Lock()
		c.syncedPortals[portalID] = true
		c.mu.Unlock()

		chatInfo := c.buildChatInfoFromRecord(rec, portal)
		c.queueRemoteEvent(&simplevent.ChatResync{
			EventMeta: simplevent.EventMeta{
				Type:         bridgev2.RemoteEventChatResync,
				PortalKey:    portalKey,
				CreatePortal: true,
			},
			ChatInfo: chatInfo,
		})
	}
	return nil
}

func (c *Client) ensurePortalForMessage(ctx context.Context, db *ChatDB, row MessageRecord) error {
	if row.ChatGUID == "" {
		return nil
	}
	portalID := networkid.PortalID(row.ChatGUID)
	c.mu.Lock()
	synced := c.syncedPortals[portalID]
	c.mu.Unlock()
	if synced {
		return nil
	}
	chatRec, err := db.GetChatByGUID(ctx, row.ChatGUID)
	if err != nil {
		return err
	}
	if chatRec == nil {
		chatRec = &ChatRecord{
			GUID:           row.ChatGUID,
			ChatIdentifier: row.ChatIdentifier,
			ServiceName:    row.Service,
			Style:          row.ChatStyle,
			LastMessageTS:  row.Date,
		}
		if row.SenderHandle != "" {
			chatRec.Participants = []string{row.SenderHandle}
		} else if row.ChatIdentifier != "" && chatRec.IsDM() {
			chatRec.Participants = []string{row.ChatIdentifier}
		}
	}
	return c.syncSingleChatRecord(ctx, *chatRec)
}

func (c *Client) storedLastRowID() int64 {
	if c.UserLogin == nil {
		return 0
	}
	c.metaMu.Lock()
	defer c.metaMu.Unlock()
	if meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata); ok && meta != nil {
		return meta.LastRowID
	}
	return 0
}

func (c *Client) advanceLastRowID(ctx context.Context, rowID int64) error {
	if rowID <= 0 || c.UserLogin == nil {
		return nil
	}
	c.metaMu.Lock()
	defer c.metaMu.Unlock()
	meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata)
	if !ok || meta == nil {
		meta = &UserLoginMetadata{}
		c.UserLogin.Metadata = meta
	}
	if rowID <= meta.LastRowID {
		return nil
	}
	meta.LastRowID = rowID
	if c.UserLogin.Bridge != nil && c.UserLogin.Bridge.DB != nil {
		return c.UserLogin.Save(ctx)
	}
	return nil
}

func (c *Client) pollMessages(ctx context.Context, db *ChatDB) error {
	afterRowID := c.storedLastRowID()
	for {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		rows, err := db.FetchMessagesAfterRowID(ctx, afterRowID, pollBatchSize)
		if err != nil {
			return err
		}
		if len(rows) == 0 {
			return nil
		}
		for _, row := range rows {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			if err := c.processMessageRow(ctx, db, row); err != nil && c.UserLogin != nil {
				c.UserLogin.Log.Warn().Err(err).Int64("rowid", row.RowID).Str("guid", row.GUID).Msg("imessage failed to process message row")
			}
			afterRowID = row.RowID
			_ = c.advanceLastRowID(ctx, row.RowID)
		}
		if len(rows) < pollBatchSize {
			return nil
		}
	}
}

func (c *Client) eventSender(row MessageRecord) bridgev2.EventSender {
	if row.IsFromMe {
		var loginID networkid.UserLoginID
		if c.UserLogin != nil {
			loginID = c.UserLogin.ID
		}
		return bridgev2.EventSender{
			IsFromMe:    true,
			SenderLogin: loginID,
			Sender:      SelfUserID,
		}
	}
	senderHandle := strings.TrimSpace(row.SenderHandle)
	if senderHandle == "" {
		_, ident, isGroup := ParseChatGUID(row.ChatGUID)
		if !isGroup && ident != "" {
			senderHandle = ident
		}
	}
	return bridgev2.EventSender{
		Sender: networkid.UserID(senderHandle),
	}
}

func (c *Client) markDispatched(portalID networkid.PortalID, msgID networkid.MessageID) {
	if msgID == "" {
		return
	}
	key := string(portalID) + "|" + string(msgID)
	c.mu.Lock()
	defer c.mu.Unlock()
	c.recordDispatchedLocked(key)
}

func (c *Client) recordDispatchedLocked(key string) {
	if c.dispatchedGUIDs == nil {
		c.dispatchedGUIDs = make(map[string]struct{})
	}
	if _, exists := c.dispatchedGUIDs[key]; exists {
		return
	}
	for len(c.dispatchedGUIDs) >= maxDispatchedGUIDs && len(c.dispatchedGUIDOrder) > 0 {
		oldest := c.dispatchedGUIDOrder[0]
		c.dispatchedGUIDOrder = c.dispatchedGUIDOrder[1:]
		delete(c.dispatchedGUIDs, oldest)
	}
	c.dispatchedGUIDs[key] = struct{}{}
	c.dispatchedGUIDOrder = append(c.dispatchedGUIDOrder, key)
}

func (c *Client) isOrMarkDispatched(ctx context.Context, portalID networkid.PortalID, row MessageRecord) bool {
	dedupKey := string(portalID) + "|" + row.GUID
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, exists := c.dispatchedGUIDs[dedupKey]; exists {
		return true
	}
	if row.IsFromMe && c.consumePendingOutboundEchoLocked(row.ChatGUID, row.Text, time.Now().UTC()) {
		c.recordDispatchedLocked(dedupKey)
		return true
	}
	if c.UserLogin != nil && c.UserLogin.Bridge != nil && c.UserLogin.Bridge.DB != nil && c.UserLogin.Bridge.DB.Message != nil {
		if existing, err := c.UserLogin.Bridge.DB.Message.GetFirstPartByID(ctx, c.UserLogin.ID, networkid.MessageID(row.GUID)); err == nil && existing != nil {
			c.recordDispatchedLocked(dedupKey)
			return true
		}
	}
	c.recordDispatchedLocked(dedupKey)
	return false
}

func (c *Client) processMessageRow(ctx context.Context, db *ChatDB, row MessageRecord) error {
	if row.ChatGUID == "" || row.GUID == "" || c.UserLogin == nil {
		return nil
	}
	if err := c.ensurePortalForMessage(ctx, db, row); err != nil {
		return err
	}

	portalKey := networkid.PortalKey{
		ID:       networkid.PortalID(row.ChatGUID),
		Receiver: c.UserLogin.ID,
	}
	ts := row.Date
	if ts.IsZero() {
		ts = time.Now().UTC()
	}

	if IsTapbackType(row.AssociatedMessageType) {
		emoji, isRemove, ok := TapbackFromRow(row.AssociatedMessageType, row.AssociatedEmoji, row.Text)
		if !ok || row.AssociatedMessageGUID == "" {
			return nil
		}
		targetMsgID := networkid.MessageID(row.AssociatedMessageGUID)
		sender := c.eventSender(row)
		evtType := bridgev2.RemoteEventReaction
		if isRemove {
			evtType = bridgev2.RemoteEventReactionRemove
		}
		c.queueRemoteEvent(&simplevent.Reaction{
			EventMeta: simplevent.EventMeta{
				Type:      evtType,
				PortalKey: portalKey,
				Sender:    sender,
				Timestamp: ts,
			},
			TargetMessage: targetMsgID,
			EmojiID:       networkid.EmojiID(emoji),
			Emoji:         emoji,
		})
		return nil
	}

	if strings.TrimSpace(row.Text) == "" && len(row.Attachments) == 0 {
		return nil
	}
	if c.isOrMarkDispatched(ctx, portalKey.ID, row) {
		return nil
	}

	sender := c.eventSender(row)
	msgEvt := &simplevent.Message[MessageRecord]{
		EventMeta: simplevent.EventMeta{
			Type:         bridgev2.RemoteEventMessage,
			PortalKey:    portalKey,
			Sender:       sender,
			Timestamp:    ts,
			StreamOrder:  row.Date.UnixMicro(),
			CreatePortal: true,
		},
		ID:   networkid.MessageID(row.GUID),
		Data: row,
		ConvertMessageFunc: func(ctx context.Context, portal *bridgev2.Portal, intent bridgev2.MatrixAPI, data MessageRecord) (*bridgev2.ConvertedMessage, error) {
			return c.convertMessageRecord(ctx, portal, intent, data)
		},
	}
	c.queueRemoteEvent(msgEvt)

	// Emit read receipt if the message has already been read in Messages.app.
	if row.IsRead {
		receiptTS := row.DateRead
		if receiptTS.IsZero() {
			receiptTS = ts
		}
		if row.IsFromMe {
			// In a 1:1 DM, is_from_me=1 with is_read=1 means the recipient read our message.
			_, peerHandle, isGroup := ParseChatGUID(row.ChatGUID)
			if !isGroup && peerHandle != "" {
				c.queueRemoteEvent(&simplevent.Receipt{
					EventMeta: simplevent.EventMeta{
						Type:      bridgev2.RemoteEventReadReceipt,
						PortalKey: portalKey,
						Sender:    bridgev2.EventSender{Sender: networkid.UserID(peerHandle)},
						Timestamp: receiptTS,
					},
					LastTarget: networkid.MessageID(row.GUID),
					Targets:    []networkid.MessageID{networkid.MessageID(row.GUID)},
				})
			}
		} else {
			// Incoming message already read by the local user in Messages.app.
			c.queueRemoteEvent(&simplevent.Receipt{
				EventMeta: simplevent.EventMeta{
					Type:      bridgev2.RemoteEventReadReceipt,
					PortalKey: portalKey,
					Sender: bridgev2.EventSender{
						IsFromMe:    true,
						SenderLogin: c.UserLogin.ID,
						Sender:      SelfUserID,
					},
					Timestamp: receiptTS,
				},
				LastTarget: networkid.MessageID(row.GUID),
				Targets:    []networkid.MessageID{networkid.MessageID(row.GUID)},
			})
		}
	}
	return nil
}

func (c *Client) queueRemoteEvent(evt bridgev2.RemoteEvent) {
	if evt == nil || c.UserLogin == nil {
		return
	}
	c.ghostMu.Lock()
	c.UserLogin.QueueRemoteEvent(evt)
	c.ghostMu.Unlock()
}

func msgTypeForMime(mimeType string) event.MessageType {
	lower := strings.ToLower(strings.TrimSpace(mimeType))
	switch {
	case strings.HasPrefix(lower, "image/"):
		return event.MsgImage
	case strings.HasPrefix(lower, "video/"):
		return event.MsgVideo
	case strings.HasPrefix(lower, "audio/"):
		return event.MsgAudio
	default:
		return event.MsgFile
	}
}

func (c *Client) convertMessageRecord(
	ctx context.Context,
	portal *bridgev2.Portal,
	intent bridgev2.MatrixAPI,
	row MessageRecord,
) (*bridgev2.ConvertedMessage, error) {
	var parts []*bridgev2.ConvertedMessagePart
	meta := &MessageMetadata{
		RowID:   row.RowID,
		GUID:    row.GUID,
		Service: row.Service,
	}

	if strings.TrimSpace(row.Text) != "" || len(row.Attachments) == 0 {
		parts = append(parts, &bridgev2.ConvertedMessagePart{
			ID:   networkid.PartID(""),
			Type: event.EventMessage,
			Content: &event.MessageEventContent{
				MsgType: event.MsgText,
				Body:    row.Text,
			},
			DBMetadata: meta,
		})
	}

	var roomID id.RoomID
	if portal != nil {
		roomID = portal.MXID
	}
	if intent == nil && c.UserLogin != nil && c.UserLogin.Bridge != nil {
		intent = c.UserLogin.Bridge.Bot
	}

	for idx, att := range row.Attachments {
		partID := networkid.PartID(fmt.Sprintf("att_%04d", idx))
		fileName := att.EffectiveFileName()
		fullPath := ExpandAttachmentPath(att.Filename, c.homeDir())

		placeholder := func() *bridgev2.ConvertedMessagePart {
			return &bridgev2.ConvertedMessagePart{
				ID:   partID,
				Type: event.EventMessage,
				Content: &event.MessageEventContent{
					MsgType: event.MsgNotice,
					Body:    fmt.Sprintf("Attachment unavailable (%s)", fileName),
				},
				DBMetadata: meta,
			}
		}

		if fullPath == "" {
			parts = append(parts, placeholder())
			continue
		}
		data, err := os.ReadFile(fullPath)
		if err != nil || len(data) == 0 || len(data) > MaxAttachmentBytes {
			parts = append(parts, placeholder())
			continue
		}

		mimeType := strings.TrimSpace(att.MimeType)
		if mimeType == "" || mimeType == "application/octet-stream" {
			mimeType = http.DetectContentType(data)
		}

		var mxcURI id.ContentURIString
		if intent != nil {
			uploadedURI, _, upErr := intent.UploadMedia(ctx, roomID, data, fileName, mimeType)
			if upErr != nil {
				parts = append(parts, placeholder())
				continue
			}
			mxcURI = uploadedURI
		}

		msgType := msgTypeForMime(mimeType)
		parts = append(parts, &bridgev2.ConvertedMessagePart{
			ID:   partID,
			Type: event.EventMessage,
			Content: &event.MessageEventContent{
				MsgType:  msgType,
				Body:     fileName,
				FileName: fileName,
				URL:      mxcURI,
				Info: &event.FileInfo{
					MimeType: mimeType,
					Size:     len(data),
				},
			},
			DBMetadata: meta,
		})
	}

	cm := &bridgev2.ConvertedMessage{
		Parts: parts,
	}
	if row.ReplyToGUID != "" {
		cm.ReplyTo = &networkid.MessageOptionalPartID{
			MessageID: networkid.MessageID(row.ReplyToGUID),
		}
	}
	return cm, nil
}

// FetchMessages implements bridgev2.BackfillingNetworkAPI for on-demand chat history queries.
func (c *Client) FetchMessages(ctx context.Context, fetchParams bridgev2.FetchMessagesParams) (*bridgev2.FetchMessagesResponse, error) {
	if fetchParams.Portal == nil {
		return nil, errors.New("FetchMessages called with nil portal")
	}
	c.mu.Lock()
	db := c.chatDB
	c.mu.Unlock()
	if db == nil {
		return nil, errors.New("iMessage chat.db is not connected")
	}

	limit := fetchParams.Count
	if limit <= 0 {
		limit = 50
	}
	rows, err := db.FetchMessagesForChat(ctx, string(fetchParams.Portal.ID), limit)
	if err != nil {
		return nil, err
	}

	var backfillMsgs []*bridgev2.BackfillMessage
	for _, row := range rows {
		if row.GUID == "" || IsTapbackType(row.AssociatedMessageType) {
			continue
		}
		if strings.TrimSpace(row.Text) == "" && len(row.Attachments) == 0 {
			continue
		}
		cm, err := c.convertMessageRecord(ctx, fetchParams.Portal, nil, row)
		if err != nil {
			return nil, err
		}
		c.markDispatched(fetchParams.Portal.ID, networkid.MessageID(row.GUID))
		backfillMsgs = append(backfillMsgs, &bridgev2.BackfillMessage{
			ConvertedMessage: cm,
			Sender:           c.eventSender(row),
			ID:               networkid.MessageID(row.GUID),
			Timestamp:        row.Date,
			StreamOrder:      row.Date.UnixMicro(),
		})
	}

	return &bridgev2.FetchMessagesResponse{
		Messages:                backfillMsgs,
		HasMore:                 false,
		MarkRead:                false,
		AggressiveDeduplication: true,
	}, nil
}

func (c *Client) buildChatMemberList(isDM bool, otherUserID networkid.UserID, participants []string) *bridgev2.ChatMemberList {
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
				Sender:      SelfUserID,
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
	for _, h := range participants {
		uid := networkid.UserID(strings.TrimSpace(h))
		if uid == "" || uid == SelfUserID {
			continue
		}
		memberMap[uid] = bridgev2.ChatMember{
			EventSender: bridgev2.EventSender{Sender: uid},
			Membership:  event.MembershipJoin,
			PowerLevel:  &level,
		}
	}
	return &bridgev2.ChatMemberList{
		IsFull:      true,
		OtherUserID: otherUserID,
		MemberMap:   memberMap,
		PowerLevels: &bridgev2.PowerLevelOverrides{
			Invite:       &level,
			Kick:         &level,
			StateDefault: &level,
		},
	}
}

func (c *Client) buildChatInfoFromRecord(rec ChatRecord, portal *bridgev2.Portal) *bridgev2.ChatInfo {
	isDM := rec.IsDM()
	roomType := database.RoomTypeDefault
	var otherUserID networkid.UserID
	if isDM {
		roomType = database.RoomTypeDM
		if len(rec.Participants) > 0 {
			otherUserID = networkid.UserID(rec.Participants[0])
		} else if rec.ChatIdentifier != "" {
			otherUserID = networkid.UserID(rec.ChatIdentifier)
		} else if portal != nil {
			otherUserID = portal.OtherUserID
		}
	}

	var namePtr *string
	if !isDM {
		name := strings.TrimSpace(rec.DisplayName)
		if name == "" && len(rec.Participants) > 0 {
			name = strings.Join(rec.Participants, ", ")
		}
		if name != "" {
			namePtr = &name
		}
	}

	return &bridgev2.ChatInfo{
		Name:        namePtr,
		Type:        &roomType,
		CanBackfill: false,
		Members:     c.buildChatMemberList(isDM, otherUserID, rec.Participants),
	}
}

func (c *Client) GetChatInfo(ctx context.Context, portal *bridgev2.Portal) (*bridgev2.ChatInfo, error) {
	if portal == nil {
		return nil, errors.New("nil portal")
	}
	c.mu.Lock()
	db := c.chatDB
	c.mu.Unlock()
	if db != nil {
		if rec, err := db.GetChatByGUID(ctx, string(portal.ID)); err == nil && rec != nil {
			return c.buildChatInfoFromRecord(*rec, portal), nil
		}
	}

	service, ident, isGroup := ParseChatGUID(string(portal.ID))
	style := ChatStyleDM
	if isGroup {
		style = ChatStyleGroup
	}
	var participants []string
	c.metaMu.Lock()
	if meta, ok := portal.Metadata.(*PortalMetadata); ok && meta != nil {
		if meta.ServiceName != "" {
			service = meta.ServiceName
		}
		if meta.ChatIdentifier != "" {
			ident = meta.ChatIdentifier
		}
		if meta.Style != 0 {
			style = meta.Style
		}
		participants = slices.Clone(meta.Participants)
	}
	c.metaMu.Unlock()
	if len(participants) == 0 && style == ChatStyleDM && ident != "" {
		participants = []string{ident}
	}
	rec := ChatRecord{
		GUID:           string(portal.ID),
		ChatIdentifier: ident,
		ServiceName:    service,
		DisplayName:    portal.Name,
		Style:          style,
		Participants:   participants,
	}
	return c.buildChatInfoFromRecord(rec, portal), nil
}

func (c *Client) GetUserInfo(_ context.Context, ghost *bridgev2.Ghost) (*bridgev2.UserInfo, error) {
	if ghost == nil {
		return &bridgev2.UserInfo{}, nil
	}
	handle := strings.TrimSpace(string(ghost.ID))
	if handle == "" || ghost.ID == SelfUserID {
		name := "Me"
		return &bridgev2.UserInfo{
			Name:   &name,
			Avatar: &bridgev2.Avatar{Remove: true},
		}, nil
	}
	var identifiers []string
	if strings.Contains(handle, "@") {
		identifiers = []string{"mailto:" + handle}
	} else if strings.HasPrefix(handle, "+") {
		identifiers = []string{"tel:" + handle}
	}
	return &bridgev2.UserInfo{
		Name:        &handle,
		Identifiers: identifiers,
		Avatar:      &bridgev2.Avatar{Remove: true},
	}, nil
}

// ResolveIdentifier resolves a phone number or email address and optionally opens a 1:1 iMessage DM.
func (c *Client) ResolveIdentifier(ctx context.Context, identifier string, startChat bool) (*bridgev2.ResolveIdentifierResponse, error) {
	cleaned := strings.TrimSpace(identifier)
	if cleaned == "" {
		return nil, errors.New("Enter a phone number or email address for iMessage.")
	}
	uid := networkid.UserID(cleaned)
	var ghost *bridgev2.Ghost
	var userInfo *bridgev2.UserInfo
	if c.UserLogin != nil && c.UserLogin.Bridge != nil {
		ghost, _ = c.UserLogin.Bridge.GetGhostByID(ctx, uid)
		if ghost != nil {
			userInfo, _ = c.GetUserInfo(ctx, ghost)
		}
	}
	if !startChat {
		return &bridgev2.ResolveIdentifierResponse{
			Ghost:    ghost,
			UserID:   uid,
			UserInfo: userInfo,
		}, nil
	}
	chatResp, err := c.startDMWithHandle(ctx, cleaned, ghost, userInfo)
	if err != nil {
		return nil, err
	}
	return &bridgev2.ResolveIdentifierResponse{
		Ghost:    ghost,
		UserID:   uid,
		UserInfo: userInfo,
		Chat:     chatResp,
	}, nil
}

// CreateChatWithGhost opens a 1:1 iMessage DM with an existing ghost.
func (c *Client) CreateChatWithGhost(ctx context.Context, ghost *bridgev2.Ghost) (*bridgev2.CreateChatResponse, error) {
	if ghost == nil || strings.TrimSpace(string(ghost.ID)) == "" {
		return nil, errors.New("missing iMessage contact handle")
	}
	userInfo, _ := c.GetUserInfo(ctx, ghost)
	return c.startDMWithHandle(ctx, strings.TrimSpace(string(ghost.ID)), ghost, userInfo)
}

func (c *Client) startDMWithHandle(
	ctx context.Context,
	handle string,
	_ *bridgev2.Ghost,
	userInfo *bridgev2.UserInfo,
) (*bridgev2.CreateChatResponse, error) {
	if c.UserLogin == nil {
		return nil, errors.New("iMessage is not logged in")
	}
	chatGUID := MakeDMChatGUID("iMessage", handle)
	c.mu.Lock()
	db := c.chatDB
	c.mu.Unlock()
	if db != nil {
		if existing, err := db.GetChatByGUID(ctx, handle); err == nil && existing != nil && existing.GUID != "" {
			chatGUID = existing.GUID
		}
	}

	portalKey := networkid.PortalKey{
		ID:       networkid.PortalID(chatGUID),
		Receiver: c.UserLogin.ID,
	}
	var portal *bridgev2.Portal
	if c.UserLogin.Bridge != nil {
		portal, _ = c.UserLogin.Bridge.GetPortalByKey(ctx, portalKey)
	}
	otherUID := networkid.UserID(handle)
	if portal != nil {
		portal.RoomType = database.RoomTypeDM
		portal.OtherUserID = otherUID
		c.metaMu.Lock()
		meta, ok := portal.Metadata.(*PortalMetadata)
		if !ok || meta == nil {
			meta = &PortalMetadata{}
		}
		meta.ServiceName = "iMessage"
		meta.ChatIdentifier = handle
		meta.Style = ChatStyleDM
		meta.Participants = []string{handle}
		portal.Metadata = meta
		_ = portal.Save(ctx)
		c.metaMu.Unlock()
	}

	rec := ChatRecord{
		GUID:           chatGUID,
		ChatIdentifier: handle,
		ServiceName:    "iMessage",
		Style:          ChatStyleDM,
		Participants:   []string{handle},
	}
	chatInfo := c.buildChatInfoFromRecord(rec, portal)
	if userInfo != nil && userInfo.Name != nil && *userInfo.Name != "" {
		n := *userInfo.Name
		chatInfo.Name = &n
	}

	return &bridgev2.CreateChatResponse{
		PortalKey:  portalKey,
		Portal:     portal,
		PortalInfo: chatInfo,
	}, nil
}

// GetContactList returns all known handles in chat.db as contacts.
func (c *Client) GetContactList(ctx context.Context) ([]*bridgev2.ResolveIdentifierResponse, error) {
	c.mu.Lock()
	db := c.chatDB
	c.mu.Unlock()
	if db == nil {
		return nil, nil
	}
	handles, err := db.ListHandles(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]*bridgev2.ResolveIdentifierResponse, 0, len(handles))
	for _, h := range handles {
		res, err := c.ResolveIdentifier(ctx, h.ID, false)
		if err != nil || res == nil {
			continue
		}
		out = append(out, res)
	}
	return out, nil
}

// SearchUsers searches known handles in chat.db matching query.
func (c *Client) SearchUsers(ctx context.Context, query string) ([]*bridgev2.ResolveIdentifierResponse, error) {
	q := strings.ToLower(strings.TrimSpace(query))
	if q == "" {
		return nil, nil
	}
	contacts, err := c.GetContactList(ctx)
	if err != nil {
		return nil, err
	}
	var matches []*bridgev2.ResolveIdentifierResponse
	for _, ct := range contacts {
		if strings.Contains(strings.ToLower(string(ct.UserID)), q) {
			matches = append(matches, ct)
		}
	}
	return matches, nil
}
