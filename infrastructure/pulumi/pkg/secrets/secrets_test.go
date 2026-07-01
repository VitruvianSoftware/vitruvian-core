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

package secrets

import (
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// mocks is a no-op pulumi.MockResourceMonitor; the helpers under test create no
// resources, so the callbacks just echo their inputs.
type mocks int

func (mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "_id", args.Inputs, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// runWithMocks executes fn inside a mocked Pulumi runtime so the helpers can
// build a real *config.Config.
func runWithMocks(t *testing.T, fn func(ctx *pulumi.Context, cfg *config.Config)) {
	t.Helper()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		fn(ctx, config.New(ctx, ""))
		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	if err != nil {
		t.Fatalf("pulumi run: %v", err)
	}
}

// awaitString resolves a fully-known StringInput to its concrete value. The
// wg.Wait()-inside-the-run pattern is Pulumi's documented approach for testing
// outputs; our inputs are known values, so the callback runs promptly.
func awaitString(in pulumi.StringInput) string {
	var got string
	var wg sync.WaitGroup
	wg.Add(1)
	in.ToStringOutput().ApplyT(func(v string) string {
		got = v
		wg.Done()
		return v
	})
	wg.Wait()
	return got
}

func TestEnvOrConfig_PrefersEnv(t *testing.T) {
	t.Setenv("MY_SECRET", "from-env")
	runWithMocks(t, func(_ *pulumi.Context, cfg *config.Config) {
		if got := awaitString(EnvOrConfig(cfg, "MY_SECRET", "mySecret")); got != "from-env" {
			t.Fatalf("EnvOrConfig: want %q, got %q", "from-env", got)
		}
	})
}

func TestEnvOrConfigOptional_PrefersEnv(t *testing.T) {
	t.Setenv("MY_SECRET", "from-env")
	runWithMocks(t, func(_ *pulumi.Context, cfg *config.Config) {
		in := EnvOrConfigOptional(cfg, "MY_SECRET", "mySecret")
		if in == nil {
			t.Fatal("EnvOrConfigOptional: want non-nil when env is set, got nil")
		}
		if got := awaitString(in); got != "from-env" {
			t.Fatalf("EnvOrConfigOptional: want %q, got %q", "from-env", got)
		}
	})
}

func TestEnvOrConfigOptional_NilWhenAbsent(t *testing.T) {
	// Neither the env var nor the (empty mock) config has the key: the optional
	// variant must return nil so callers skip managing the resource. This is the
	// behavior repo_config.dependabotSecrets relies on to stay green until the
	// BuildBuddy key is wired.
	runWithMocks(t, func(_ *pulumi.Context, cfg *config.Config) {
		if in := EnvOrConfigOptional(cfg, "DEFINITELY_UNSET_SECRET", "definitelyUnset"); in != nil {
			t.Fatal("EnvOrConfigOptional: want nil when neither env nor config is set")
		}
	})
}
