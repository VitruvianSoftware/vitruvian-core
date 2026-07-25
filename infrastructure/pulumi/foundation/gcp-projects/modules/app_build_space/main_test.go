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

// Mock-driven tests for app_build_space.
//
// Written WITH the module rather than after it. #1023 shipped the
// serverless_space wiring behind a flag that was off, so no check executed a
// line of it and a service-naming bug reached main; #1026 added the mocks that
// caught it. The same trap applies here — this module lands gated — so the
// tests come first this time.
//
// What they pin is adoption safety: the module must produce the names the LIVE
// resources already have, because taking ownership of a live Artifact Registry
// repository means importing it and applying an EMPTY diff.

package app_build_space

import (
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type mocks int

// NewResource echoes inputs back as state, and additionally synthesises the
// provider-COMPUTED fields the assertions depend on. A service account's email
// is derived by GCP from accountId + project, so without this it comes back
// empty and a test would "fail" for a harness reason rather than a real one.
func (mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	out := args.Inputs
	if args.TypeToken == "gcp:serviceaccount/account:Account" {
		acct := out["accountId"].StringValue()
		proj := out["project"].StringValue()
		out["email"] = resource.NewStringProperty(
			acct + "@" + proj + ".iam.gserviceaccount.com",
		)
	}
	return args.Name + "-id", out, nil
}
func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) { return args.Args, nil }

// liveArgs mirrors what oauth-user-inspector runs today: repository
// "oauth-user-inspector" and build SA "oauth-user-inspector-build" in
// prj-c-bu1-infra-pipeline-4b48.
func liveArgs() *Args {
	return &Args{
		App:                  "oauth-user-inspector",
		BuildProjectID:       pulumi.String("prj-c-bu1-infra-pipeline-4b48"),
		Region:               "us-west1",
		WorkloadIdentityPool: pulumi.String("projects/1064807322707/locations/global/workloadIdentityPools/foundation-pool"),
		GitHubEnvironment:    "oauth-user-inspector-build",
		KeepCount:            10,
	}
}

func run(t *testing.T, args *Args, check func(*testing.T, *Result)) {
	t.Helper()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		res, err := Deploy(ctx, args)
		if err != nil {
			return err
		}
		check(t, res)
		return nil
	}, pulumi.WithMocks("foundation-projects-bu1-shared", "production", mocks(0)))
	if err != nil {
		t.Fatalf("program failed: %v", err)
	}
}

// The repository id must match the LIVE repository. If it did not, adopting it
// would mean importing one repository and declaring a different one — the apply
// would create a second repo and the app's pushes would keep going to the old
// one, silently.
func TestRepositoryIDMatchesTheLiveRepository(t *testing.T) {
	var wg sync.WaitGroup
	wg.Add(1)
	run(t, liveArgs(), func(t *testing.T, res *Result) {
		res.RepositoryID.ApplyT(func(id string) error {
			defer wg.Done()
			if id != "oauth-user-inspector" {
				t.Errorf("repository id = %q, want %q (the live repo)", id, "oauth-user-inspector")
			}
			return nil
		})
	})
	wg.Wait()
}

// The build SA must match the live account, for the same adoption reason.
func TestBuildServiceAccountMatchesTheLiveAccount(t *testing.T) {
	var wg sync.WaitGroup
	wg.Add(1)
	run(t, liveArgs(), func(t *testing.T, res *Result) {
		res.BuildServiceAccountEmail.ApplyT(func(email string) error {
			defer wg.Done()
			want := "oauth-user-inspector-build@prj-c-bu1-infra-pipeline-4b48.iam.gserviceaccount.com"
			if email != want {
				t.Errorf("build SA = %q, want the live %q", email, want)
			}
			return nil
		})
	})
	wg.Wait()
}

// Overrides exist so a repo or account whose id does NOT follow the convention
// can still be adopted without renaming a live resource.
func TestOverridesAdoptNonConventionalNames(t *testing.T) {
	args := liveArgs()
	args.RepositoryID = "legacy-images"
	args.BuildAccountID = "legacy-builder"
	var wg sync.WaitGroup
	wg.Add(1)
	run(t, args, func(t *testing.T, res *Result) {
		res.RepositoryID.ApplyT(func(id string) error {
			defer wg.Done()
			if id != "legacy-images" {
				t.Errorf("override ignored: repository id = %q", id)
			}
			return nil
		})
	})
	wg.Wait()
}

func TestRequiredArgs(t *testing.T) {
	for _, tc := range []struct {
		name   string
		mutate func(*Args)
	}{
		{"no app", func(a *Args) { a.App = "" }},
		{"no region", func(a *Args) { a.Region = "" }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			args := liveArgs()
			tc.mutate(args)
			err := pulumi.RunErr(func(ctx *pulumi.Context) error {
				_, err := Deploy(ctx, args)
				return err
			}, pulumi.WithMocks("p", "s", mocks(0)))
			if err == nil {
				t.Fatal("expected an error for missing required arg")
			}
		})
	}
}
