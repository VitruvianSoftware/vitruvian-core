// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"fmt"
	"strings"

	"go.mau.fi/util/configupgrade"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"
)

const (
	NetworkID   = "gchat"
	DisplayName = "Google Chat"
	FlowCookies = "cookies"
)

// UserLoginMetadata persists the user's Google Chat cookies, User-Agent, and user_revision cursor on the UserLogin row.
type UserLoginMetadata struct {
	Cookies      map[string]string `json:"cookies,omitempty"`
	UserAgent    string            `json:"user_agent,omitempty"`
	UserRevision int64             `json:"user_revision,omitempty"`
}

// PortalMetadata stores per-portal Google Chat revision and threading state.
type PortalMetadata struct {
	Revision       int64    `json:"revision,omitempty"`
	GroupRevision  int64    `json:"group_revision,omitempty"`
	TopicThreaded  bool     `json:"topic_threaded,omitempty"`
	ThreadsEnabled bool     `json:"threads_enabled,omitempty"`
	MemberUserIDs  []string `json:"member_user_ids,omitempty"`
}

// GhostMetadata stores per-ghost Google Chat metadata.
type GhostMetadata struct{}

// MessageMetadata stores per-message Google Chat topic and timestamp metadata.
type MessageMetadata struct {
	TopicID          string `json:"topic_id,omitempty"`
	CreateTimeMicros int64  `json:"create_time_micros,omitempty"`
	LastEditTime     int64  `json:"last_edit_time,omitempty"`
}

// ReactionMetadata stores per-reaction Google Chat topic metadata.
type ReactionMetadata struct {
	TopicID string `json:"topic_id,omitempty"`
}

// Connector implements bridgev2.NetworkConnector for Google Chat.
type Connector struct {
	Bridge  *bridgev2.Bridge
	baseURL string
}

var _ bridgev2.NetworkConnector = (*Connector)(nil)

// NewConnector creates a new Google Chat NetworkConnector.
func NewConnector() bridgev2.NetworkConnector {
	return &Connector{}
}

func (c *Connector) Init(bridge *bridgev2.Bridge) {
	c.Bridge = bridge
}

func (c *Connector) Start(_ context.Context) error {
	return nil
}

