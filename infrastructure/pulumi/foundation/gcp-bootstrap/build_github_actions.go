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

	libcicd "github.com/VitruvianSoftware/pulumi-library/go/pkg/cicd"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// CICDBuildOutputs holds the outputs from the CI/CD build provisioning.
type CICDBuildOutputs struct {
	// WIF outputs (only populated when github_owner is set)
	WIFPoolName     pulumi.StringOutput
	WIFProviderName pulumi.StringOutput
}

// deployGitHubActionsBuild provisions the Workload Identity Federation (WIF)
// resources in the CI/CD project, adapted for a MONOREPO.
//
// The upstream foundation binds one GitHub repo per stage. Here every stage
// lives in a single repo (VitruvianSoftware/vitruvian-core), so instead of
// scoping each stage's service account to a distinct repo we scope it to a
// distinct GitHub Environment: SA `sa-terraform-<stage>` is impersonable only
// from a job running in the `foundation-<stage>` Environment. This preserves
// least privilege on one repo and relies on the cicd library's
// `attribute.environment` mapping (published in go-cicd v0.5.0).
//
// When `github_owner` is set, this creates:
//   - A Workload Identity Pool ("foundation-pool")
//   - A GitHub OIDC provider ("foundation-gh-provider")
//   - Per-SA principalSet bindings on `attribute.environment/foundation-<stage>`
//
// Secrets/vars (WIF provider name, per-stage SA emails) are NOT written from
// here — that is published as GitHub Environment config by the existing
// infrastructure/pulumi/platform/repo_config project, keeping a single GitOps
// owner for GitHub settings and avoiding an admin:org token in this stack.
func deployGitHubActionsBuild(ctx *pulumi.Context, cfg *Config, _ *SeedProject, cicd *CICDProject, sas map[string]*serviceaccount.Account) (*CICDBuildOutputs, error) {
	outputs := &CICDBuildOutputs{}

	// If github_owner is not set, skip WIF provisioning.
	// The user can still use key-based auth (GOOGLE_CREDENTIALS).
	if cfg.GitHubOwner == "" {
		return outputs, nil
	}

	// ========================================================================
	// Workload Identity Pool, Provider, and per-Environment SA bindings
	// ========================================================================
	attributeCondition := cfg.WIFAttributeCondition
	if attributeCondition == "" {
		// Default: restrict to the configured GitHub organization/owner. The
		// per-SA environment principalSet below adds the per-stage scoping.
		attributeCondition = fmt.Sprintf("assertion.repository_owner=='%s'", cfg.GitHubOwner)
	}

	saMappings := make(map[string]libcicd.SAMappingEntry)
	for key, sa := range sas {
		// Scope each stage SA to its GitHub Environment (foundation-<stage>).
		// The stage keys are: bootstrap, org, env, net, proj.
		saMappings[key] = libcicd.SAMappingEntry{
			SAName:    sa.Name,
			Attribute: pulumi.String(fmt.Sprintf("attribute.environment/foundation-%s", key)),
		}
	}

	githubOidc, err := libcicd.NewGitHubOIDC(ctx, "foundation-wif", &libcicd.GitHubOIDCArgs{
		ProjectID:          cicd.ProjectID,
		PoolID:             pulumi.String("foundation-pool"),
		ProviderID:         pulumi.String("foundation-gh-provider"),
		AttributeCondition: pulumi.String(attributeCondition),
		SAMapping:          saMappings,
	})
	if err != nil {
		return nil, err
	}

	// ========================================================================
	// Outputs (consumed by repo_config to publish GitHub Environment config)
	// ========================================================================
	outputs.WIFPoolName = githubOidc.Pool.Name
	outputs.WIFProviderName = githubOidc.Provider.Name

	return outputs, nil
}
