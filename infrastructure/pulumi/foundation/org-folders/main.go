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
