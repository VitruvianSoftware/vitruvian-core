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

// The PagerDuty stack whose "CI / delivery" service key notify-ci-issues
// sends to, and the repository secret that key lands in.
const (
	pagerdutyStackName       = "ipv1337/vitruvian-pagerduty/production"
	pagerdutyCIKeyOutput     = "ciIntegrationKey"
	pagerdutyCIRoutingSecret = "PAGERDUTY_CI_ROUTING_KEY"
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
// with no required reviewers, and the CI routing key secret below.
func pagerdutyEnvironment(ctx *pulumi.Context, repo *github.Repository) error {
	if err := mainOnlyEnvironment(ctx, repo, pagerdutyProductionEnvironmentName, nil); err != nil {
		return err
	}
	return pagerdutyCIRoutingKey(ctx, repo)
}

// pagerdutyCIRoutingKey copies the PagerDuty stack's ciIntegrationKey output
// into the repository secret PAGERDUTY_CI_ROUTING_KEY, which
// .github/workflows/notify-ci-issues.yaml reads to open incidents for CI
// failures.
//
// Unlike the secrets //tools/sync-env-secrets manages, this one is minted by
// infrastructure, so it is read from that stack's state: it never sits in git
// or a local store, nobody copies it by hand, and every apply carries the same
// value, so there is no flip-flop between local and CI applies.
//
// It is a repository secret, not an environment one: the notifier runs on a
// schedule and on workflow_run without an environment. An Events API routing
// key can only open incidents on that one service.
//
// If the PagerDuty stack has not exported the key yet, the secret is skipped
// with a warning rather than failing the apply, for the reason the
// GCP_SERVICE_ACCOUNT lookup in main.go gives: repo-config owns the merge
// queue and must never be blocked by another stack. Without the secret the
// notifier still sends ntfy and says PagerDuty was skipped.
func pagerdutyCIRoutingKey(ctx *pulumi.Context, repo *github.Repository) error {
	ref, err := pulumi.NewStackReference(ctx, "pagerduty-production", &pulumi.StackReferenceArgs{
		Name: pulumi.String(pagerdutyStackName),
	})
	if err != nil {
		return err
	}
	details, err := ref.GetOutputDetails(pagerdutyCIKeyOutput)
	if err != nil {
		return err
	}
	key, _ := details.SecretValue.(string)
	if key == "" {
		// A non-secret output would be a bug upstream, but the key is still
		// the key; never drop it on the floor for being unwrapped.
		key, _ = details.Value.(string)
	}
	if key == "" {
		ctx.Log.Warn(pagerdutyStackName+" has not exported "+pagerdutyCIKeyOutput+
			" yet; leaving "+pagerdutyCIRoutingSecret+" unset, so notify-ci-issues sends ntfy only. "+
			"Re-run repo-config after the PagerDuty stack applies.", nil)
		return nil
	}
	_, err = github.NewActionsSecret(
		ctx, "pagerduty-ci-routing-key", &github.ActionsSecretArgs{
			Repository: repo.Name,
			SecretName: pulumi.String(pagerdutyCIRoutingSecret),
			// `value`, not the deprecated `plaintextValue`. The SDK marks it
			// secret itself; ToSecret keeps that explicit.
			Value: pulumi.ToSecret(pulumi.String(key)).(pulumi.StringOutput),
		},
		// Old and new share one GitHub secret name, so a replacement must
		// delete first: Pulumi's default (create, then delete the old) would
		// end by deleting the secret it had just written.
		pulumi.DeleteBeforeReplace(true),
	)
	return err
}
