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
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Pulumi Cloud's OIDC issuer. Fixed by the vendor; not configurable.
const pulumiESCIssuerURI = "https://api.pulumi.com/oidc"

// PulumiESCOutputs holds what an operator needs to finish the wiring on the
// Pulumi side (the ESC environment definition references the provider by name).
type PulumiESCOutputs struct {
	WIFPoolName     pulumi.StringOutput
	WIFProviderName pulumi.StringOutput
	ServiceAccount  pulumi.StringOutput
}

// deployPulumiESCOIDC lets Pulumi ESC mint short-lived GCP credentials, so a
// Claude Code cloud session can do GCP work with no credential of its own.
//
// ---------------------------------------------------------------------------
// WHY THIS EXISTS
// ---------------------------------------------------------------------------
// A cloud sandbox cannot hold a service-account key: iam.disableServiceAccountKeyCreation
// is enforced org-wide by //infrastructure/pulumi/foundation/gcp-org ("prevent
// SA key sprawl"). //tools/gcp-token solves that today by minting a token over
// the tailnet from a homelab node, which works but means GCP work depends on a
// machine at home being reachable.
//
// ESC removes that dependency: Pulumi Cloud presents an OIDC token, GCP
// exchanges it for a short-lived access token, and nothing local need be awake.
// It was probed against the live account BEFORE this was written -- ESC accepted
// the `fn::open::gcp-login` definition and attempted a real exchange, failing
// only with:
//
//	status 400: invalid_target ... the pool or provider is disabled or deleted
//	                              or because it doesn't exist
//	Subject:  "pulumi:environments:org:<org>:env:<project>/<env>"
//	Audience: "gcp:<org>"
//
// This function creates exactly what that error named, and nothing more.
//
// ---------------------------------------------------------------------------
// THE SERVICE ACCOUNT IS INERT BY DEFAULT, ON PURPOSE
// ---------------------------------------------------------------------------
// No project roles are granted unless `pulumi_esc_roles` says so. A federated
// identity that can authenticate but do nothing is the correct starting point:
// it makes the trust relationship reviewable on its own, and forces the
// capability grant to be a separate, deliberate decision rather than a default
// nobody chose. Grant the narrowest set that makes the session useful --
// `roles/secretmanager.secretAccessor` alone is enough to replace the Secret
// Manager half of //tools/cloud-bootstrap.
//
// Gated on `pulumi_esc_org`: unset, this provisions nothing and the tailnet
// broker remains the only path.
func deployPulumiESCOIDC(ctx *pulumi.Context, cfg *Config, cicd *CICDProject) (*PulumiESCOutputs, error) {
	outputs := &PulumiESCOutputs{}
	if cfg.PulumiESCOrg == "" {
		return outputs, nil
	}
	if len(cfg.PulumiESCEnvironments) == 0 {
		return nil, fmt.Errorf("pulumi_esc_org is set but pulumi_esc_environments is empty: " +
			"an OIDC provider with no subject bound to it can never be used, and a pool " +
			"that trusts an issuer without naming which environments may use it is a " +
			"standing invitation to bind one later without review")
	}

	// The audience Pulumi ESC presents. Derived from the org, not configurable:
	// it is what the service actually sends, confirmed by the probe above, and a
	// mismatch here fails at exchange time with an opaque 400.
	audience := fmt.Sprintf("gcp:%s", cfg.PulumiESCOrg)

	// Mirrors the API-enablement pattern in the gitlab-oidc module: order the
	// pool after the services so a cold first apply is race-free rather than
	// relying on eventual convergence.
	services := make([]pulumi.Resource, 0, 2)
	for _, svc := range []string{"iam.googleapis.com", "sts.googleapis.com"} {
		service, err := projects.NewService(ctx, fmt.Sprintf("esc-%s", svc), &projects.ServiceArgs{
			Project:          cicd.ProjectID,
			Service:          pulumi.String(svc),
			DisableOnDestroy: pulumi.Bool(false),
		})
		if err != nil {
			return nil, fmt.Errorf("enabling %s for Pulumi ESC OIDC: %w", svc, err)
		}
		services = append(services, service)
	}

	pool, err := iam.NewWorkloadIdentityPool(ctx, "pulumi-esc-pool", &iam.WorkloadIdentityPoolArgs{
		Project:                cicd.ProjectID,
		WorkloadIdentityPoolId: pulumi.String(cfg.PulumiESCPoolID),
		DisplayName:            pulumi.String("Pulumi ESC"),
		Description:            pulumi.String("Federates Pulumi Cloud ESC environments so agent sessions need no GCP key"),
		Disabled:               pulumi.Bool(false),
	}, pulumi.DependsOn(services))
	if err != nil {
		return nil, fmt.Errorf("creating the Pulumi ESC workload identity pool: %w", err)
	}

	// AttributeCondition is defence in depth. AllowedAudiences already rejects a
	// token minted for anyone else, but asserting the audience again in CEL means
	// a future edit that widens the audience list does not silently widen who can
	// exchange -- the two have to be widened together, deliberately.
	provider, err := iam.NewWorkloadIdentityPoolProvider(ctx, "pulumi-esc-provider", &iam.WorkloadIdentityPoolProviderArgs{
		Project:                        cicd.ProjectID,
		WorkloadIdentityPoolId:         pool.WorkloadIdentityPoolId,
		WorkloadIdentityPoolProviderId: pulumi.String(cfg.PulumiESCProviderID),
		DisplayName:                    pulumi.String("Pulumi Cloud OIDC"),
		Description:                    pulumi.String("Issuer api.pulumi.com/oidc; subjects are ESC environments"),
		AttributeCondition:             pulumi.String(fmt.Sprintf("assertion.aud == %q", audience)),
		AttributeMapping: pulumi.StringMap{
			"google.subject": pulumi.String("assertion.sub"),
		},
		Oidc: &iam.WorkloadIdentityPoolProviderOidcArgs{
			IssuerUri:        pulumi.String(pulumiESCIssuerURI),
			AllowedAudiences: pulumi.StringArray{pulumi.String(audience)},
		},
	})
	if err != nil {
		return nil, fmt.Errorf("creating the Pulumi ESC OIDC provider: %w", err)
	}

	sa, err := serviceaccount.NewAccount(ctx, "sa-pulumi-esc", &serviceaccount.AccountArgs{
		Project:     cicd.ProjectID,
		AccountId:   pulumi.String(cfg.PulumiESCServiceAccountID),
		DisplayName: pulumi.String("Pulumi ESC federated identity"),
		Description: pulumi.String("Impersonated by Pulumi ESC environments via OIDC; holds no key"),
	})
	if err != nil {
		return nil, fmt.Errorf("creating the Pulumi ESC service account: %w", err)
	}

	// One binding per named ESC environment, on the EXACT subject rather than an
	// attribute principalSet. A principalSet would let any future environment
	// matching the attribute impersonate this account without a review; naming
	// each subject means adding one is a diff.
	for _, env := range cfg.PulumiESCEnvironments {
		subject := fmt.Sprintf("pulumi:environments:org:%s:env:%s", cfg.PulumiESCOrg, env)
		key := strings.NewReplacer("/", "-", ".", "-").Replace(env)
		if _, err := serviceaccount.NewIAMMember(ctx, fmt.Sprintf("sa-pulumi-esc-wif-%s", key), &serviceaccount.IAMMemberArgs{
			ServiceAccountId: sa.Name,
			Role:             pulumi.String("roles/iam.workloadIdentityUser"),
			Member:           pulumi.Sprintf("principal://iam.googleapis.com/%s/subject/%s", pool.Name, subject),
		}); err != nil {
			return nil, fmt.Errorf("binding ESC environment %q to the service account: %w", env, err)
		}
	}

	// Capability, granted only where asked. See the header: inert by default.
	for _, role := range cfg.PulumiESCRoles {
		roleKey := strings.NewReplacer("/", "-", ".", "-").Replace(role)
		if _, err := projects.NewIAMMember(ctx, fmt.Sprintf("sa-pulumi-esc-role-%s", roleKey), &projects.IAMMemberArgs{
			Project: cicd.ProjectID,
			Role:    pulumi.String(role),
			Member:  pulumi.Sprintf("serviceAccount:%s", sa.Email),
		}); err != nil {
			return nil, fmt.Errorf("granting %q to the Pulumi ESC service account: %w", role, err)
		}
	}

	outputs.WIFPoolName = pool.Name
	outputs.WIFProviderName = provider.Name
	outputs.ServiceAccount = sa.Email
	return outputs, nil
}
