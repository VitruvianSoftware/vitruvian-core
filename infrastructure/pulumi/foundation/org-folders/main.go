/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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

		ctx.Export("folder_name", folder.Name)
		ctx.Export("folder_id", folderID)
		return nil
	})
}
