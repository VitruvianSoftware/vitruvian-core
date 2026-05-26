package main

import (
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/pkg/copybara_sync"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		// Manage the auth resources that back the Copybara bidirectional sync
		// between vitruvian-core and each standalone component repository:
		//   - a write deploy key on the standalone repo (export push), and
		//   - GitHub App dispatch credentials (import trigger).
		return copybara_sync.ManageSyncAuth(ctx)
	})
}
