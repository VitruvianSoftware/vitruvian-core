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
)

const (
	NetworkID   = "gchat"
	DisplayName = "Google Chat"
	FlowCookies = "cookies"
)

// UserLoginMetadata persists the user's Google Chat cookies and User-Agent on the UserLogin row.
type UserLoginMetadata struct {
	Cookies   map[string]string `json:"cookies,omitempty"`
	UserAgent string            `json:"user_agent,omitempty"`
}

// PortalMetadata stores per-portal Google Chat revision state.
type PortalMetadata struct {
	Revision int64 `json:"revision,omitempty"`
}

// GhostMetadata stores per-ghost Google Chat metadata.
type GhostMetadata struct{}

// MessageMetadata stores per-message Google Chat topic metadata.
type MessageMetadata struct {
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
		UserLogin: func() any { return &UserLoginMetadata{} },
	}
}

func (c *Connector) GetCapabilities() *bridgev2.NetworkGeneralCapabilities {
	return &bridgev2.NetworkGeneralCapabilities{}
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
