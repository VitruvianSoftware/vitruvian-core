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
	"strings"
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func TestActionsCacheStorageLimitPath(t *testing.T) {
	got := actionsCacheStorageLimitPath("VitruvianSoftware", "vitruvian-core")
	want := "repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit"
	if got != want {
		t.Fatalf("actionsCacheStorageLimitPath = %q, want %q", got, want)
	}
}

func TestActionsCacheStorageLimitBody(t *testing.T) {
	for _, tc := range []struct {
		limitGB int
		want    string
	}{
		{limitGB: 15, want: `{"max_cache_size_gb":15}`},
		{limitGB: 10, want: `{"max_cache_size_gb":10}`},
	} {
		got, err := actionsCacheStorageLimitBody(tc.limitGB)
		if err != nil {
			t.Fatalf("actionsCacheStorageLimitBody(%d) unexpected error: %v", tc.limitGB, err)
		}
		if got != tc.want {
			t.Errorf("actionsCacheStorageLimitBody(%d) = %q, want %q", tc.limitGB, got, tc.want)
		}
	}

	for _, bad := range []int{0, -1} {
		if _, err := actionsCacheStorageLimitBody(bad); err == nil {
			t.Errorf("actionsCacheStorageLimitBody(%d) = nil error, want error", bad)
		}
	}
}

func TestActionsCacheLimitScript(t *testing.T) {
	for _, want := range []string{
		"--method PUT",
		"ACTIONS_CACHE_STORAGE_LIMIT_PATH",
		"ACTIONS_CACHE_STORAGE_LIMIT_BODY",
		".max_cache_size_gb",
		"exit 1",
		"GITHUB_TOKEN",
	} {
		if !strings.Contains(actionsCacheLimitScript, want) {
			t.Errorf("actionsCacheLimitScript lacks %q", want)
		}
	}
	for _, forbidden := range []string{
		"--method PATCH",
		"usage-policy",
		"repo_cache_size_limit_in_gb",
		"set -x",
		"echo \"$token",
		"echo \"${token",
	} {
		if strings.Contains(actionsCacheLimitScript, forbidden) {
			t.Errorf("actionsCacheLimitScript must not contain %q", forbidden)
		}
	}
}

func runActionsCacheLimitWithMocks(t *testing.T, pulumiConfig string) (int, *recordingMocks, error) {
	t.Helper()
	if pulumiConfig != "" {
		t.Setenv("PULUMI_CONFIG", pulumiConfig)
	}
	mocks := &recordingMocks{resources: map[string][]resource.PropertyMap{}}
	var gotLimit int
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "")
		repo, err := github.NewRepository(ctx, "vitruvian-core", &github.RepositoryArgs{
			Name: pulumi.String("vitruvian-core"),
		})
		if err != nil {
			return err
		}
		gotLimit, err = manageActionsCacheLimit(ctx, cfg, "VitruvianSoftware", "vitruvian-core", repo)
		return err
	}, pulumi.WithMocks("vitruvian-core-repo-config", "dev", mocks))
	return gotLimit, mocks, err
}

func TestManageActionsCacheLimit(t *testing.T) {
	t.Run("default unset config uses 15 GB", func(t *testing.T) {
		limit, mocks, err := runActionsCacheLimitWithMocks(t, `{}`)
		if err != nil {
			t.Fatalf("manageActionsCacheLimit: %v", err)
		}
		if limit != 15 {
			t.Fatalf("limit = %d, want 15", limit)
		}
		cmds := mocks.resources["command:local:Command"]
		if len(cmds) != 1 {
			t.Fatalf("registered %d command:local:Command resources, want 1", len(cmds))
		}
		in := cmds[0]
		if in["create"].StringValue() != actionsCacheLimitScript || in["update"].StringValue() != actionsCacheLimitScript {
			t.Error("create and update must both run actionsCacheLimitScript")
		}
		if in.HasValue("delete") {
			t.Error("deleting the resource must not change the repository cache limit")
		}
		env := in["environment"].ObjectValue()
		if got := env["ACTIONS_CACHE_STORAGE_LIMIT_PATH"].StringValue(); got != "repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit" {
			t.Errorf("ACTIONS_CACHE_STORAGE_LIMIT_PATH = %q", got)
		}
		if got := env["ACTIONS_CACHE_STORAGE_LIMIT_BODY"].StringValue(); got != `{"max_cache_size_gb":15}` {
			t.Errorf("ACTIONS_CACHE_STORAGE_LIMIT_BODY = %q", got)
		}
		if got := env["ACTIONS_CACHE_SIZE_LIMIT_GB"].StringValue(); got != "15" {
			t.Errorf("ACTIONS_CACHE_SIZE_LIMIT_GB = %q", got)
		}
		triggers := in["triggers"].ArrayValue()
		if len(triggers) != 2 ||
			triggers[0].StringValue() != "repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit" ||
			triggers[1].StringValue() != `{"max_cache_size_gb":15}` {
			t.Errorf("triggers = %v", triggers)
		}
	})

	t.Run("explicit override uses configured GB", func(t *testing.T) {
		limit, mocks, err := runActionsCacheLimitWithMocks(t, `{"vitruvian-core-repo-config:actionsCacheSizeLimitGB":"20"}`)
		if err != nil {
			t.Fatalf("manageActionsCacheLimit: %v", err)
		}
		if limit != 20 {
			t.Fatalf("limit = %d, want 20", limit)
		}
		cmds := mocks.resources["command:local:Command"]
		if len(cmds) != 1 {
			t.Fatalf("registered %d command:local:Command resources, want 1", len(cmds))
		}
		env := cmds[0]["environment"].ObjectValue()
		if got := env["ACTIONS_CACHE_STORAGE_LIMIT_BODY"].StringValue(); got != `{"max_cache_size_gb":20}` {
			t.Errorf("ACTIONS_CACHE_STORAGE_LIMIT_BODY = %q", got)
		}
		if got := env["ACTIONS_CACHE_SIZE_LIMIT_GB"].StringValue(); got != "20" {
			t.Errorf("ACTIONS_CACHE_SIZE_LIMIT_GB = %q", got)
		}
	})

	t.Run("committed Pulumi.dev.yaml resolves to 15 GB", func(t *testing.T) {
		limit, mocks, err := runActionsCacheLimitWithMocks(t, stackConfigEnv(t))
		if err != nil {
			t.Fatalf("manageActionsCacheLimit with Pulumi.dev.yaml: %v", err)
		}
		if limit != 15 {
			t.Fatalf("limit = %d, want 15", limit)
		}
		cmds := mocks.resources["command:local:Command"]
		if len(cmds) != 1 {
			t.Fatalf("registered %d command:local:Command resources, want 1", len(cmds))
		}
		env := cmds[0]["environment"].ObjectValue()
		if got := env["ACTIONS_CACHE_SIZE_LIMIT_GB"].StringValue(); got != "15" {
			t.Errorf("ACTIONS_CACHE_SIZE_LIMIT_GB = %q", got)
		}
	})

	for _, bad := range []string{"0", "-5", "fifteen"} {
		t.Run("invalid config "+bad, func(t *testing.T) {
			_, mocks, err := runActionsCacheLimitWithMocks(t, `{"vitruvian-core-repo-config:actionsCacheSizeLimitGB":"`+bad+`"}`)
			if err == nil {
				t.Fatalf("manageActionsCacheLimit(%q) = nil error, want error", bad)
			}
			if cmds := mocks.resources["command:local:Command"]; len(cmds) != 0 {
				t.Errorf("registered %d commands on invalid input %q, want 0", len(cmds), bad)
			}
		})
	}
}
