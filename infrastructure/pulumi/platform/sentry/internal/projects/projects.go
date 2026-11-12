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

package projects

import (
	"fmt"
	"strings"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/sentry/internal/config"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	sentry "github.com/pulumiverse/pulumi-sentry/sdk/go/sentry"
)

type ProjectResult struct {
	Project *sentry.SentryProject
	Key     *sentry.SentryKey
}

func Reconcile(ctx *pulumi.Context, org string, teamSlug string, projects []config.ProjectConfig, opts ...pulumi.ResourceOption) (map[string]*ProjectResult, error) {
	results := make(map[string]*ProjectResult)

	for _, p := range projects {
		resName := fmt.Sprintf("project-%s", p.Slug)
		project, err := sentry.NewSentryProject(ctx, resName, &sentry.SentryProjectArgs{
			Organization: pulumi.String(org),
			Team:         pulumi.String(teamSlug),
			Name:         pulumi.String(p.Name),
			Slug:         pulumi.String(p.Slug),
			Platform:     pulumi.String(p.Platform),
			ResolveAge:   pulumi.Int(p.ResolveAge),
		}, opts...)
		if err != nil {
			return nil, fmt.Errorf("creating sentry project %s: %w", p.Slug, err)
		}

		keyName := fmt.Sprintf("key-%s", p.Slug)
		key, err := sentry.NewSentryKey(ctx, keyName, &sentry.SentryKeyArgs{
			Organization: pulumi.String(org),
			Project:      project.Slug,
			Name:         pulumi.Sprintf("%s-default-key", p.Slug),
		}, append(opts, pulumi.DependsOn([]pulumi.Resource{project}))...)
		if err != nil {
			return nil, fmt.Errorf("creating sentry key for project %s: %w", p.Slug, err)
		}

		results[p.Slug] = &ProjectResult{
			Project: project,
			Key:     key,
		}

		browserDsn := key.DsnPublic.ApplyT(func(dsn string) string {
			return strings.Replace(dsn, "sentry.lab.ipv1337.dev", "sentry-ingest.ipv1337.dev", 1)
		}).(pulumi.StringOutput)

		ctx.Export(fmt.Sprintf("%s_dsn_public", p.Slug), key.DsnPublic)
		ctx.Export(fmt.Sprintf("%s_dsn_secret", p.Slug), pulumi.ToSecret(key.DsnSecret))
		ctx.Export(fmt.Sprintf("%s_dsn_browser", p.Slug), browserDsn)
		ctx.Export(fmt.Sprintf("%s_project_id", p.Slug), project.ProjectId)
	}

	return results, nil
}
