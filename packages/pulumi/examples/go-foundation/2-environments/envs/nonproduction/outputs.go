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

// Stack exports for the nonproduction environment leaf — the Pulumi analog of
// upstream 2-environments/envs/nonproduction/outputs.tf.
package main

import (
	"foundation-2-environments/modules/env_baseline"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// exportOutputs mirrors upstream 2-environments/envs/nonproduction/outputs.tf. Each
// stack deploys a single environment, so outputs are un-prefixed.
func exportOutputs(ctx *pulumi.Context, res *env_baseline.Result) {
	ctx.Export("env_folder", res.FolderName)
	ctx.Export("env_kms_project_id", res.KMSProjectID)
	ctx.Export("env_kms_project_number", res.KMSProjectNumber)
	ctx.Export("env_secrets_project_id", res.SecretsProjectID)
	if res.AssuredWorkloadID != (pulumi.StringOutput{}) {
		ctx.Export("assured_workload_id", res.AssuredWorkloadID)
		ctx.Export("assured_workload_resources", res.AssuredWorkloadResources)
	}
}
