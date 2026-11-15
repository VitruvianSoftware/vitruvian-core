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
	"os"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/sentry/internal/alerts"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/sentry/internal/config"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/sentry/internal/projects"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/sentry/internal/teams"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	sentry "github.com/pulumiverse/pulumi-sentry/sdk/go/sentry"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg, err := config.Load(ctx)
		if err != nil {
			return fmt.Errorf("loading stack config: %w", err)
		}

		token := os.Getenv("SENTRY_TOKEN")
		if token == "" {
			token = os.Getenv("SENTRY_AUTH_TOKEN")
		}
		if token == "" {
			return fmt.Errorf("SENTRY_TOKEN or SENTRY_AUTH_TOKEN environment variable must be set")
		}

		provider, err := sentry.NewProvider(ctx, "sentry-provider", &sentry.ProviderArgs{
			BaseUrl: pulumi.String(cfg.BaseURL),
			Token:   pulumi.ToSecret(pulumi.String(token)).(pulumi.StringOutput),
		})
		if err != nil {
			return fmt.Errorf("initializing sentry provider: %w", err)
		}

		provOpt := pulumi.Provider(provider)

		team, err := teams.Reconcile(ctx, cfg.Organization, &cfg.Team, provOpt)
		if err != nil {
			return err
		}

		projResults, err := projects.Reconcile(ctx, cfg.Organization, cfg.Team.Slug, cfg.Projects, provOpt, pulumi.DependsOn([]pulumi.Resource{team}))
		if err != nil {
			return err
		}

		projMap := make(map[string]*sentry.SentryProject)
		for slug, r := range projResults {
			projMap[slug] = r.Project
		}

		if cfg.EnableIssueAlerts {
			if err := alerts.ReconcileDefaultIssueAlerts(ctx, cfg.Organization, projMap, provOpt); err != nil {
				return err
			}
		}

		return nil
	})
}