func (c *Connector) GetName() bridgev2.BridgeName {
	return bridgev2.BridgeName{
		DisplayName:          DisplayName,
		NetworkURL:           "https://chat.google.com",
		NetworkIcon:          "mxc://maunium.net/ProjGChat",
		NetworkID:            NetworkID,
		BeeperBridgeType:     "googlechat",
		DefaultPort:          29320,
		DefaultCommandPrefix: "!gchat",
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

func defaultRoomCapabilities(portal *bridgev2.Portal) *event.RoomFeatures {
	isDM := portal != nil && portal.RoomType == database.RoomTypeDM
	if portal != nil {
		if parsedDM, _, err := ParsePortalID(portal.ID); err == nil {
			isDM = parsedDM
		}
	}
	var isThreaded bool
	if portal != nil {
		if meta, ok := portal.Metadata.(*PortalMetadata); ok && meta != nil {
			isThreaded = meta.TopicThreaded || meta.ThreadsEnabled
		}
	}

	atRoomLevel := event.CapLevelFullySupported
	if isDM {
		atRoomLevel = event.CapLevelUnsupported
	}
	threadLevel := event.CapLevelUnsupported
	if !isDM && isThreaded {
		threadLevel = event.CapLevelFullySupported
	}

	const maxUploadSize = 200 * 1024 * 1024
	const maxTextLen = 4096

	var stateCaps event.StateFeatureMap
	var memberActions event.MemberFeatureMap
	if !isDM {
		stateCaps = event.StateFeatureMap{
			event.StateRoomName.Type: {Level: event.CapLevelFullySupported},
			event.StateTopic.Type:    {Level: event.CapLevelFullySupported},
		}
		memberActions = event.MemberFeatureMap{
			event.MemberActionInvite: event.CapLevelFullySupported,
			event.MemberActionKick:   event.CapLevelFullySupported,
			event.MemberActionLeave:  event.CapLevelFullySupported,
		}
	}

	return &event.RoomFeatures{
		MaxTextLength: maxTextLen,
		State:         stateCaps,
		MemberActions: memberActions,
		Formatting: event.FormattingFeatureMap{
			event.FmtBold:                event.CapLevelFullySupported,
			event.FmtItalic:              event.CapLevelFullySupported,
			event.FmtStrikethrough:       event.CapLevelFullySupported,
			event.FmtUnderline:           event.CapLevelFullySupported,
			event.FmtInlineCode:          event.CapLevelFullySupported,
			event.FmtCodeBlock:           event.CapLevelFullySupported,
			event.FmtTextForegroundColor: event.CapLevelFullySupported,
			event.FmtUnorderedList:       event.CapLevelPartialSupport,
			event.FmtOrderedList:         event.CapLevelPartialSupport,
			event.FmtBlockquote:          event.CapLevelPartialSupport,
			event.FmtInlineLink:          event.CapLevelFullySupported,
			event.FmtUserLink:            event.CapLevelFullySupported,
			event.FmtAtRoomMention:       atRoomLevel,
			event.FmtHeaders:             event.CapLevelPartialSupport,
		},
		File: event.FileFeatureMap{
			event.MsgImage: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/*": event.CapLevelFullySupported,
				},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: maxTextLen,
				MaxSize:          maxUploadSize,
			},
			event.MsgVideo: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"video/*": event.CapLevelFullySupported,
				},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: maxTextLen,
				MaxSize:          maxUploadSize,
			},
			event.MsgAudio: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"audio/*": event.CapLevelFullySupported,
				},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: maxTextLen,
				MaxSize:          maxUploadSize,
			},
			event.CapMsgVoice: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"audio/*": event.CapLevelFullySupported,
				},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: maxTextLen,
				MaxSize:          maxUploadSize,
			},
			event.MsgFile: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"*/*": event.CapLevelFullySupported,
				},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: maxTextLen,
				MaxSize:          maxUploadSize,
			},
			event.CapMsgGIF: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/gif": event.CapLevelFullySupported,
				},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: maxTextLen,
				MaxSize:          maxUploadSize,
			},
		},
		Thread:              threadLevel,
		Reply:               event.CapLevelFullySupported,
		Edit:                event.CapLevelFullySupported,
		Delete:              event.CapLevelFullySupported,
		Reaction:            event.CapLevelFullySupported,
		ReadReceipts:        true,
		TypingNotifications: true,
		DeleteChat:          isDM,
	}
}

func (c *Connector) GetCapabilities() *bridgev2.NetworkGeneralCapabilities {
	return &bridgev2.NetworkGeneralCapabilities{
		Provisioning: bridgev2.ProvisioningCapabilities{
			ResolveIdentifier: bridgev2.ResolveIdentifierCapabilities{
				CreateDM:    true,
				LookupEmail: true,
			},
		},
	}
}

func (c *Connector) GetBridgeInfoVersion() (info, capabilities int) {
	return 1, 1
}

func (c *Connector) GetConfig() (example string, data any, upgrader configupgrade.Upgrader) {
	return "", nil, nil
}

func (c *Connector) LoadUserLogin(_ context.Context, login *bridgev2.UserLogin) error {
	login.Client = &Client{
		Main:      c,
		UserLogin: login,
	}
	return nil
}

func (c *Connector) GetLoginFlows() []bridgev2.LoginFlow {
	return []bridgev2.LoginFlow{{
		Name:        "Google Account",
		Description: "Sign in with your Google Chat session cookies",
		ID:          FlowCookies,
	}}
}

func (c *Connector) CreateLogin(_ context.Context, user *bridgev2.User, flowID string) (bridgev2.LoginProcess, error) {
	if flowID != FlowCookies {
		return nil, fmt.Errorf("invalid login flow %q", flowID)
	}
	return &CookieLogin{
		User: user,
		Main: c,
	}, nil
}

