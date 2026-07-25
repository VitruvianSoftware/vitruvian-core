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

// Cross-stage StackReferences for this leaf — the Pulumi analogue of upstream
// 5-app-infra/business_unit_1/development/remote.tf.

package main

import "github.com/pulumi/pulumi/sdk/v3/go/pulumi"

// stackRefs carries the cross-stage outputs this leaf consumes.
type stackRefs struct {
	// From the gcp-projects BU leaf: the environment's OSS app-hosting project.
	// Deployment region: the leaf's region config when set, otherwise the
	// gcp-projects default_region — CONSUMED from the earlier phase so region
	// flows bootstrap -> ... -> projects -> app-infra and cannot drift.
	Region                   pulumi.StringOutput
	OSSFloatingProjectID     pulumi.StringOutput
	OSSFloatingProjectNumber pulumi.StringOutput
	// From the gcp-projects BU leaf: the platform-issued deploy SA per app.
	// Minted one stage up so it cannot edit its own grants.
	DeployServiceAccounts map[string]pulumi.StringOutput
}

// loadStackReferences resolves the stage-4 and stage-0 references. Both are
// unconditional: without a host project there is nowhere to deploy, and without
// the pool a deploy identity cannot be impersonated by CI.
func loadStackReferences(ctx *pulumi.Context, cfg *AppInfraConfig) (*stackRefs, error) {
	projectsStack, err := pulumi.NewStackReference(ctx, "projects", &pulumi.StackReferenceArgs{
		Name: pulumi.String(cfg.ProjectsStackName),
	})
	if err != nil {
		return nil, err
	}
	deploySAs := map[string]pulumi.StringOutput{}
	for _, app := range cfg.Apps {
		deploySAs[app.Name] = projectsStack.GetStringOutput(pulumi.String(app.Name + "_deploy_service_account"))
	}
	appRegion := projectsStack.GetStringOutput(pulumi.String("default_region"))
	if cfg.Region != "" {
		appRegion = pulumi.String(cfg.Region).ToStringOutput()
	}
	return &stackRefs{
		Region:                   appRegion,
		OSSFloatingProjectID:     projectsStack.GetStringOutput(pulumi.String("oss_floating_project")),
		OSSFloatingProjectNumber: projectsStack.GetStringOutput(pulumi.String("oss_floating_project_number")),
		DeployServiceAccounts:    deploySAs,
	}, nil
}
