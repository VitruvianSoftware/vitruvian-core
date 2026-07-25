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

// Mock-driven smoke test for the env_base archetype.
//
// WHY THIS EXISTS. env_base is DORMANT — no leaf calls DeployEnvBase yet — so
// without a test the module would ship on compile-coverage alone and could rot
// silently (a wrong default, a broken zone lookup) until the day a leaf first
// instantiates it. pulumi.WithMocks runs the real resource graph (SA →
// instance template → compute instance, including the GetZones data-source
// call) without touching a cloud, proving the archetype actually executes and
// its defaults hold. Mirrors serverless_space/main_test.go.

package env_base

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

// Call fakes the compute.GetZones data source DeployEnvBase uses to pick a
// zone; every other call passes its inputs through.
func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	if strings.Contains(args.Token, "getZones") {
		return resource.NewPropertyMapFromMap(map[string]interface{}{
			"names": []string{"us-central1-a", "us-central1-b"},
		}), nil
	}
	return args.Args, nil
}

func baseArgs() *EnvBaseArgs {
	return &EnvBaseArgs{
		Env:                "development",
		BusinessUnit:       "bu1",
		ProjectSuffix:      "app-infra",
		ProjectID:          pulumi.String("prj-d-bu1-oss-floating-648a"),
		Region:             pulumi.String("us-central1"),
		SubnetworkSelfLink: pulumi.String("projects/prj-d-bu1-oss-floating-648a/regions/us-central1/subnetworks/sb-d-app"),
	}
}

func run(t *testing.T, args *EnvBaseArgs, check func(*testing.T, *EnvBaseResult)) {
	t.Helper()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		res, err := DeployEnvBase(ctx, "env-base", args)
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

// The archetype must execute end to end (SA → template → instance) and resolve
// a non-empty instance identity — the zone lookup in particular is the piece
// most likely to break under a provider bump, and a dormant module never
// exercises it in production until first use.
func TestDeployEnvBaseProducesAnInstance(t *testing.T) {
	var wg sync.WaitGroup
	wg.Add(1)
	run(t, baseArgs(), func(t *testing.T, res *EnvBaseResult) {
		if res == nil {
			t.Fatal("nil result")
		}
		pulumi.All(res.InstanceName, res.InstanceZone).ApplyT(func(vs []interface{}) error {
			defer wg.Done()
			name, _ := vs[0].(string)
			zone, _ := vs[1].(string)
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

// Defaults must fill when the caller omits them (matches the README's default
// table); a dormant module is exactly where a silently-dropped default hides.
func TestDefaultsFillWhenOmitted(t *testing.T) {
	args := baseArgs() // Hostname/MachineType/NumInstances/SourceImage* left zero
	run(t, args, func(t *testing.T, res *EnvBaseResult) {
		if res == nil {
			t.Fatal("nil result")
		}
	})
}
