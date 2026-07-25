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

// Mock-driven smoke test for the confidential_space archetype.
//
// WHY THIS EXISTS. confidential_space is DORMANT — no leaf calls
// DeployConfidentialSpace yet — so without a test it would ship on
// compile-coverage alone and could rot silently until first use. This module
// is the most intricate archetype in the catalog (Workload Identity Pool +
// OIDC attestation provider with an SA-templated attribute condition, a
// propagation Sleep, the workloadIdentityUser IAM binding, and a Confidential
// VM whose zone comes from a GetZones data source), so an executes-end-to-end
// check earns its keep. pulumi.WithMocks runs the real resource graph without
// touching a cloud. Mirrors env_base/serverless_space main_test.go.

package confidential_space

import (
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type mocks int

func (mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "-id", args.Inputs, nil
}

// Call fakes the compute.GetZones data source used to place the VM; every other
// call passes its inputs through.
func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	if strings.Contains(args.Token, "getZones") {
		return resource.NewPropertyMapFromMap(map[string]interface{}{
			"names": []string{"us-central1-a", "us-central1-b"},
		}), nil
	}
	return args.Args, nil
}

func confArgs() *ConfidentialSpaceArgs {
	return &ConfidentialSpaceArgs{
		Env:                      "development",
		BusinessUnit:             "bu1",
		ProjectID:                pulumi.String("prj-d-bu1-oss-floating-648a"),
		ProjectNumber:            pulumi.String("123456789012"),
		Region:                   pulumi.String("us-central1"),
		SubnetworkSelfLink:       pulumi.String("projects/prj-d-bu1-oss-floating-648a/regions/us-central1/subnetworks/sb-d-app"),
		WorkloadSAEmail:          pulumi.String("workload@prj-d-bu1-oss-floating-648a.iam.gserviceaccount.com"),
		ConfidentialImageDigest:  "sha256:abc123def456",
		ConfidentialMachineType:  "n2d-standard-2",
		ConfidentialInstanceType: "SEV",
		CpuPlatform:              "AMD Milan",
		CloudBuildProjectID:      pulumi.String("prj-c-bu1-infra-pipeline-0000"),
	}
}

func run(t *testing.T, args *ConfidentialSpaceArgs, check func(*testing.T, *ConfidentialSpaceResult)) {
	t.Helper()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		res, err := DeployConfidentialSpace(ctx, "conf-space", args)
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

// The archetype must execute end to end (pool → provider → sleep → IAM →
// confidential VM) and resolve a non-empty pool id and instance identity. The
// GetZones-driven zone in particular is the piece most likely to break under a
// provider bump, and a dormant module never exercises it in production.
func TestDeployConfidentialSpaceProducesPoolAndInstance(t *testing.T) {
	var wg sync.WaitGroup
	wg.Add(1)
	run(t, confArgs(), func(t *testing.T, res *ConfidentialSpaceResult) {
		if res == nil {
			t.Fatal("nil result")
		}
		pulumi.All(res.WorkloadPoolID, res.InstanceName, res.InstanceZone).ApplyT(func(vs []interface{}) error {
			defer wg.Done()
			pool, _ := vs[0].(string)
			name, _ := vs[1].(string)
			zone, _ := vs[2].(string)
			if pool == "" {
				t.Error("workload pool id resolved empty")
			}
			if name == "" {
				t.Error("instance name resolved empty")
			}
			if zone == "" {
				t.Error("instance zone resolved empty — GetZones fake not wired?")
			}
			return nil
		})
	})
	wg.Wait()
}
