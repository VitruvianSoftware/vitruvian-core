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

package pdtoken

import (
	"strings"
	"sync/atomic"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type spyMocks struct {
	newResourceCalls atomic.Int32
}

func (m *spyMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.newResourceCalls.Add(1)
	return args.Name + "_id", args.Inputs, nil
}

func (m *spyMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func runResolve(t *testing.T, stackCfg map[string]string) (value string, secret bool, registered int32, runErr error) {
	t.Helper()
	m := &spyMocks{}
	runErr = pulumi.RunErr(func(ctx *pulumi.Context) error {
		out, err := Resolve(ctx)
		if err != nil {
			return err
		}
		ctx.Export("token", out)
		secret = pulumi.IsSecret(out)
		got := make(chan string, 1)
		out.ApplyT(func(v string) string {
			got <- v
			return v
		})
		value = <-got
		return nil
	}, pulumi.WithMocks("vitruvian-pagerduty", "production", m), func(info *pulumi.RunInfo) {
		info.Config = stackCfg
	})
	return value, secret, m.newResourceCalls.Load(), runErr
}

func TestResolvePrefersEnvAndStaysSecret(t *testing.T) {
	t.Setenv(EnvName, "env-test-token")
	got, secret, _, err := runResolve(t, map[string]string{
		ProviderNamespace + ":" + ConfigKey: "cfg-test-token",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "env-test-token" {
		t.Fatalf("want env token, got %q", got)
	}
	if !secret {
		t.Fatal("expected resolved token output to be a Pulumi secret")
	}
}

func TestResolveUsesStackConfigWhenEnvUnset(t *testing.T) {
	t.Setenv(EnvName, "")
	got, secret, _, err := runResolve(t, map[string]string{
		ProviderNamespace + ":" + ConfigKey: "cfg-test-token",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "cfg-test-token" {
		t.Fatalf("want stack config token, got %q", got)
	}
	if !secret {
		t.Fatal("expected resolved token output to be a Pulumi secret")
	}
}

func TestResolveFailsBeforeAnyResourceWhenUnset(t *testing.T) {
	t.Setenv(EnvName, "   ")
	_, _, registered, err := runResolve(t, nil)
	if err == nil {
		t.Fatal("expected an error when neither env nor stack secret is set")
	}
	if !strings.Contains(err.Error(), EnvName) || !strings.Contains(err.Error(), "pagerduty:token") {
		t.Fatalf("expected clear error mentioning %s and pagerduty:token, got %v", EnvName, err)
	}
	if registered != 0 {
		t.Fatalf("expected zero resources registered before error, got %d", registered)
	}
}
