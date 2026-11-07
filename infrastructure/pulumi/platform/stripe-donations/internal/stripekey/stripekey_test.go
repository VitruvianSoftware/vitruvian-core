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

package stripekey

import (
	"strings"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe-donations/internal/donations"
)

type mocks int

func (mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "_id", args.Inputs, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// resolve runs Resolve inside a mocked Pulumi program and reports the
// resolved value, whether it stayed secret, and the error the run returned.
func resolve(t *testing.T, mode donations.Mode, wait bool) (value string, secret bool, runErr error) {
	t.Helper()
	runErr = pulumi.RunErr(func(ctx *pulumi.Context) error {
		out := Resolve(config.New(ctx, "stripe-donations"), mode)
		// The check is wired to an export, as main.go wires it to the
		// provider: a failed Apply has to fail the run, not vanish.
		ctx.Export("key", out)
		secret = pulumi.IsSecret(out)
		if wait {
			// Block until the Apply has run; only safe when it succeeds.
			got := make(chan string, 1)
			out.ApplyT(func(v string) string { got <- v; return v })
			value = <-got
		}
		return nil
	}, pulumi.WithMocks("stripe-donations", "sandbox", mocks(0)))
	return value, secret, runErr
}

func TestResolvePrefersEnvAndStaysSecret(t *testing.T) {
	t.Setenv(EnvName, "sk_test_fromenv")
	got, secret, err := resolve(t, donations.ModeTest, true)
	if err != nil {
		t.Fatalf("run: %v", err)
	}
	if got != "sk_test_fromenv" {
		t.Fatalf("want the env key, got %q", got)
	}
	if !secret {
		t.Fatal("the resolved key must stay a secret Output")
	}
}

func TestResolveRefusesLiveKeyInTestMode(t *testing.T) {
	// Split so secret scanners do not read the fake as a real key.
	t.Setenv(EnvName, "sk_live_"+"neverused")
	_, _, err := resolve(t, donations.ModeTest, false)
	if err == nil {
		t.Fatal("a live key on a test-mode stack must fail the run")
	}
	if strings.Contains(err.Error(), "neverused") {
		t.Fatalf("error leaks the key: %v", err)
	}
}
