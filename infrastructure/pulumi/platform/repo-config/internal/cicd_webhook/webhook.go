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

// Package cicd_webhook declares the GitHub webhook that sends vitruvian-core's
// GitHub Actions run/job events to the CI collector (spec:
// docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md).
package cicd_webhook

import (
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/repo-config/internal/secrets"
	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

const (
	repoName = "vitruvian-core"
	url      = "https://github-otel.ipv1337.dev/events"
	// Written by `bazel run //tools/gitops:rotate-github-otel-webhook-secret`
	// into both the Actions and Dependabot secret stores. (GitHub forbids
	// secret names starting with GITHUB_.)
	secretEnv = "OTEL_GITHUB_WEBHOOK_SECRET"
	secretCfg = "otelGithubWebhookSecret"
)

// Args is the webhook's full desired state, separate from Manage so it can be
// unit-tested without a Pulumi engine.
func Args(secret pulumi.StringInput) *github.RepositoryWebhookArgs {
	return &github.RepositoryWebhookArgs{
		Repository: pulumi.String(repoName),
		Active:     pulumi.Bool(true),
		Events:     pulumi.StringArray{pulumi.String("workflow_job"), pulumi.String("workflow_run")},
		Configuration: &github.RepositoryWebhookConfigurationArgs{
			Url:         pulumi.String(url),
			ContentType: pulumi.String("json"),
			InsecureSsl: pulumi.Bool(false),
			// StringInput does not satisfy StringPtrInput; its Output does.
			Secret: secret.ToStringOutput(),
		},
	}
}

// Manage declares the webhook. With the secret absent (a local stack without
// it) it declares nothing and says so, rather than creating an UNSIGNED
// webhook the collector would reject.
func Manage(ctx *pulumi.Context) error {
	secret := secrets.EnvOrConfigOptional(config.New(ctx, ""), secretEnv, secretCfg)
	if secret == nil {
		_ = ctx.Log.Warn(secretEnv+" not set: not managing the CI telemetry webhook", nil)
		return nil
	}
	_, err := github.NewRepositoryWebhook(ctx, "cicd-otel-webhook", Args(secret))
	return err
}
