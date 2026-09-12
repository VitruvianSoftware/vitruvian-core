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

package upstash

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
	// Echo the inputs back and add the outputs the real provider computes, so
	// the connection-string assembly below is exercised against realistic shapes.
	out := args.Inputs.Copy()
	out["endpoint"] = resource.NewStringProperty("fake-123.upstash.io")
	out["password"] = resource.NewStringProperty("s3cret-pw")
	out["port"] = resource.NewNumberProperty(6379)
	return args.Name + "_id", out, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func run(t *testing.T, args *RedisArgs) (map[string]resource.PropertyMap, *Redis) {
	t.Helper()
	var (
		mu     sync.Mutex
		inputs = map[string]resource.PropertyMap{}
		got    *Redis
	)
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		r, err := NewRedis(ctx, "cache", args)
		got = r
		return err
	}, pulumi.WithMocks("proj", "stack", mocks{mu: &mu, inputs: &inputs}))
	if err != nil {
		t.Fatalf("program failed: %v", err)
	}
	return inputs, got
}

func TestNewRedis(t *testing.T) {
	t.Run("passes the database name through", func(t *testing.T) {
		inputs, _ := run(t, &RedisArgs{Name: "tabula-shared", Region: "us-east-1"})
		in, ok := inputs["cache"]
		if !ok {
			t.Fatalf("no resource registered; got %v", inputs)
		}
		if got := in["databaseName"].StringValue(); got != "tabula-shared" {
			t.Errorf("databaseName = %q, want tabula-shared", got)
		}
		// Region deliberately does NOT pass through as `region` — see the
		// global-tier case below.
	})

	// TLS is on by default at Upstash and cannot be turned off for new databases,
	// but making it explicit means a future provider default-flip cannot silently
	// downgrade an existing caller to plaintext.
	t.Run("enables TLS explicitly rather than relying on the provider default", func(t *testing.T) {
		inputs, _ := run(t, &RedisArgs{Name: "c", Region: "us-east-1"})
		if !inputs["cache"]["tls"].BoolValue() {
			t.Error("tls not explicitly enabled")
		}
	})

	// A cache that fills up and starts REJECTING writes takes the app down; one
	// that evicts degrades instead. Eviction is the safe default for a cache and
	// the wrong default for a datastore, so it is opt-out, not opt-in.
	t.Run("enables eviction by default", func(t *testing.T) {
		inputs, _ := run(t, &RedisArgs{Name: "c", Region: "us-east-1"})
		if !inputs["cache"]["eviction"].BoolValue() {
			t.Error("eviction should default to true for a cache")
		}
	})

	t.Run("eviction can be disabled for datastore use", func(t *testing.T) {
		no := false
		inputs, _ := run(t, &RedisArgs{Name: "c", Region: "us-east-1", Eviction: &no})
		if inputs["cache"]["eviction"].BoolValue() {
			t.Error("eviction should be disabled when explicitly set false")
		}
	})

	// Upstash now REJECTS regional databases outright:
	//   400 "regional db creation is deprecated"
	// so the module defaults to the global tier, which requires a PrimaryRegion.
	t.Run("defaults to the global tier with the given region as primary", func(t *testing.T) {
		inputs, _ := run(t, &RedisArgs{Name: "c", Region: "us-east-1"})
		if got := inputs["cache"]["region"].StringValue(); got != "global" {
			t.Errorf("region = %q, want global (regional creation is deprecated)", got)
		}
		if got := inputs["cache"]["primaryRegion"].StringValue(); got != "us-east-1" {
			t.Errorf("primaryRegion = %q, want us-east-1", got)
		}
	})

	t.Run("read regions are passed through", func(t *testing.T) {
		inputs, _ := run(t, &RedisArgs{Name: "c", Region: "us-east-1", ReadRegions: []string{"eu-west-1"}})
		rr := inputs["cache"]["readRegions"].ArrayValue()
		if len(rr) != 1 || rr[0].StringValue() != "eu-west-1" {
			t.Errorf("readRegions = %v", rr)
		}
	})

	t.Run("requires a name and a region", func(t *testing.T) {
		for _, tc := range []struct {
			why  string
			args *RedisArgs
		}{
			{"no name", &RedisArgs{Region: "us-east-1"}},
			{"no region", &RedisArgs{Name: "c"}},
		} {
			err := pulumi.RunErr(func(ctx *pulumi.Context) error {
				_, err := NewRedis(ctx, "cache", tc.args)
				return err
			}, pulumi.WithMocks("p", "s", mocks{mu: &sync.Mutex{}, inputs: &map[string]resource.PropertyMap{}}))
			if err == nil {
				t.Errorf("%s: expected an error", tc.why)
			}
		}
	})

	// The connection URL is the whole point of the component: callers should not
	// have to know how to assemble rediss://default:<pw>@<host>:<port> correctly.
	// It carries the password, so it MUST be a secret output — otherwise it lands
	// in plan diffs and CI logs in plaintext.
	t.Run("exposes a secret connection URL", func(t *testing.T) {
		_, r := run(t, &RedisArgs{Name: "c", Region: "us-east-1"})
		if r == nil {
			t.Fatal("nil Redis")
		}
		var (
			wg     sync.WaitGroup
			url    string
			secret bool
		)
		wg.Add(1)
		r.ConnectionURL.ApplyT(func(v string) string {
			url = v
			wg.Done()
			return v
		})
		wg.Wait()
		if url != "rediss://default:s3cret-pw@fake-123.upstash.io:6379" {
			t.Errorf("ConnectionURL = %q", url)
		}
		wg.Add(1)
		pulumi.All(r.ConnectionURL).ApplyT(func(_ []interface{}) error { return nil })
		secret = pulumi.IsSecret(r.ConnectionURL)
		wg.Done()
		wg.Wait()
		if !secret {
			t.Error("ConnectionURL must be a secret output — it embeds the password")
		}
	})
}
