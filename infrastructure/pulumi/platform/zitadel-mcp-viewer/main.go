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

// A read-only Zitadel identity for the Zitadel MCP server on James's Mac
// (@warnyin/zitadel-mcp, which authenticates with a Personal Access Token).
//
// It creates one machine user, `mcp-viewer`, makes it a member of the org with
// the single role ORG_OWNER_VIEWER (read everything in the org, change
// nothing), and issues it one PAT with a fixed expiry. The PAT is a SECRET stack
// output: the apply workflow never prints it. James reads it locally once after
// an apply and stores it in Bitwarden.
//
// Its own stack, not an entry in a sibling: zitadel-apps-mcp-slack and
// zitadel-apps-relay each own one app's project and clients, and a machine user
// with org-wide read is a different blast radius from either.
package main

import (
	"fmt"
	"time"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
	"github.com/pulumiverse/pulumi-zitadel/sdk/go/zitadel"
)

// viewerRole is the only org role the machine user gets. ORG_OWNER_VIEWER can
// read users, projects, apps, grants and policies, and cannot change any of
// them. A test pins it so a widening is a reviewed, visible change.
const viewerRole = "ORG_OWNER_VIEWER"

// maxPATLifetime bounds how far ahead patExpiry may be. A token that never
// expires is a credential nobody remembers to rotate.
const maxPATLifetime = 366 * 24 * time.Hour

// resolvePATExpiry parses patExpiry (RFC 3339) and refuses one that is missing,
// unparsable, already past, or more than maxPATLifetime away. Refusing beats a
// silently long-lived token: Zitadel treats an empty expiry as "never".
func resolvePATExpiry(raw string, now time.Time) (string, error) {
	if raw == "" {
		return "", fmt.Errorf("zitadel-mcp-viewer:patExpiry is required (RFC 3339, e.g. 2027-05-24T00:00:00Z); an empty expiry would mint a token that never expires")
	}
	t, err := time.Parse(time.RFC3339, raw)
	if err != nil {
		return "", fmt.Errorf("zitadel-mcp-viewer:patExpiry %q is not RFC 3339: %w", raw, err)
	}
	if !t.After(now) {
		return "", fmt.Errorf("zitadel-mcp-viewer:patExpiry %s is not in the future", raw)
	}
	if t.Sub(now) > maxPATLifetime {
		return "", fmt.Errorf("zitadel-mcp-viewer:patExpiry %s is more than a year away; rotate at least yearly", raw)
	}
	return t.UTC().Format(time.RFC3339), nil
}

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "zitadel-mcp-viewer")
		orgID := cfg.Require("orgId")
		expiry, err := resolvePATExpiry(cfg.Get("patExpiry"), time.Now())
		if err != nil {
			return err
		}

		user, err := zitadel.NewMachineUser(ctx, "mcp-viewer", &zitadel.MachineUserArgs{
			OrgId:       pulumi.String(orgID),
			UserName:    pulumi.String("mcp-viewer"),
			Name:        pulumi.String("MCP viewer"),
			Description: pulumi.String("Read-only identity for the Zitadel MCP server (ORG_OWNER_VIEWER). Managed by infrastructure/pulumi/platform/zitadel-mcp-viewer."),
			// A PAT is a bearer token by nature; JWT applies to machine-key auth.
			AccessTokenType: pulumi.String("ACCESS_TOKEN_TYPE_BEARER"),
			// No client secret: the PAT below is its only credential.
			WithSecret: pulumi.Bool(false),
		})
		if err != nil {
			return err
		}

		if _, err := zitadel.NewOrgMember(ctx, "mcp-viewer", &zitadel.OrgMemberArgs{
			OrgId:  pulumi.String(orgID),
			UserId: user.ID(),
			Roles:  pulumi.StringArray{pulumi.String(viewerRole)},
		}); err != nil {
			return err
		}

		// Changing patExpiry replaces this resource (a new token, the old one
		// deleted), so a rotation is a commit with an `Allow-destroy:` line for
		// this URN, which the plan guard requires.
		pat, err := zitadel.NewPersonalAccessToken(ctx, "mcp-viewer", &zitadel.PersonalAccessTokenArgs{
			OrgId:          pulumi.String(orgID),
			UserId:         user.ID(),
			ExpirationDate: pulumi.String(expiry),
		})
		if err != nil {
			return err
		}

		ctx.Export("machineUserId", user.ID())
		ctx.Export("orgRole", pulumi.String(viewerRole))
		ctx.Export("patExpiry", pulumi.String(expiry))
		// Secret: never print it. Read once with
		//   bazel run //infrastructure/pulumi/platform/zitadel-mcp-viewer:stack -- output patToken --show-secrets
		ctx.Export("patToken", pulumi.ToSecret(pat.Token))
		return nil
	})
}
