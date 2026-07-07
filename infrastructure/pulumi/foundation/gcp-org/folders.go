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

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type Folders struct {
	Common  *organizations.Folder
	Network *organizations.Folder
}

// deployFolders creates the top-level organization folders (Common and Network).
// This mirrors the Terraform foundation's 1-org/envs/shared/folders.tf exactly.
//
// Environment folders (development, nonproduction, production) are created in
// the 2-environments stage, matching the upstream architecture where each stage
// owns its specific resources.
func deployFolders(ctx *pulumi.Context, cfg *OrgConfig) (*Folders, error) {
	// Folder resource options — apply deletion protection when enabled (D11)
	var folderOpts []pulumi.ResourceOption
	if cfg.FolderDeletionProtection {
		folderOpts = append(folderOpts, pulumi.Protect(true))
	}

	// Common Folder
	common, err := organizations.NewFolder(ctx, "common-folder", &organizations.FolderArgs{
		DisplayName:        pulumi.String(fmt.Sprintf("%s-common", cfg.FolderPrefix)),
		Parent:             pulumi.String(cfg.Parent),
		DeletionProtection: pulumi.Bool(cfg.FolderDeletionProtection),
	}, folderOpts...)
	if err != nil {
		return nil, err
	}

	// Network Folder
	network, err := organizations.NewFolder(ctx, "network-folder", &organizations.FolderArgs{
		DisplayName:        pulumi.String(fmt.Sprintf("%s-network", cfg.FolderPrefix)),
		Parent:             pulumi.String(cfg.Parent),
		DeletionProtection: pulumi.Bool(cfg.FolderDeletionProtection),
	}, folderOpts...)
	if err != nil {
		return nil, err
	}

	return &Folders{
		Common:  common,
		Network: network,
	}, nil
}
