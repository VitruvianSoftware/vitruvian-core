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
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// foundation-environments-preview and foundation-networks-preview were two
// GitHub Environments that nothing used. GitHub created them when the
// foundation preview jobs briefly used those names (#779). #780 renamed the
// jobs, and the two Environments were left behind. #4260 brought them into
// the stack unchanged, and removing them from code then deleted them. Nothing
// may declare them again: either one coming back would be an unused
// Environment that a workflow could name to pick up its settings.
func TestRetiredFoundationPreviewEnvironmentsAreNotDeclared(t *testing.T) {
	t.Setenv("PULUMI_CONFIG", stackConfigEnv(t))
	m := &envMocks{resources: map[string][]resource.PropertyMap{}}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "")
		repo, err := github.NewRepository(ctx, "vitruvian-core", &github.RepositoryArgs{
			Name: pulumi.String("vitruvian-core"),
		})
		if err != nil {
			return err
		}
		return foundationEnvironments(ctx, cfg, repo)
	}, pulumi.WithMocks("vitruvian-core-repo-config", "dev", m))
	if err != nil {
		t.Fatalf("foundationEnvironments: %v", err)
	}

	retired := map[string]bool{
		"foundation-environments-preview": true,
		"foundation-networks-preview":     true,
	}
	declared := 0
	for typ, all := range m.resources {
		for _, inputs := range all {
			v, ok := inputs["environment"]
			if !ok || !v.IsString() {
				continue
			}
			if typ == "github:index/repositoryEnvironment:RepositoryEnvironment" {
				declared++
			}
			if retired[v.StringValue()] {
				t.Errorf("%s declares retired Environment %s", typ, v.StringValue())
			}
		}
	}
	// Guard against a vacuous pass: the mocks must have seen the foundation
	// Environments that do still exist.
	if declared == 0 {
		t.Fatal("foundationEnvironments declared no Environments; the check above saw nothing")
	}
}
