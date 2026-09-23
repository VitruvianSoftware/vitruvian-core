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
	"os"
	"strings"
	"testing"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/dev-local/pkg/utils"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type mapConfig map[string]string

func (m mapConfig) Lookup(key string) (string, bool) {
	v, ok := m[key]
	return v, ok
}

func TestRequireStackConfig(t *testing.T) {
	tests := []struct {
		name    string
		conf    mapConfig
		wantErr string
	}{
		{name: "missing config file (the 2026-09-23 incident)", conf: mapConfig{}, wantErr: "is not set"},
		{name: "argocd explicitly enabled", conf: mapConfig{"argocd_enabled": "true"}},
		{name: "argocd explicitly disabled is still allowed", conf: mapConfig{"argocd_enabled": "false"}},
		{name: "typo is rejected, not read as false", conf: mapConfig{"argocd_enabled": "ture"}, wantErr: "must be true or false"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := requireStackConfig(tt.conf)
			if tt.wantErr == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
				t.Fatalf("error = %v, want it to contain %q", err, tt.wantErr)
			}
		})
	}
}

type noopMocks struct{}

func (noopMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "_id", args.Inputs, nil
}

func (noopMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// TestLookupReadsRealStackConfig exercises utils.PulumiConfig.Lookup against
// the engine's real config plumbing, so the guard is proven to see an absent
// key as absent rather than as an empty string.
func TestLookupReadsRealStackConfig(t *testing.T) {
	run := func(configJSON string) error {
		t.Setenv("PULUMI_CONFIG", configJSON)
		return pulumi.RunErr(func(ctx *pulumi.Context) error {
			return requireStackConfig(utils.NewConfig(ctx))
		}, pulumi.WithMocks("monorepo", "local", noopMocks{}))
	}
	if err := run(`{}`); err == nil || !strings.Contains(err.Error(), "is not set") {
		t.Fatalf("empty stack config: got %v, want the not-set error", err)
	}
	if err := run(`{"monorepo:argocd_enabled":"true"}`); err != nil {
		t.Fatalf("argocd_enabled=true: unexpected error %v", err)
	}
	_ = os.Unsetenv("PULUMI_CONFIG")
}
