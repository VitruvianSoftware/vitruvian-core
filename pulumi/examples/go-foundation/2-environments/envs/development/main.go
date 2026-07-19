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

// Foundation stage 2 (environments) — thin env root for the development environment.
//
// Faithful to upstream terraform-example-foundation 2-environments/envs/development:
// this leaf pins the environment identity (development/d), reads the core
// identifiers from stack config and a StackReference to 1-org (for tag values),
// then calls the shared env_baseline module. All resource creation lives in
// ../../modules/env_baseline; the sibling envs/ leaves deploy the other
// environments.
package main

import (
	"foundation-2-environments/modules/env_baseline"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Environment pinned by this leaf project — upstream 2-environments/envs/development
// hardcodes env = "development" in its main.tf; the leaf dir is the pin, not
// per-stack config.
const (
	pinnedEnv     = "development"
	pinnedEnvCode = "d"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadEnvConfig(ctx)

		// StackReference to 1-org for tag values. Core identifiers (org_id,
		// billing_account, prefixes) come from Pulumi config, not remote state,
		// because StackReference outputs are async and env_baseline consumes some
		// as synchronous strings; tags flow as a pulumi.Output into resource args.
		orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.OrgStackName),
		})
		if err != nil {
			return err
		}
		tagsOutput := orgStack.GetOutput(pulumi.String("tags"))

		res, err := env_baseline.Deploy(ctx, &env_baseline.Args{
			Env:                      cfg.Env,
			EnvCode:                  cfg.EnvCode,
			Parent:                   cfg.Parent,
			OrgID:                    cfg.OrgID,
			BillingAccount:           cfg.BillingAccount,
			ProjectPrefix:            cfg.ProjectPrefix,
			FolderPrefix:             cfg.FolderPrefix,
			RandomSuffix:             cfg.RandomSuffix,
			DefaultServiceAccount:    cfg.DefaultServiceAccount,
			ProjectDeletionPolicy:    cfg.ProjectDeletionPolicy,
			FolderDeletionProtection: cfg.FolderDeletionProtection,
			ApiPropagationSeconds:    cfg.ApiPropagationSeconds,
			ProjectBudget:            cfg.ProjectBudget,
			AssuredWorkload:          cfg.AssuredWorkload,
			Tags:                     tagsOutput,
		})
		if err != nil {
			return err
		}

		// Stack exports live in outputs.go — the Pulumi analog of upstream
		// 2-environments/envs/development/outputs.tf.
		exportOutputs(ctx, res)

		return nil
	})
}
