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

package oncall

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-pagerduty/sdk/v4/go/pagerduty"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Dependency says one service needs others to work: an incident on a
// supporting service then shows in PagerDuty as affecting the dependent one.
// Both are keys from the services list.
type Dependency struct {
	Service   string   `json:"service" yaml:"service"`
	DependsOn []string `json:"dependsOn" yaml:"dependsOn"`
}

// BusinessService is what people care about (say, "the homelab"), built on
// technical services. PagerDuty shows it as impacted when any of them has an
// incident. DependsOn lists service keys.
type BusinessService struct {
	Key         string   `json:"key" yaml:"key"`
	Name        string   `json:"name" yaml:"name"`
	Description string   `json:"description" yaml:"description"`
	DependsOn   []string `json:"dependsOn" yaml:"dependsOn"`
}

func validateDependencies(s Settings, add func(string, ...any)) {
	known := map[string]bool{}
	for _, svc := range s.Services {
		known[svc.Key] = true
	}
	edges := map[string]map[string]bool{}
	for i, d := range s.Dependencies {
		if !known[d.Service] {
			add("dependencies[%d].service %q is not a services key", i, d.Service)
		}
		if len(d.DependsOn) == 0 {
			add("dependencies[%d].dependsOn must name at least one service", i)
		}
		if edges[d.Service] == nil {
			edges[d.Service] = map[string]bool{}
		}
		for _, on := range d.DependsOn {
			switch {
			case !known[on]:
				add("dependencies[%d].dependsOn %q is not a services key", i, on)
			case on == d.Service:
				add("dependencies[%d]: %q cannot depend on itself", i, on)
			case edges[d.Service][on]:
				add("dependencies[%d]: %q already depends on %q", i, d.Service, on)
			}
			edges[d.Service][on] = true
		}
	}
	if cycle := findCycle(edges); cycle != "" {
		add("dependencies form a cycle: %s", cycle)
	}
	seen := map[string]bool{}
	for i, b := range s.BusinessServices {
		if !serviceKeyPattern.MatchString(b.Key) {
			add("businessServices[%d].key %q must match ^[a-z][a-z0-9-]*$", i, b.Key)
		}
		if seen[b.Key] || known[b.Key] {
			add("businessServices[%d].key %q is already used", i, b.Key)
		}
		seen[b.Key] = true
		if strings.TrimSpace(b.Name) == "" {
			add("businessServices[%d].name must be non-empty", i)
		}
		if len(b.DependsOn) == 0 {
			add("businessServices[%d].dependsOn must name at least one service", i)
		}
		dup := map[string]bool{}
		for _, on := range b.DependsOn {
			if !known[on] {
				add("businessServices[%d].dependsOn %q is not a services key", i, on)
			}
			if dup[on] {
				add("businessServices[%d].dependsOn repeats %q", i, on)
			}
			dup[on] = true
		}
	}
}

// findCycle returns "a -> b -> a" for the first cycle in edges, or "".
// PagerDuty rejects circular dependencies; catching them here fails the
// preview instead of the apply.
func findCycle(edges map[string]map[string]bool) string {
	const (
		unvisited = iota
		active
		done
	)
	state := map[string]int{}
	var path []string
	var visit func(string) string
	visit = func(n string) string {
		state[n] = active
		path = append(path, n)
		for _, m := range sortedKeys(edges[n]) {
			switch state[m] {
			case active:
				start := 0
				for i, p := range path {
					if p == m {
						start = i
					}
				}
				return strings.Join(append(append([]string{}, path[start:]...), m), " -> ")
			case unvisited:
				if c := visit(m); c != "" {
					return c
				}
			}
		}
		path = path[:len(path)-1]
		state[n] = done
		return ""
	}
	for _, n := range sortedKeys(edges) {
		if state[n] == unvisited {
			if c := visit(n); c != "" {
				return c
			}
		}
	}
	return ""
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	for i := 1; i < len(keys); i++ {
		for j := i; j > 0 && keys[j] < keys[j-1]; j-- {
			keys[j], keys[j-1] = keys[j-1], keys[j]
		}
	}
	return keys
}

// serviceRef is what a dependency points at: an id and PagerDuty's type for it.
type serviceRef struct {
	id  pulumi.StringInput
	typ pulumi.StringInput
}

// reconcileDependencies creates the business services and one
// ServiceDependency per (dependent, supporting) pair, so adding or removing
// one pair never touches the others.
func reconcileDependencies(ctx *pulumi.Context, providerOpt pulumi.ResourceOption, s Settings, services map[string]*pagerduty.Service) error {
	ref := func(key string) serviceRef {
		svc := services[key]
		return serviceRef{id: svc.ID().ToStringOutput(), typ: svc.Type}
	}
	link := func(name string, dependent, supporting serviceRef) error {
		_, err := pagerduty.NewServiceDependency(ctx, name, &pagerduty.ServiceDependencyArgs{
			Dependency: &pagerduty.ServiceDependencyDependencyArgs{
				DependentServices: pagerduty.ServiceDependencyDependencyDependentServiceArray{
					&pagerduty.ServiceDependencyDependencyDependentServiceArgs{Id: dependent.id, Type: dependent.typ},
				},
				SupportingServices: pagerduty.ServiceDependencyDependencySupportingServiceArray{
					&pagerduty.ServiceDependencyDependencySupportingServiceArgs{Id: supporting.id, Type: supporting.typ},
				},
			},
		}, providerOpt)
		if err != nil {
			return fmt.Errorf("create dependency %s: %w", name, err)
		}
		return nil
	}
	for _, d := range s.Dependencies {
		for _, on := range d.DependsOn {
			if err := link("dep-"+d.Service+"-on-"+on, ref(d.Service), ref(on)); err != nil {
				return err
			}
		}
	}
	for _, b := range s.BusinessServices {
		bs, err := pagerduty.NewBusinessService(ctx, "business-"+b.Key, &pagerduty.BusinessServiceArgs{
			Name:        pulumi.String(b.Name),
			Description: pulumi.String(b.Description),
		}, providerOpt)
		if err != nil {
			return fmt.Errorf("create business service %q: %w", b.Key, err)
		}
		ctx.Export(b.Key+"BusinessServiceId", bs.ID())
		self := serviceRef{id: bs.ID().ToStringOutput(), typ: bs.Type}
		for _, on := range b.DependsOn {
			if err := link("dep-business-"+b.Key+"-on-"+on, self, ref(on)); err != nil {
				return err
			}
		}
	}
	return nil
}