// MakeUserLoginID turns a Gaia ID into a networkid.UserLoginID.
func MakeUserLoginID(gaiaID string) networkid.UserLoginID {
	return networkid.UserLoginID(gaiaID)
}

// CookieLogin implements bridgev2.LoginProcessCookies for Google Chat.
type CookieLogin struct {
	User *bridgev2.User
	Main *Connector
}

var _ bridgev2.LoginProcessCookies = (*CookieLogin)(nil)

func (cl *CookieLogin) Start(_ context.Context) (*bridgev2.LoginStep, error) {
	return &bridgev2.LoginStep{
		Type:         bridgev2.LoginStepTypeCookies,
		StepID:       "fi.mau.gchat.login.cookies",
		Instructions: "Sign in to your Google account in the browser window.",
		CookiesParams: &bridgev2.LoginCookiesParams{
			URL:               "https://chat.google.com/",
			UserAgent:         "",
			WaitForURLPattern: `^https://chat\.google\.com/`,
			Fields: []bridgev2.LoginCookieField{
				{ID: "COMPASS", Required: true, Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "COMPASS", CookieDomain: "chat.google.com"}}},
				{ID: "OSID", Required: true, Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "OSID", CookieDomain: "chat.google.com"}}},
				{ID: "SID", Required: true, Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "SID", CookieDomain: "google.com"}}},
				{ID: "HSID", Required: true, Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "HSID", CookieDomain: "google.com"}}},
				{ID: "SSID", Required: true, Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "SSID", CookieDomain: "google.com"}}},
				{ID: "APISID", Required: false, Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "APISID", CookieDomain: "google.com"}}},
				{ID: "SAPISID", Required: false, Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "SAPISID", CookieDomain: "google.com"}}},
				{ID: "__Secure-1PSID", Required: false, Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "__Secure-1PSID", CookieDomain: "google.com"}}},
				{ID: "__Secure-3PSID", Required: false, Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "__Secure-3PSID", CookieDomain: "google.com"}}},
				{ID: "user_agent", Required: false, Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeSpecial, Name: "user_agent"}}},
			},
		},
	}, nil
}

func (cl *CookieLogin) SubmitCookies(ctx context.Context, cookies map[string]string) (*bridgev2.LoginStep, error) {
	cleaned := make(map[string]string, len(cookies))
	var userAgent string
	for k, v := range cookies {
		if k == "user_agent" {
			userAgent = strings.TrimSpace(v)
			continue
		}
		if strings.TrimSpace(v) != "" {
			cleaned[k] = v
		}
	}

	validated, err := ValidateSession(SessionConfig{
		CookieMap: cleaned,
		UserAgent: userAgent,
		BaseURL:   cl.Main.baseURL,
	})
	if err != nil {
		return nil, err
	}

	var remoteName string
	switch {
	case validated.Name != "" && validated.Email != "":
		remoteName = fmt.Sprintf("%s (%s)", validated.Name, validated.Email)
	case validated.Name != "":
		remoteName = validated.Name
	case validated.Email != "":
		remoteName = validated.Email
	default:
		remoteName = validated.GaiaID
	}

	ul, err := cl.User.NewLogin(ctx, &database.UserLogin{
		ID:         MakeUserLoginID(validated.GaiaID),
		RemoteName: remoteName,
		RemoteProfile: status.RemoteProfile{
			Email: validated.Email,
			Name:  validated.Name,
		},
		Metadata: &UserLoginMetadata{
			Cookies:   cleaned,
			UserAgent: userAgent,
		},
	}, &bridgev2.NewLoginParams{
		DeleteOnConflict: true,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create user login: %w", err)
	}

	ul.Client.Connect(ul.Log.WithContext(ctx))

	return &bridgev2.LoginStep{
		Type:         bridgev2.LoginStepTypeComplete,
		StepID:       "fi.mau.gchat.login.complete",
		Instructions: fmt.Sprintf("Signed in as %s", remoteName),
		CompleteParams: &bridgev2.LoginCompleteParams{
			UserLoginID: ul.ID,
			UserLogin:   ul,
		},
	}, nil
}

func (cl *CookieLogin) Cancel() {}
