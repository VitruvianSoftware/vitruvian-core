/*
Copyright (c) 2026 VitruvianSoftware

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

package neon

import (
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type mocks struct {
	mu     *sync.Mutex
	inputs *map[string]resource.PropertyMap
}

func (m mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	(*m.inputs)[args.Name] = args.Inputs
	m.mu.Unlock()
	out := args.Inputs.Copy()
	// The two URIs the real provider computes; distinct so the pooled/direct
	// selection below is actually observable.
	out["connectionUri"] = resource.NewStringProperty("postgres://app:pw@direct.neon.tech/main")
	out["connectionUriPooler"] = resource.NewStringProperty("postgres://app:pw@pooler.neon.tech/main")
	return args.Name + "_id", out, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func run(t *testing.T, args *ProjectArgs) (map[string]resource.PropertyMap, *Project) {
	t.Helper()
	var (
		mu     sync.Mutex
		inputs = map[string]resource.PropertyMap{}
		got    *Project
	)
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		p, err := NewProject(ctx, "db", args)
		got = p
		return err
	}, pulumi.WithMocks("proj", "stack", mocks{mu: &mu, inputs: &inputs}))
	if err != nil {
		t.Fatalf("program failed: %v", err)
	}
	return inputs, got
}

func resolve(t *testing.T, o pulumi.StringOutput) string {
	t.Helper()
	var (
		wg sync.WaitGroup
		v  string
	)
	wg.Add(1)
	o.ApplyT(func(s string) string { v = s; wg.Done(); return s })
	wg.Wait()
	return v
}

func TestNewProject(t *testing.T) {
	base := &ProjectArgs{Name: "tabula-dev", RegionID: "aws-us-east-1", OrgID: "org-x"}

	t.Run("passes name, region and org through", func(t *testing.T) {
		in, _ := run(t, base)
		got := in["db"]
		if got["name"].StringValue() != "tabula-dev" {
			t.Errorf("name = %q", got["name"].StringValue())
		}
		if got["regionId"].StringValue() != "aws-us-east-1" {
			t.Errorf("regionId = %q", got["regionId"].StringValue())
		}
		// A project created OUTSIDE an org is owned by an individual — the exact
		// dependency this repo's migration existed to remove.
		if got["orgId"].StringValue() != "org-x" {
			t.Errorf("orgId = %q", got["orgId"].StringValue())
		}
	})

	// Letting the provider choose means two envs created months apart silently
	// run different Postgres majors.
	t.Run("pins the Postgres major", func(t *testing.T) {
		in, _ := run(t, base)
		if got := in["db"]["pgVersion"].NumberValue(); got != float64(DefaultPgVersion) {
			t.Errorf("pgVersion = %v, want %d", got, DefaultPgVersion)
		}
		v := 16
		in2, _ := run(t, &ProjectArgs{Name: "n", RegionID: "r", PgVersion: &v})
		if got := in2["db"]["pgVersion"].NumberValue(); got != 16 {
			t.Errorf("explicit pgVersion = %v, want 16", got)
		}
	})

	t.Run("defaults the database and role names", func(t *testing.T) {
		in, _ := run(t, base)
		br := in["db"]["branch"].ObjectValue()
		if br["databaseName"].StringValue() != "main" {
			t.Errorf("databaseName = %q, want main", br["databaseName"].StringValue())
		}
		if br["roleName"].StringValue() != "app" {
			t.Errorf("roleName = %q, want app", br["roleName"].StringValue())
		}
	})

	// The important default. Serverless scales to many short-lived instances,
	// each opening connections; Postgres has a hard max_connections, so a direct
	// endpoint runs out under exactly the traffic scaling is meant to absorb.
	t.Run("returns the POOLED connection string by default", func(t *testing.T) {
		_, p := run(t, base)
		if got := resolve(t, p.ConnectionString); got != "postgres://app:pw@pooler.neon.tech/main" {
			t.Errorf("ConnectionString = %q, want the pooled URI", got)
		}
	})

	t.Run("can opt out of pooling for session-level features", func(t *testing.T) {
		no := false
		_, p := run(t, &ProjectArgs{Name: "n", RegionID: "r", Pooled: &no})
		if got := resolve(t, p.ConnectionString); got != "postgres://app:pw@direct.neon.tech/main" {
			t.Errorf("ConnectionString = %q, want the direct URI", got)
		}
	})

	// It embeds credentials; unsecreted it lands in plan diffs and CI logs.
	t.Run("marks the connection string secret", func(t *testing.T) {
		_, p := run(t, base)
		if !pulumi.IsSecret(p.ConnectionString) {
			t.Error("ConnectionString must be a secret output — it embeds credentials")
		}
	})

	t.Run("requires a name and a region", func(t *testing.T) {
		for _, tc := range []struct {
			why  string
			args *ProjectArgs
		}{
			{"no name", &ProjectArgs{RegionID: "r"}},
			{"no region", &ProjectArgs{Name: "n"}},
			{"nil args", nil},
		} {
			err := pulumi.RunErr(func(ctx *pulumi.Context) error {
				_, err := NewProject(ctx, "db", tc.args)
				return err
			}, pulumi.WithMocks("p", "s", mocks{mu: &sync.Mutex{}, inputs: &map[string]resource.PropertyMap{}}))
			if err == nil {
				t.Errorf("%s: expected an error", tc.why)
			}
		}
	})
}
