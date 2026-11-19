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
	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// The GitHub Environment that .github/workflows/sentry-pagerduty-apply.yaml
// binds. Holds SENTRY_TOKEN (the dedicated CI Sentry internal-integration
// token) and HEADSCALE_CI_AUTHKEY (reusable ephemeral tag:ci pre-auth key) so
// only main deploys may read them; no required reviewer is attached because
// the stack reconciles Sentry PagerDuty alert rules automatically on push and
// on schedule.
//
// The secrets themselves are NOT managed here, for the reason oauthEnvironment
// gives; //tools/sync-env-secrets sets them (`set -- sentry-production
// SENTRY_TOKEN`, copy `HEADSCALE_CI_AUTHKEY`, then `apply -- sentry-production`).
const sentryProductionEnvironmentName = "sentry-production"

// sentryEnvironment declares the main-only sentry-production environment with
// no required reviewers.
func sentryEnvironment(ctx *pulumi.Context, repo *github.Repository) error {
	return mainOnlyEnvironment(ctx, repo, sentryProductionEnvironmentName, nil)
}
