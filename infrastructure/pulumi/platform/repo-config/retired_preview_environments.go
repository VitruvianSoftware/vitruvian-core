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
	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// retiredFoundationPreviewEnvironments are GitHub Environments that exist on
// the repository but that nothing uses. GitHub created them on first use when
// the foundation preview jobs briefly named them (#779); #780 renamed the jobs
// to foundation-env-preview / foundation-net-preview, and these two were left
// behind outside any code. They hold no variables, secrets, reviewers or
// branch policy.
//
// They are ADOPTED here, exactly as they are, so they are owned by code. This
// is step 1 of 2: the follow-up removes them from this list, and the next
// apply deletes them. Until then the declared settings must stay equal to the
// live ones (all defaults) so the import changes nothing.
var retiredFoundationPreviewEnvironments = []string{
	"foundation-environments-preview",
	"foundation-networks-preview",
}

func adoptRetiredFoundationPreviewEnvironments(ctx *pulumi.Context, cfg *config.Config, repo *github.Repository) error {
	nm := repoName(cfg)
	for _, env := range retiredFoundationPreviewEnvironments {
		if _, err := github.NewRepositoryEnvironment(ctx, env, &github.RepositoryEnvironmentArgs{
			Repository:  repo.Name,
			Environment: pulumi.String(env),
		}, pulumi.Import(pulumi.ID(nm+":"+env))); err != nil {
			return err
		}
	}
	return nil
}
