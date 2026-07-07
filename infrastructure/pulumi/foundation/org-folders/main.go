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

// Command org-folders creates the top-level umbrella folder for the
// vitruviansoftware.dev foundation (fldr-foundation-1) at the org root.
//
// It exists as a tiny standalone stack so the foundation-bootstrap stage stays
// an unmodified copy of the reference template: bootstrap consumes the folder
// id via its existing `parent_folder` config, which nests fldr-bootstrap, the
// seed/cicd projects, and every downstream stage's resources under this folder
// — fully isolated from the existing fldr-foundation-0 foundation.
package main

import (
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		conf := config.New(ctx, "")
		orgID := conf.Require("org_id")

		displayName := conf.Get("folder_display_name")
		if displayName == "" {
			displayName = "fldr-foundation-1"
		}

		folder, err := organizations.NewFolder(ctx, "foundation-umbrella", &organizations.FolderArgs{
			DisplayName:        pulumi.String(displayName),
			Parent:             pulumi.String("organizations/" + orgID),
			DeletionProtection: pulumi.Bool(true),
		}, pulumi.Protect(true))
		if err != nil {
			return err
		}

		// folder.Name is "folders/<numeric-id>"; foundation-bootstrap's
		// parent_folder config wants the bare numeric id.
		folderID := folder.Name.ApplyT(func(name string) string {
			return strings.TrimPrefix(name, "folders/")
		}).(pulumi.StringOutput)

		// Administrative sub-folder that holds the foundation's utility projects
		// (the Cloud Identity quota project below), so they don't sit loose at the
		// umbrella folder's root.
		adminFolder, err := organizations.NewFolder(ctx, "administrative", &organizations.FolderArgs{
			DisplayName:        pulumi.String("fldr-administrative"),
			Parent:             folder.Name,
			DeletionProtection: pulumi.Bool(true),
		}, pulumi.Protect(true))
		if err != nil {
			return err
		}
		adminFolderID := adminFolder.Name.ApplyT(func(name string) string {
			return strings.TrimPrefix(name, "folders/")
		}).(pulumi.StringOutput)

		// ====================================================================
		// Cloud Identity quota project
		// ====================================================================
		// The foundation-bootstrap stage CREATES Google groups via the Cloud
		// Identity API (create_required_groups/create_optional_groups). That API
		// requires a QUOTA/billing project on every call, and groups are created
		// before the foundation's own seed project exists — so a pre-existing
		// project must supply the quota (bootstrap points its `groups_billing_project`
		// config here). We create a small, dedicated project for exactly that
		// purpose (rather than borrowing an unrelated one) so the config reads
		// sensibly and the dependency is explicit and self-contained. It only ever
		// fronts the Cloud Identity API's quota; it holds no other resources.
		billingAccount := conf.Require("billing_account")

		suffix, err := random.NewRandomId(ctx, "ci-quota-suffix", &random.RandomIdArgs{
			ByteLength: pulumi.Int(2),
		})
		if err != nil {
			return err
		}

		quotaProject, err := organizations.NewProject(ctx, "cloud-identity-quota", &organizations.ProjectArgs{
			Name:           pulumi.String("prj-b-ci-quota"),
			ProjectId:      pulumi.Sprintf("prj-b-ci-quota-%s", suffix.Hex),
			FolderId:       adminFolderID,
			BillingAccount: pulumi.String(billingAccount),
			DeletionPolicy: pulumi.String("DELETE"),
		})
		if err != nil {
			return err
		}

		// Enable the Cloud Identity API on the quota project so it can front the
		// group-creation calls' quota.
		if _, err := projects.NewService(ctx, "cloud-identity-quota-api", &projects.ServiceArgs{
			Project:                  quotaProject.ProjectId,
			Service:                  pulumi.String("cloudidentity.googleapis.com"),
			DisableOnDestroy:         pulumi.Bool(false),
			DisableDependentServices: pulumi.Bool(false),
		}); err != nil {
			return err
		}

		ctx.Export("folder_name", folder.Name)
		ctx.Export("folder_id", folderID)
		ctx.Export("administrative_folder_id", adminFolderID)
		// Consumed by foundation-bootstrap's groups_billing_project config.
		ctx.Export("cloud_identity_quota_project_id", quotaProject.ProjectId)
		return nil
	})
}
