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

// The GitHub Environment that .github/workflows/delivery-pagerduty.yaml binds.
// Holds the environment secret PAGERDUTY_TOKEN so only main deploys may read
// it; no required reviewer is attached because the stack manages on-call
// configuration rather than money.
//
// The secret itself is NOT managed here, for the reason oauthEnvironment gives;
// //tools/sync-env-secrets sets it (`set -- pagerduty-production PAGERDUTY_TOKEN`,
// then `apply -- pagerduty-production`).
const pagerdutyProductionEnvironmentName = "pagerduty-production"

// pagerdutyEnvironment declares the main-only pagerduty-production environment
// with no required reviewers.
func pagerdutyEnvironment(ctx *pulumi.Context, repo *github.Repository) error {
	return mainOnlyEnvironment(ctx, repo, pagerdutyProductionEnvironmentName, nil)
}
