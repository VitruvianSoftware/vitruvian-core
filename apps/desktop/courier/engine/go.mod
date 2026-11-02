module github.com/VitruvianSoftware/courier/engine

go 1.26.6

require (
	github.com/mdp/qrterminal/v3 v3.2.1
	github.com/modelcontextprotocol/go-sdk v1.8.0
	github.com/rs/zerolog v1.35.1
	github.com/stretchr/testify v1.12.1
	go.mau.fi/mautrix-gmessages v0.2609.0
	go.mau.fi/mautrix-signal v0.2609.0
	go.mau.fi/mautrix-slack v0.2609.1
	go.mau.fi/mautrix-telegram v0.2609.0
	go.mau.fi/mautrix-whatsapp v0.2609.0
	go.mau.fi/util v0.10.1
	golang.org/x/image v0.46.0
	golang.org/x/term v0.47.0
	golang.org/x/text v0.43.0
	gopkg.in/yaml.v3 v3.0.1
	maunium.net/go/mautrix v0.31.0
)

require (
	github.com/google/jsonschema-go v0.4.3 // indirect
	github.com/segmentio/encoding v0.5.4 // indirect
	github.com/yosida95/uritemplate/v3 v3.0.2 // indirect
	golang.org/x/oauth2 v0.36.0 // indirect
	golang.org/x/time v0.15.0 // indirect
)

require (
	filippo.io/edwards25519 v1.2.0 // indirect
	github.com/beeper/argo-go v1.1.2 // indirect
	github.com/cenkalti/backoff/v4 v4.3.0 // indirect
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/coder/websocket v1.8.15 // indirect
	github.com/coreos/go-systemd/v22 v22.7.0 // indirect
	github.com/elliotchance/orderedmap/v3 v3.1.0 // indirect
	github.com/emersion/go-vcard v0.0.0-20241024213814-c9703dde27ff // indirect
	github.com/gabriel-vasile/mimetype v1.4.15 // indirect
	github.com/go-faster/errors v0.7.1 // indirect
	github.com/go-faster/jx v1.2.0 // indirect
	github.com/go-faster/xor v1.0.0 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/gorilla/websocket v1.5.3 // indirect
	github.com/gotd/ige v0.2.2 // indirect
	github.com/gotd/neo v0.1.5 // indirect
	github.com/klauspost/compress v1.19.2 // indirect
	github.com/lib/pq v1.12.3 // indirect
	github.com/mattn/go-colorable v0.1.15 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/mattn/go-pointer v0.0.1 // indirect
	github.com/mattn/go-sqlite3 v1.14.52 // indirect
	github.com/petermattis/goid v0.0.0-20260820044319-269ab09b5261 // indirect
	github.com/rs/xid v1.6.0 // indirect
	github.com/segmentio/asm v1.2.1 // indirect
	github.com/skip2/go-qrcode v0.0.0-20200617195104-da1b6568686e // indirect
	github.com/slack-go/slack v0.24.0 // indirect
	github.com/tidwall/gjson v1.19.0 // indirect
	github.com/tidwall/match v1.2.0 // indirect
	github.com/tidwall/pretty v1.2.1 // indirect
	github.com/tidwall/sjson v1.2.5 // indirect
	github.com/vektah/gqlparser/v2 v2.5.27 // indirect
	github.com/yuin/goldmark v1.8.6 // indirect
	go.mau.fi/libsignal v0.2.2 // indirect
	go.mau.fi/webp v0.3.0 // indirect
	go.mau.fi/whatsmeow v0.0.0-20260916100317-2375e1751bbd // indirect
	go.mau.fi/zeroconfig v0.2.0 // indirect
	go.mau.fi/zerozap v0.1.2 // indirect
	go.opentelemetry.io/otel v1.45.0 // indirect
	go.opentelemetry.io/otel/trace v1.45.0 // indirect
	go.uber.org/atomic v1.11.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/zap v1.28.0 // indirect
	go.yaml.in/yaml/v3 v3.0.5 // indirect
	golang.org/x/crypto v0.58.0 // indirect
	golang.org/x/exp v0.0.0-20260908205506-85c1c2202aba // indirect
	golang.org/x/net v0.62.0 // indirect
	golang.org/x/sync v0.24.0 // indirect
	golang.org/x/sys v0.49.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260526163538-3dc84a4a5aaa // indirect
	google.golang.org/grpc v1.83.2 // indirect
	google.golang.org/protobuf v1.36.12
	gopkg.in/natefinch/lumberjack.v2 v2.2.1 // indirect
	rsc.io/qr v0.2.0 // indirect
)

// mautrix-slack builds against Beeper's fork of slack-go; replace directives do not carry over from a dependency's
// go.mod, so it is repeated here at the version mautrix-slack v0.2609.1 pins.
replace github.com/slack-go/slack => github.com/beeper/slackgo v0.0.0-20260925001310-ea62f6cbc997
