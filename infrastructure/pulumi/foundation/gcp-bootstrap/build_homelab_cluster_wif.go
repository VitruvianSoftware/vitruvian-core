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
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/iam"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/orgpolicy"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumiverse/pulumi-time/sdk/go/time"
)

// deployHomelabClusterWIF federates the homelab Kubernetes cluster into this
// foundation so in-cluster workloads (Backstage, Grafana) can read GCP APIs
// with NO service account key.
//
// ---------------------------------------------------------------------------
// WHY KEYLESS IS THE ONLY OPTION
// ---------------------------------------------------------------------------
// `constraints/iam.disableServiceAccountKeyCreation` is enforced org-wide, so
// the usual "download a JSON key, seal it into the cluster" path is closed by
// policy. The workloads also do not run on GCE, so there is no metadata server
// to fall back on. Federating the cluster's own OIDC issuer is what is left,
// and it is the better answer anyway: nothing long-lived to leak or rotate.
//
// ---------------------------------------------------------------------------
// WHY THE JWKS IS INLINE RATHER THAN FETCHED
// ---------------------------------------------------------------------------
// The cluster's issuer is `https://kubernetes.default.svc.cluster.local` -- an
// in-cluster address GCP cannot resolve, let alone reach. A provider whose
// issuer is unreachable normally fails at verification time, so the JWKS is
// supplied STATICALLY via JwksJson. That deliberately avoids exposing the
// Kubernetes API server (or its discovery endpoints) to the internet just to
// satisfy OIDC discovery.
//
// The consequence is that this value must be re-synced if the cluster's signing
// keys are ever rotated -- see docs/gcp-cluster-federation.md.
//
// ---------------------------------------------------------------------------
// WHY THE TRUST IS NARROW
// ---------------------------------------------------------------------------
// A projected ServiceAccount token is mintable by any pod that can mount one,
// so trusting the issuer alone would let ANY workload in the cluster
// impersonate. Two things keep this tight:
//
//   - AttributeCondition pins the accepted subjects to an explicit list of
//     `system:serviceaccount:<ns>:<name>` values, so a new pod in an unrelated
//     namespace is rejected at the provider before any binding is consulted.
//   - The workloadIdentityUser binding is on the EXACT subject principal, not
//     an attribute principalSet -- the same reasoning as the Pulumi ESC
//     provider above it.
//
// The service account this grants access to is read-only by construction: the
// roles it holds are granted in the stack that owns those projects, never here.
func deployHomelabClusterWIF(
	ctx *pulumi.Context,
	cfg *Config,
	cicd *CICDProject,
	issuerPolicy *orgpolicy.Policy,
) (*serviceaccount.Account, error) {
	// Unset config means the whole feature is absent, matching how the Pulumi
	// ESC federation gates itself. A half-configured federation (issuer but no
	// JWKS) is a configuration error, not a reason to build something partial.
	if cfg.ClusterIssuerURI == "" {
		return nil, nil
	}
	if cfg.ClusterJWKSJSON == "" {
		return nil, fmt.Errorf(
			"cluster_issuer_uri is set but cluster_jwks_json is empty: the issuer %q is not reachable from GCP, so the JWKS must be supplied statically",
			cfg.ClusterIssuerURI,
		)
	}
	if len(cfg.ClusterSubjects) == 0 {
		return nil, fmt.Errorf(
			"cluster_issuer_uri is set but cluster_subjects is empty: refusing to federate an issuer that would accept every ServiceAccount in the cluster",
		)
	}

	condition := clusterAttributeCondition(cfg.ClusterSubjects)

	// Same API-enablement ordering as the Pulumi ESC pool: order the pool after
	// the services so a cold first apply is race-free.
	//
	// WHY monitoring.googleapis.com IS ENABLED ON THE *CICD* PROJECT
	// --------------------------------------------------------------
	// It is not this project's metrics that are being read -- the metrics live in
	// the oss-floating app projects. But Google attributes an API call's quota to
	// the CONSUMER project, which for a federated service account defaults to the
	// project the account itself lives in. Without it enabled here, every read
	// fails with a 403 that names this project and not the one being queried:
	//
	//	Cloud Monitoring API has not been used in project 1064807322707
	//	before or it is disabled.
	//
	// which reads like a missing IAM grant on the target and is not. Grafana
	// surfaces it as a bare "403 Forbidden" on the datasource health check, with
	// the useful half of the message discarded.
	//
	// run.googleapis.com is deliberately NOT in this list: Cloud Run reads
	// already work from the same identity, so nothing here needs to change for
	// them, and enabling an API "just in case" widens the project's surface for
	// no demonstrated need.
	services := make([]pulumi.Resource, 0, 3)
	for _, svc := range []string{
		"iam.googleapis.com",
		"sts.googleapis.com",
		"monitoring.googleapis.com",
	} {
		service, err := projects.NewService(ctx, fmt.Sprintf("homelab-cluster-%s", svc), &projects.ServiceArgs{
			Project:          cicd.ProjectID,
			Service:          pulumi.String(svc),
			DisableOnDestroy: pulumi.Bool(false),
		})
		if err != nil {
			return nil, fmt.Errorf("enabling %s for the homelab cluster federation: %w", svc, err)
		}
		services = append(services, service)
	}

	// Its own pool rather than a provider inside foundation-pool: the blast
	// radius of a mistake here stays with the cluster instead of the pool that
	// backs every foundation CI deploy.
	pool, err := iam.NewWorkloadIdentityPool(ctx, "homelab-cluster-pool", &iam.WorkloadIdentityPoolArgs{
		Project:                cicd.ProjectID,
		WorkloadIdentityPoolId: pulumi.String(cfg.ClusterPoolID),
		DisplayName:            pulumi.String("Homelab cluster"),
		Description:            pulumi.String("Federates the homelab k3s cluster so in-cluster workloads need no GCP key"),
		Disabled:               pulumi.Bool(false),
	}, pulumi.DependsOn(services))
	if err != nil {
		return nil, fmt.Errorf("creating the homelab cluster workload identity pool: %w", err)
	}

	// DependsOn alone is NOT enough here, and this is not theoretical: the
	// first apply of this federation failed with exactly the error the issuer
	// policy exists to prevent --
	//
	//	Error 400: Precondition check failed
	//	"Org Policy violated for value:
	//	 'https://kubernetes.default.svc.cluster.local'."
	//
	// -- with the policy already updated in the SAME apply. DependsOn orders the
	// API CALLS; it cannot wait for the org policy to PROPAGATE, and provider
	// creation is validated against the propagated value. The pool, service
	// account and bindings all created fine; only the provider, the one resource
	// that names an issuer, was refused. That is the identical shape recorded in
	// build_wif_issuer_policy.go for the Pulumi ESC issuer, so this is the
	// second time the same race has bitten.
	//
	// Triggers on the policy's etag rather than a constant: the wait then
	// re-arms whenever the policy actually changes -- including when a FOURTH
	// issuer is added later -- instead of sleeping once on first create and
	// never again, which would leave the next federation to rediscover this the
	// hard way.
	var providerDeps []pulumi.Resource
	if issuerPolicy != nil {
		wait, err := time.NewSleep(ctx, "homelab-cluster-wait-issuer-policy", &time.SleepArgs{
			// Org policy propagation is documented as up to ~2 minutes; the
			// analogous WIP-propagation wait in the confidential_space module
			// uses 60s for a narrower change.
			CreateDuration: pulumi.String("120s"),
			Triggers: pulumi.StringMap{
				"issuer_policy_etag": issuerPolicy.Etag,
			},
		}, pulumi.DependsOn([]pulumi.Resource{issuerPolicy}))
		if err != nil {
			return nil, fmt.Errorf("waiting for the issuer allowlist policy to propagate: %w", err)
		}
		providerDeps = append(providerDeps, wait)
	}

	provider, err := iam.NewWorkloadIdentityPoolProvider(ctx, "homelab-cluster-provider", &iam.WorkloadIdentityPoolProviderArgs{
		Project:                        cicd.ProjectID,
		WorkloadIdentityPoolId:         pool.WorkloadIdentityPoolId,
		WorkloadIdentityPoolProviderId: pulumi.String(cfg.ClusterProviderID),
		DisplayName:                    pulumi.String("Homelab cluster OIDC"),
		Description:                    pulumi.String("Projected ServiceAccount tokens from the homelab k3s cluster; JWKS supplied statically"),
		AttributeCondition:             pulumi.String(condition),
		AttributeMapping: pulumi.StringMap{
			"google.subject": pulumi.String("assertion.sub"),
		},
		Oidc: &iam.WorkloadIdentityPoolProviderOidcArgs{
			IssuerUri: pulumi.String(cfg.ClusterIssuerURI),
			JwksJson:  pulumi.String(cfg.ClusterJWKSJSON),
			// The audience the in-cluster projected token is minted for. Pinning
			// it means a token minted for some other audience (the Kubernetes API
			// itself, say) is not replayable against GCP.
			AllowedAudiences: pulumi.StringArray{pulumi.String(cfg.ClusterAudience)},
		},
	}, pulumi.DependsOn(providerDeps))
	if err != nil {
		return nil, fmt.Errorf("creating the homelab cluster OIDC provider: %w", err)
	}

	sa, err := serviceaccount.NewAccount(ctx, "sa-homelab-cluster", &serviceaccount.AccountArgs{
		Project:     cicd.ProjectID,
		AccountId:   pulumi.String(cfg.ClusterServiceAccountID),
		DisplayName: pulumi.String("Homelab cluster federated identity"),
		Description: pulumi.String("Impersonated by in-cluster workloads via OIDC; holds no key. Read-only roles are granted by the stacks owning each project."),
	})
	if err != nil {
		return nil, fmt.Errorf("creating the homelab cluster service account: %w", err)
	}

	// One binding per subject, on the EXACT principal. An attribute principalSet
	// would silently extend impersonation to every future subject the provider
	// accepts; naming them keeps the blast radius equal to the list above.
	for _, s := range cfg.ClusterSubjects {
		member := pulumi.Sprintf("principal://iam.googleapis.com/%s/subject/%s", pool.Name, s)
		if _, err := serviceaccount.NewIAMMember(ctx, "sa-homelab-cluster-wi-"+sanitizeSubject(s), &serviceaccount.IAMMemberArgs{
			ServiceAccountId: sa.Name,
			Role:             pulumi.String("roles/iam.workloadIdentityUser"),
			Member:           member,
		}, pulumi.DependsOn([]pulumi.Resource{provider})); err != nil {
			return nil, fmt.Errorf("binding workloadIdentityUser for %q: %w", s, err)
		}
	}

	return sa, nil
}

// sanitizeSubject turns a Kubernetes subject into a stable Pulumi resource-name
// suffix. Colons are not valid in a URN component, and the subject is the only
// thing distinguishing these bindings from one another.
func sanitizeSubject(subject string) string {
	return strings.NewReplacer(":", "-", "/", "-").Replace(subject)
}

// clusterAttributeCondition builds the CEL that rejects unlisted subjects at the
// provider, before any IAM binding is consulted.
//
// Quoted with %q rather than concatenated: a subject containing a quote would
// otherwise close the CEL string literal early, and the tail of the subject
// would be parsed as CEL. `%q` escapes it, so a malformed subject produces a
// condition that never matches instead of one that means something else.
func clusterAttributeCondition(subjects []string) string {
	parts := make([]string, 0, len(subjects))
	for _, s := range subjects {
		parts = append(parts, fmt.Sprintf("assertion.sub == %q", s))
	}
	return strings.Join(parts, " || ")
}
