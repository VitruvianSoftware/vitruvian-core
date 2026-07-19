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

// Environment folder + tag binding — the Pulumi analog of upstream
// env_baseline/folders.tf (google_folder.env + google_tags_tag_binding.folder_env).

package env_baseline

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/tags"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployFolders creates the environment folder and binds the environment tag
// value from the 1-org stage to it. Returns the folder for downstream concerns
// (kms.go, secrets.go, assured_workload.go) to parent on.
func deployFolders(ctx *pulumi.Context, args *Args, res *Result) (*organizations.Folder, error) {
	env := args.Env

	// ========================================================================
	// 1. Environment Folder — folders.tf google_folder.env
	// ========================================================================
	var folderOpts []pulumi.ResourceOption
	if args.FolderDeletionProtection {
		folderOpts = append(folderOpts, pulumi.Protect(true))
	}

	envFolder, err := organizations.NewFolder(ctx, fmt.Sprintf("env-folder-%s", env), &organizations.FolderArgs{
		DisplayName:        pulumi.String(fmt.Sprintf("%s-%s", args.FolderPrefix, env)),
		Parent:             pulumi.String(args.Parent),
		DeletionProtection: pulumi.Bool(args.FolderDeletionProtection),
	}, folderOpts...)
	if err != nil {
		return nil, err
	}
	res.FolderName = envFolder.Name
	res.FolderID = envFolder.ID()

	// ========================================================================
	// 2. Folder Tag Binding — folders.tf google_tags_tag_binding.folder_env
	// Binds the environment_{env} tag value from the 1-org stage to this folder.
	// Upstream parity: TF's time_sleep.wait_60_seconds is a destroy-only delay;
	// Pulumi handles destroy ordering via its dependency graph (DependsOn).
	// ========================================================================
	if args.Tags != nil {
		tagValueID := envTagValue(args.Tags, env)

		if _, err := tags.NewTagBinding(ctx, fmt.Sprintf("tag-binding-%s", env), &tags.TagBindingArgs{
			Parent: envFolder.Name.ApplyT(func(name string) string {
				return fmt.Sprintf("//cloudresourcemanager.googleapis.com/%s", name)
			}).(pulumi.StringOutput),
			TagValue: tagValueID,
		}, pulumi.DependsOn([]pulumi.Resource{envFolder})); err != nil {
			return nil, err
		}
	}

	return envFolder, nil
}

// folderIDString converts the environment folder's ID output into the plain
// folder-id string consumed as a project parent (FolderID) and as the Assured
// Workload provisioned-resources parent.
func folderIDString(envFolder *organizations.Folder) pulumi.StringOutput {
	return envFolder.ID().ApplyT(func(id pulumi.ID) string {
		return string(id)
	}).(pulumi.StringOutput)
}
