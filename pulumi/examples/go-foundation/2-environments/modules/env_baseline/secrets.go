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

// Environment Secrets project — the Pulumi analog of upstream
// env_baseline/secrets.tf (module "env_secrets").

package env_baseline

import (
	"fmt"

	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deploySecrets creates the environment-level Secret Manager project under the
// environment folder.
func deploySecrets(ctx *pulumi.Context, args *Args, envFolder *organizations.Folder, res *Result) error {
	env := args.Env
	envCode := args.EnvCode

	// ========================================================================
	// 4. Secrets Project — secrets.tf module "env_secrets"
	// ========================================================================
	secretsProject, err := project.NewProject(ctx, fmt.Sprintf("env-secrets-%s", env), &project.ProjectArgs{
		ProjectID:             pulumi.String(fmt.Sprintf("%s-%s-secrets", args.ProjectPrefix, envCode)),
		Name:                  pulumi.String(fmt.Sprintf("%s-%s-secrets", args.ProjectPrefix, envCode)),
		FolderID:              folderIDString(envFolder),
		BillingAccount:        pulumi.String(args.BillingAccount),
		RandomProjectID:       args.RandomSuffix,
		DeletionPolicy:        pulumi.String(args.ProjectDeletionPolicy),
		DefaultServiceAccount: args.DefaultServiceAccount,
		// Cold-deploy race fix: wait for freshly-enabled APIs to propagate
		// before dependents (Budget, default-SA deprivilege) use them.
		ApiPropagationSeconds: args.ApiPropagationSeconds,
		ActivateApis: []string{
			"logging.googleapis.com",
			"secretmanager.googleapis.com",
		},
		Labels: pulumi.StringMap{
			"environment":       pulumi.String(env),
			"application_name":  pulumi.String("env-secrets"),
			"billing_code":      pulumi.String("1234"),
			"primary_contact":   pulumi.String("example1"),
			"secondary_contact": pulumi.String("example2"),
			"business_code":     pulumi.String("shared"),
			"env_code":          pulumi.String(envCode),
			"vpc":               pulumi.String("none"),
		},
		Budget: budgetFor(getEnvProjectBudget(args.ProjectBudget, "secret")),
	}, pulumi.DependsOn([]pulumi.Resource{envFolder}))
	if err != nil {
		return err
	}
	res.SecretsProjectID = secretsProject.Project.ProjectId

	return nil
}
