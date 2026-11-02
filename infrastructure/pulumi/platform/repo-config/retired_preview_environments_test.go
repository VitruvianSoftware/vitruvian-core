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
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

type importRecord struct {
	typ, name, id string
	inputs        resource.PropertyMap
}

// importMocks wraps envMocks and also keeps each resource's import id, which
// envMocks drops.
type importMocks struct {
	envMocks
	mu  sync.Mutex
	got []importRecord
}

func (m *importMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	m.got = append(m.got, importRecord{args.TypeToken, args.Name, args.ID, args.Inputs})
	m.mu.Unlock()
	return m.envMocks.NewResource(args)
}

// The retired preview Environments are adopted exactly as they are live: an
// import of the existing Environment, with only the repository and name set
// (every other setting at its default, which is what GitHub shows), and
// nothing else attached to them. Anything more would turn the import into a
// change, or put an identity behind an Environment that is about to go.
func TestRetiredFoundationPreviewEnvironmentsAreAdoptedUnchanged(t *testing.T) {
	t.Setenv("PULUMI_CONFIG", stackConfigEnv(t))
	m := &importMocks{envMocks: envMocks{resources: map[string][]resource.PropertyMap{}}}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "")
		repo, err := github.NewRepository(ctx, "vitruvian-core", &github.RepositoryArgs{
			Name: pulumi.String("vitruvian-core"),
		})
		if err != nil {
			return err
		}
		return foundationEnvironments(ctx, cfg, repo)
	}, pulumi.WithMocks("vitruvian-core-repo-config", "dev", m))
	if err != nil {
		t.Fatalf("foundationEnvironments: %v", err)
	}

	want := map[string]bool{
		"foundation-environments-preview": true,
		"foundation-networks-preview":     true,
	}
	var adopted []string
	for _, r := range m.got {
		env := ""
		if v, ok := r.inputs["environment"]; ok && v.IsString() {
			env = v.StringValue()
		}
		if !want[env] && !want[r.name] {
			continue
		}
		if r.typ != "github:index/repositoryEnvironment:RepositoryEnvironment" {
			t.Errorf("%s (%s) is attached to retired Environment %s", r.name, r.typ, env)
			continue
		}
		if r.id != "vitruvian-core:"+env {
			t.Errorf("%s: import id = %q, want %q (an Environment created rather than imported would be new)", r.name, r.id, "vitruvian-core:"+env)
		}
		var keys []string
		for k := range r.inputs {
			keys = append(keys, string(k))
		}
		sort.Strings(keys)
		if got := strings.Join(keys, ","); got != "environment,repository" {
			t.Errorf("%s: inputs = [%s], want only [environment,repository]", r.name, got)
		}
		adopted = append(adopted, env)
	}
	sort.Strings(adopted)
	if got := strings.Join(adopted, ","); got != "foundation-environments-preview,foundation-networks-preview" {
		t.Errorf("adopted = [%s], want each retired Environment exactly once", got)
	}
}
