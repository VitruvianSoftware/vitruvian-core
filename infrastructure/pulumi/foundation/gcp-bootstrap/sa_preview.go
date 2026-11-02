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

package main

import (
	"fmt"
	"sort"
	"strings"

	"github.com/VitruvianSoftware/pulumi-library/go/pkg/iam"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Read-only identities for pull-request previews.
//
// A PR preview only needs to READ what is deployed so `pulumi preview` can diff
// against it. It does not need the stage's deploy roles, so each stage gets a
// second, read-only service account, and the `foundation-*-preview` GitHub
// Environments federate to that account (see build_github.go) instead of to the
// stage's deploy account.
//
// Naming: `sa-terraform-<stage>-preview`. Service account ids are capped at 30
// characters; the longest, `sa-terraform-bootstrap-preview`, is exactly 30, and
// previewSAAccountID refuses anything longer so a new stage key cannot silently
// produce an id GCP rejects at apply time.

// previewStageKeys are the stage keys that get a read-only preview identity.
// They match the deploy SA keys minted in deployIAM.
var previewStageKeys = []string{"bootstrap", "org", "env", "net", "proj"}

// previewReadRoles is the COMPLETE set of roles a preview identity holds, at the
// organization. Every one is a viewer role: list the resource hierarchy, read
// IAM policies, read org policies, read folders. Nothing here can change a
// resource, act as another service account, or read secret payloads; the unit
// tests pin this list exactly.
var previewReadRoles = []string{
	"roles/browser",
	"roles/iam.securityReviewer",
	"roles/orgpolicy.policyViewer",
	"roles/resourcemanager.folderViewer",
}

// previewEnvironments maps each PR-preview GitHub Environment to the stage key
// of the read-only identity it federates to. org-folders previews with the
// bootstrap identity and app-infra with the projects identity, mirroring which
// deploy SA each stage uses.
var previewEnvironments = map[string]string{
	"foundation-bootstrap-preview":   "bootstrap",
	"foundation-org-preview":         "org",
	"foundation-env-preview":         "env",
	"foundation-net-preview":         "net",
	"foundation-proj-preview":        "proj",
	"foundation-org-folders-preview": "bootstrap",
	"foundation-app-preview":         "proj",
}

// maxServiceAccountIDLen is GCP's limit on a service account id (6-30 chars).
const maxServiceAccountIDLen = 30

// previewSAAccountID returns the account id of a stage's preview identity.
func previewSAAccountID(key string) (string, error) {
	id := fmt.Sprintf("sa-terraform-%s-preview", key)
	if len(id) > maxServiceAccountIDLen {
		return "", fmt.Errorf("preview service account id %q is %d characters; GCP allows at most %d", id, len(id), maxServiceAccountIDLen)
	}
	return id, nil
}

// previewBindingKey is the WIF binding key for a preview Environment. It is
// distinct from the existing `<stage>-preview` keys, which bind the same
// Environments to the deploy SAs and are removed in a follow-up.
func previewBindingKey(environment string) string {
	return strings.TrimPrefix(environment, "foundation-") + "-readonly"
}

// deployPreviewIdentities creates one read-only service account per stage in
// the seed project (next to the deploy SAs) and grants it previewReadRoles at
// the organization. It returns the accounts keyed by stage key.
func deployPreviewIdentities(ctx *pulumi.Context, cfg *Config, seed *SeedProject, opts ...pulumi.ResourceOption) (map[string]*serviceaccount.Account, error) {
	saOpts := append([]pulumi.ResourceOption{}, opts...)
	if seed.APIsReady != nil {
		saOpts = append(saOpts, pulumi.DependsOn([]pulumi.Resource{seed.APIsReady}))
	}

	keys := append([]string{}, previewStageKeys...)
	sort.Strings(keys)

	previewSAs := make(map[string]*serviceaccount.Account, len(keys))
	for _, key := range keys {
		accountID, err := previewSAAccountID(key)
		if err != nil {
			return nil, err
		}
		sa, err := serviceaccount.NewAccount(ctx, accountID, &serviceaccount.AccountArgs{
			Project:     seed.ProjectID,
			AccountId:   pulumi.String(accountID),
			DisplayName: pulumi.String(fmt.Sprintf("Foundation %s preview SA (read-only). Managed by Pulumi.", key)),
			Description: pulumi.String("Read-only identity for pull-request previews of this foundation stage."),
		}, saOpts...)
		if err != nil {
			return nil, err
		}
		previewSAs[key] = sa

		member := sa.Email.ApplyT(func(email string) string {
			return "serviceAccount:" + email
		}).(pulumi.StringOutput)
		for _, role := range previewReadRoles {
			roleName := strings.ReplaceAll(strings.TrimPrefix(role, "roles/"), ".", "-")
			if _, err := iam.NewOrganizationIAMMember(ctx, fmt.Sprintf("org-iam-%s-preview-%s", key, roleName), &iam.OrganizationIAMMemberArgs{
				OrgID:  pulumi.String(cfg.OrgID),
				Role:   pulumi.String(role),
				Member: member,
			}, opts...); err != nil {
				return nil, err
			}
		}
	}
	return previewSAs, nil
}
