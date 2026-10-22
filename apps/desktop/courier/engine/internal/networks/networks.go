// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package networks is the list of chat networks Courier can bridge, and how to build each one's engine spec.
package networks

import (
	"context"
	"errors"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/rs/zerolog"
	gmessages "go.mau.fi/mautrix-gmessages/pkg/connector"
	slack "go.mau.fi/mautrix-slack/pkg/connector"
	telegram "go.mau.fi/mautrix-telegram/pkg/connector"
	whatsapp "go.mau.fi/mautrix-whatsapp/pkg/connector"
	"gopkg.in/yaml.v3"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Network describes one chat network.
type Network struct {
	Name        string   // "whatsapp", "telegram", "gmessages", "slack", "signal"
	DisplayName string   // "WhatsApp", ...
	Flows       []string // login flow IDs this CLI offers, preferred first
	Spec        func() (engine.Spec, error)
}

// All lists the networks in the order the CLI shows them. Names are lowercase letters only: they become
// ghost-ID prefixes, where an underscore would break parsing.
func All() []Network {
	return append([]Network{
		{
			Name: "whatsapp", DisplayName: "WhatsApp",
			Flows: []string{"qr"},
			Spec:  whatsappSpec,
		},
		{
			Name: "telegram", DisplayName: "Telegram",
			Flows: []string{"qr", "phone"},
			Spec:  telegramSpec,
		},
		{
			Name: "gmessages", DisplayName: "Google Messages",
			// Upstream disabled QR login ("Google has discontinued it", CHANGELOG v26.05) and no longer
			// lists it in GetLoginFlows, though CreateLogin still accepts it. google needs a cookies step plus an emoji
			// match on the phone.
			Flows: []string{"google"},
			Spec:  simpleSpec("gmessages", func() bridgev2.NetworkConnector { return &gmessages.GMConnector{} }),
		},
		{
			Name: "slack", DisplayName: "Slack",
			// email needs an emailed code (and a captcha cookies step if Slack demands one); token needs pasted
			// browser cookies; app needs bot tokens.
			Flows: []string{"email", "token", "app"},
			Spec:  simpleSpec("slack", func() bridgev2.NetworkConnector { return &slack.SlackConnector{} }),
		},
	}, platformNetworks()...)
}

// Start starts every network in nets it can. One that can't start (Telegram without its app credentials, say) is
// reported under its name, from its Spec or from engine.Start, and the others carry on.
func Start(ctx context.Context, dataDir string, s *store.Store, m *media.Store, nets []Network, log zerolog.Logger) (*engine.Engine, map[string]error) {
	errs := map[string]error{}
	var specs []engine.Spec
	for _, n := range nets {
		spec, err := n.Spec()
		if err != nil {
			errs[n.Name] = err
			continue
		}
		specs = append(specs, spec)
	}
	eng, startErrs := engine.Start(ctx, dataDir, s, m, specs, log)
	for name, err := range startErrs {
		errs[name] = err
	}
	return eng, errs
}

// NotStarted turns Start's errors into the reason text of each network that is not running. A key of the form
// "<name> (duplicate)" is dropped: the network of that name is running, and the key only reports a second spec.
func NotStarted(errs map[string]error) map[string]string {
	out := make(map[string]string, len(errs))
	for name, err := range errs {
		if strings.HasSuffix(name, " (duplicate)") {
			continue
		}
		out[name] = err.Error()
	}
	return out
}

// Get finds a network by name.
func Get(name string) (Network, bool) {
	for _, n := range All() {
		if n.Name == name {
			return n, true
		}
	}
	return Network{}, false
}

// simpleSpec is the spec of a network that needs nothing beyond its connector's own example config.
func simpleSpec(name string, newConnector func() bridgev2.NetworkConnector) func() (engine.Spec, error) {
	return func() (engine.Spec, error) {
		return engine.Spec{
			Name:      name,
			Connector: func() (bridgev2.NetworkConnector, error) { return newConnector(), nil },
		}, nil
	}
}

// whatsappSpec is WhatsApp's example config with two changes. A chat archived on the phone is tagged
// m.lowpriority, which the store takes in as archived: the example leaves archive_tag empty, so archived chats
// would arrive in the inbox. And polls arrive as polls (extev_polls), not as text asking people to vote on the
// phone.
func whatsappSpec() (engine.Spec, error) {
	return engine.Spec{
		Name:      "whatsapp",
		Connector: func() (bridgev2.NetworkConnector, error) { return &whatsapp.WhatsAppConnector{}, nil },
		Configure: func(data any) error {
			cfg, ok := data.(*whatsapp.Config)
			if !ok {
				return fmt.Errorf("unexpected WhatsApp config type %T", data)
			}
			cfg.ArchiveTag = event.RoomTagLowPriority
			cfg.ExtEvPolls = true
			return nil
		},
	}, nil
}

const (
	telegramIDEnv   = "COURIER_TELEGRAM_API_ID"
	telegramHashEnv = "COURIER_TELEGRAM_API_HASH"
)

var telegramHashRE = regexp.MustCompile(`^[0-9a-fA-F]{32}$`)

// telegramSpec reads the app credentials Telegram requires of every client. They come only from the environment
// and are never logged: every error below names the variables, never their values.
func telegramSpec() (engine.Spec, error) {
	id := strings.TrimSpace(os.Getenv(telegramIDEnv))
	hash := strings.TrimSpace(os.Getenv(telegramHashEnv))
	if id == "" || hash == "" {
		return engine.Spec{}, errors.New("Telegram needs its own app credentials: create an app at https://my.telegram.org " +
			"and set " + telegramIDEnv + " and " + telegramHashEnv)
	}
	n, err := strconv.ParseUint(id, 10, 31)
	if err != nil || n == 0 {
		return engine.Spec{}, errors.New(telegramIDEnv + " must be the positive whole number shown as \"App api_id\" at https://my.telegram.org")
	}
	if !telegramHashRE.MatchString(hash) {
		return engine.Spec{}, errors.New(telegramHashEnv + " must be the 32-character hex string shown as \"App api_hash\" at https://my.telegram.org")
	}
	return engine.Spec{
		Name:      "telegram",
		Connector: func() (bridgev2.NetworkConnector, error) { return &telegram.TelegramConnector{}, nil },
		// Unmarshalling into the already decoded example config changes only these two keys; every other
		// field keeps the default the example gave it. The hash is quoted so YAML never reads it as a number.
		// The id is written from the parsed number: YAML reads a raw "0042" as octal, which would silently
		// become a different (wrong) credential.
		Configure: func(data any) error {
			return yaml.Unmarshal([]byte(fmt.Sprintf("api_id: %s\napi_hash: %q\n", strconv.FormatUint(n, 10), hash)), data)
		},
	}, nil
}
