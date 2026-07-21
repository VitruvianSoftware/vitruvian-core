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

// outputs.go is this leaf's export surface (upstream outputs.tf). An
// application's own stacks consume the platform-issued deploy identity from
// here by StackReference instead of minting one.

package main

import "github.com/pulumi/pulumi/sdk/v3/go/pulumi"

// exportOutputs publishes the leaf's results.
func exportOutputs(ctx *pulumi.Context, cfg *AppInfraConfig, refs *stackRefs, deploySAs map[string]pulumi.StringOutput) {
	ctx.Export("environment", pulumi.String(cfg.Env))
	ctx.Export("business_code", pulumi.String(cfg.BusinessCode))
	ctx.Export("region", pulumi.String(cfg.Region))
	ctx.Export("oss_floating_project", refs.OSSFloatingProjectID)
	ctx.Export("oss_floating_project_number", refs.OSSFloatingProjectNumber)
	for app, email := range deploySAs {
		ctx.Export(app+"_deploy_service_account", email)
	}
}
