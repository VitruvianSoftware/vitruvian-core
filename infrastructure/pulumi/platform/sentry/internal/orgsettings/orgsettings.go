// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Package orgsettings sets organization-wide Sentry settings that the
// Sentry Pulumi provider cannot express. pulumiverse/pulumi-sentry v0.0.9
// and jianyuan/terraform-provider-sentry v0.15.8 have no field for them, so
// a command resource sets them through Sentry's API on create and on any
// change, and confirms the server took them.
package orgsettings

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Settings are the organization options this stack owns.
type Settings struct {
	// ScrubIPAddresses stops Sentry storing any IP address on events, for
	// every project. Without it Sentry fills in the sender's address for
	// browser and Apple SDKs.
	ScrubIPAddresses bool `json:"scrubIPAddresses"`
}

// Desired is what this stack enforces.
var Desired = Settings{ScrubIPAddresses: true}

// OrgURL is the organization details endpoint, from the provider's base URL
// (which ends in /api/).
func OrgURL(baseURL, org string) string {
	return strings.TrimRight(baseURL, "/") + "/0/organizations/" + org + "/"
}

// Body is the JSON the PUT sends.
func Body(s Settings) string {
	b, _ := json.Marshal(s)
	return string(b)
}

// script sends the settings and fails unless Sentry reports every one back
// as set. The token comes from the environment the Pulumi wrapper already
// requires (SENTRY_TOKEN or SENTRY_AUTH_TOKEN) and is never echoed.
const script = `set -eu
token="${SENTRY_TOKEN:-${SENTRY_AUTH_TOKEN:-}}"
[ -n "$token" ] || { echo "SENTRY_TOKEN or SENTRY_AUTH_TOKEN must be set" >&2; exit 1; }
resp="$(curl -fsS -X PUT \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  --data "$SENTRY_ORG_SETTINGS" "$SENTRY_ORG_URL")"
case "$resp" in
  *'"scrubIPAddresses":true'*|*'"scrubIPAddresses": true'*) ;;
  *) echo "Sentry did not confirm scrubIPAddresses=true" >&2; exit 1 ;;
esac
`

// Reconcile applies Desired to the organization.
func Reconcile(ctx *pulumi.Context, baseURL, org string, opts ...pulumi.ResourceOption) (*local.Command, error) {
	url := OrgURL(baseURL, org)
	body := Body(Desired)
	cmd, err := local.NewCommand(ctx, "sentry-org-privacy", &local.CommandArgs{
		Create: pulumi.String(script),
		Update: pulumi.String(script),
		// Removing this resource leaves the setting as it is: turning IP
		// storage back on should be a deliberate change, not a side effect.
		Interpreter: pulumi.StringArray{pulumi.String("/bin/sh"), pulumi.String("-c")},
		Environment: pulumi.StringMap{
			"SENTRY_ORG_URL":      pulumi.String(url),
			"SENTRY_ORG_SETTINGS": pulumi.String(body),
		},
		Triggers: pulumi.Array{pulumi.String(url), pulumi.String(body)},
	}, opts...)
	if err != nil {
		return nil, fmt.Errorf("setting Sentry organization privacy options: %w", err)
	}
	return cmd, nil
}
