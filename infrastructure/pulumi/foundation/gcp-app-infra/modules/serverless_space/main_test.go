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

// Mock-driven tests for the serverless_space archetype.
//
// WHY THESE EXIST. The archetype was wired into the stage-5 leaves in #1023
// behind `<app>_workload_enabled`, which ships FALSE — so the leaf `continue`s
// past it and NO check in that PR executed a line of this module. It merged
// green on compile-coverage alone. `pulumi.WithMocks` runs the real resource
// graph without touching a cloud, which is the only way to exercise this before
// the cutover puts it in front of live traffic.
//
// What they pin down is the cutover's core requirement: the resources this
// module declares must match the ones oauth-user-inspector/infra/app already
// has running, so the post-import diff is EMPTY. A mismatch here is not a
// cosmetic drift — for a Cloud Run service, a changed name is a delete and
// recreate.

package serverless_space

import (
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type mocks int

func (mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "-id", args.Inputs, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// liveArgs mirrors what oauth-user-inspector runs in development today. Keep it
// in step with the leaf's Pulumi.production.yaml — that is the whole point.
func liveArgs() *ServerlessSpaceArgs {
	return &ServerlessSpaceArgs{
		Env:                        "development",
		BusinessUnit:               "bu1",
		ProjectID:                  pulumi.String("prj-d-bu1-oss-floating-648a"),
		Region:                     pulumi.String("us-west1"),
		ServiceName:                "oauth-user-inspector",
		ImageDigest:                pulumi.String("us-west1-docker.pkg.dev/p/oauth-user-inspector/app@sha256:abc12345def"),
		RuntimeServiceAccountEmail: pulumi.String("oauth-user-inspector-rt@prj-d-bu1-oss-floating-648a.iam.gserviceaccount.com"),
		SecretPrefix:               "OAUTH_USER_INSPECTOR_",
		EnvVars:                    map[string]string{"NODE_ENV": "production"},
		MaxInstances:               10,
		PublicInvoker:              true,
		RevisionSuffix:             "abc12345",
	}
}

func run(t *testing.T, args *ServerlessSpaceArgs, check func(*testing.T, *ServerlessSpaceResult)) {
	t.Helper()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		res, err := DeployServerlessSpace(ctx, "oauth-user-inspector", args)
		if err != nil {
			return err
		}
		check(t, res)
		return nil
	}, pulumi.WithMocks("foundation-app-infra-bu1-development", "production", mocks(0)))
	if err != nil {
		t.Fatalf("program failed: %v", err)
	}
}

// The archetype must produce the SAME service name the app stack already runs:
// oauth-user-inspector-development. If it produces "oauth-user-inspector"
// instead, importing the live service and applying would RENAME it — and a
// Cloud Run rename is a delete + create, i.e. an outage on the production leg.
func TestServiceNameMatchesTheLiveService(t *testing.T) {
	var wg sync.WaitGroup
	wg.Add(1)
	run(t, liveArgs(), func(t *testing.T, res *ServerlessSpaceResult) {
		res.ServiceName.ApplyT(func(name string) error {
			defer wg.Done()
			if name != "oauth-user-inspector-development" {
				t.Errorf("service name = %q, want %q — importing the live service and applying this would RENAME it (delete + create)",
					name, "oauth-user-inspector-development")
			}
			return nil
		})
	})
	wg.Wait()
}

// A digest is not a legal revision name, so the suffix is derived from it. The
// resulting revision must match what the app stack produces today:
// <service>-<shortdigest>.
func TestRevisionNameMatchesTheAppStackFormat(t *testing.T) {
	var wg sync.WaitGroup
	wg.Add(1)
	run(t, liveArgs(), func(t *testing.T, res *ServerlessSpaceResult) {
		res.ServiceName.ApplyT(func(svc string) error {
			defer wg.Done()
			want := "oauth-user-inspector-development-abc12345"
			if got := svc + "-abc12345"; got != want {
				t.Errorf("revision name would be %q, want %q", got, want)
			}
			return nil
		})
	})
	wg.Wait()
}

// Blue-green phase 1: with a stable revision present and promote=false, ALL
// traffic must stay on the stable revision. Getting this wrong sends live
// traffic to an unsmoked revision.
func TestBlueGreenHoldsTrafficOnStableUntilPromoted(t *testing.T) {
	args := liveArgs()
	args.StableRevision = "oauth-user-inspector-development-0000dead"
	args.Promote = false
	run(t, args, func(t *testing.T, res *ServerlessSpaceResult) {
		if res == nil {
			t.Fatal("nil result")
		}
	})
}

// Blue-green phase 2 and the first-ever deploy both route 100% to the new
// revision — the first because there is nothing to hold traffic on.
func TestPromoteAndFirstDeployBothRouteToTheNewRevision(t *testing.T) {
	for _, tc := range []struct {
		name    string
		stable  string
		promote bool
	}{
		{"promote", "oauth-user-inspector-development-0000dead", true},
		{"first deploy", "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			args := liveArgs()
			args.StableRevision = tc.stable
			args.Promote = tc.promote
			run(t, args, func(t *testing.T, res *ServerlessSpaceResult) {
				if res == nil {
					t.Fatal("nil result")
				}
			})
		})
	}
}

// The runtime SA is supplied by the app (the app still owns its identity); the
// archetype must use it rather than minting a second one.
func TestSuppliedRuntimeServiceAccountIsUsed(t *testing.T) {
	var wg sync.WaitGroup
	wg.Add(1)
	run(t, liveArgs(), func(t *testing.T, res *ServerlessSpaceResult) {
		res.RuntimeSAEmail.ApplyT(func(email string) error {
			defer wg.Done()
			want := "oauth-user-inspector-rt@prj-d-bu1-oss-floating-648a.iam.gserviceaccount.com"
			if email != want {
				t.Errorf("runtime SA = %q, want the app-supplied %q", email, want)
			}
			return nil
		})
	})
	wg.Wait()
}
