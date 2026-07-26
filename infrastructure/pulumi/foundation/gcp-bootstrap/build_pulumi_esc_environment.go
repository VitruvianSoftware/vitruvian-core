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

	"github.com/pulumi/pulumi-pulumiservice/sdk/go/pulumiservice"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployPulumiESCEnvironments creates the OTHER half of the federation: the
// Pulumi-side environment definition that names the GCP resources built in
// build_pulumi_esc.go.
//
// ---------------------------------------------------------------------------
// WHY THIS IS CODE AND NOT A DOCUMENTED PASTE
// ---------------------------------------------------------------------------
// Federation only works when both halves agree, and the halves live in
// different systems: GCP has to trust a subject, and Pulumi has to present one.
// Leaving the Pulumi half as console YAML meant an operator hand-copying three
// generated identifiers -- the project NUMBER, the pool id, the service account
// email -- into a web form, where a single wrong character produces an opaque
// 400 at exchange time and nothing that says which of the two halves is wrong.
//
// Expressing it here means the identifiers come from the resources themselves,
// so they cannot disagree, and `preview` shows the environment as a resource
// like any other.
//
// The environment is created for each name in `pulumi_esc_environments` -- the
// same list that gets a workload-identity binding -- because those names are
// exactly the subjects this stack has already told GCP to trust. Set
// `pulumi_esc_manage_environments=false` to hand an existing, externally-owned
// environment back to its owner.
func deployPulumiESCEnvironments(ctx *pulumi.Context, cfg *Config, esc *PulumiESCOutputs) error {
	if cfg.PulumiESCOrg == "" || !cfg.PulumiESCManageEnvironments || esc == nil {
		return nil
	}

	for _, env := range cfg.PulumiESCEnvironments {
		// `project/name`. The ESC subject this stack binds is
		// "pulumi:environments:org:<org>:env:<project>/<name>", so anything else
		// here would create an environment that the IAM binding does not cover --
		// authenticating fine and being refused by GCP, which is the confusing
		// direction of failure.
		project, name, ok := strings.Cut(env, "/")
		if !ok || project == "" || name == "" {
			return fmt.Errorf("pulumi_esc_environments entry %q must be \"project/name\": "+
				"that is the shape the workload-identity subject is built from, so a bare "+
				"name would bind one thing and create another", env)
		}

		// The gcp-login `project` field wants the project NUMBER, not the id, and
		// the number is already embedded in the pool's resource name
		// (projects/<number>/locations/global/workloadIdentityPools/<id>). Taking
		// it from there rather than looking the project up again keeps the YAML
		// consistent with the pool it refers to by construction.
		yaml := pulumi.All(esc.WIFPoolName, esc.ServiceAccount).ApplyT(
			func(args []interface{}) (pulumi.AssetOrArchive, error) {
				poolName, _ := args[0].(string)
				serviceAccount, _ := args[1].(string)

				parts := strings.Split(poolName, "/")
				if len(parts) < 2 || parts[0] != "projects" || parts[1] == "" {
					return nil, fmt.Errorf("cannot read the project number from workload identity "+
						"pool name %q (expected projects/<number>/...)", poolName)
				}
				projectNumber := parts[1]

				return pulumi.NewStringAsset(fmt.Sprintf(`values:
  gcp:
    login:
      fn::open::gcp-login:
        project: %s
        oidc:
          workloadPoolId: %s
          providerId: %s
          serviceAccount: %s
`, projectNumber, cfg.PulumiESCPoolID, cfg.PulumiESCProviderID, serviceAccount)), nil
			}).(pulumi.AssetOrArchiveOutput)

		key := strings.NewReplacer("/", "-", ".", "-").Replace(env)
		if _, err := pulumiservice.NewEnvironment(ctx, fmt.Sprintf("pulumi-esc-env-%s", key),
			&pulumiservice.EnvironmentArgs{
				Organization: pulumi.String(cfg.PulumiESCOrg),
				Project:      pulumi.String(project),
				Name:         pulumi.String(name),
				Yaml:         yaml,
			}); err != nil {
			return fmt.Errorf("creating Pulumi ESC environment %q: %w", env, err)
		}
	}
	return nil
}
