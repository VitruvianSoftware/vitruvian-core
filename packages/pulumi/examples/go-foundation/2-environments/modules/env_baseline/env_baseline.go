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

// Package env_baseline is the reusable per-environment baseline module, the
// faithful Pulumi port of upstream terraform-example-foundation
// 2-environments/modules/env_baseline. The thin stage root (main.go) reads the
// environment identity + core identifiers from stack config and calls Deploy;
// all resource creation lives here (env folder + tag binding, KMS project,
// Secrets project, optional Assured Workload).
//
// The package mirrors upstream's file-per-concern layout: folders.go
// (folders.tf), kms.go (kms.tf), secrets.go (secrets.tf), assured_workload.go
// (assured_workload.tf), remote.go (remote.tf), config.go (variables.tf), and
// outputs.go (outputs.tf). This file holds the module entrypoint (Deploy) that
// orchestrates them.
package env_baseline

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Deploy creates all per-environment baseline resources. Mirrors upstream
// 2-environments/modules/env_baseline (folders.tf, kms.tf, secrets.tf,
// assured_workload.tf); each concern lives in its upstream-named file.
func Deploy(ctx *pulumi.Context, args *Args) (*Result, error) {
	res := &Result{}

	// folders.tf — environment folder + tag binding.
	envFolder, err := deployFolders(ctx, args, res)
	if err != nil {
		return nil, err
	}

	// kms.tf — environment KMS project.
	if err := deployKMS(ctx, args, envFolder, res); err != nil {
		return nil, err
	}

	// secrets.tf — environment Secrets project.
	if err := deploySecrets(ctx, args, envFolder, res); err != nil {
		return nil, err
	}

	// assured_workload.tf — optional Assured Workload.
	if err := deployAssuredWorkload(ctx, args, envFolder, res); err != nil {
		return nil, err
	}

	return res, nil
}
