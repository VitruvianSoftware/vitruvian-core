/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Package testutil provides shared Pulumi mock infrastructure for unit tests.
//
// The ResourceTracker captures every resource registered during a
// pulumi.WithMocks test run and exposes query helpers to assert on resource
// counts, inputs, and type tokens.
package testutil

import (
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TrackedResource represents a single resource registered during a test.
type TrackedResource struct {
	TypeToken string
	Name      string
	Inputs    resource.PropertyMap
}

// ResourceTracker implements pulumi.Mock and records every resource registration.
type ResourceTracker struct {
	mu        sync.Mutex
	resources []TrackedResource

	// OutputOverrides maps type tokens to custom output property maps. When
	// NewResource encounters a matching type, it merges these outputs into
	// the response. This is useful for simulating provider-computed outputs
	// (e.g. projectId, number) that downstream references depend on.
	OutputOverrides map[string]resource.PropertyMap
}

// NewTracker creates a ResourceTracker with sensible defaults for the GCP
// provider. Pre-populates OutputOverrides for common GCP resource types whose
// computed outputs are referenced by component logic.
func NewTracker() *ResourceTracker {
	return &ResourceTracker{
		OutputOverrides: map[string]resource.PropertyMap{
			"gcp:organizations/project:Project": resource.NewPropertyMapFromMap(map[string]interface{}{
				"projectId": "mock-project-id",
				"number":    "123456789",
			}),
			"random:index/randomId:RandomId": resource.NewPropertyMapFromMap(map[string]interface{}{
				"hex": "a1b2",
			}),
			"gcp:cloudrunv2/service:Service": resource.NewPropertyMapFromMap(map[string]interface{}{
				"uri": "https://mock-service-abc123-uc.a.run.app",
			}),
			"gcp:bigquery/dataset:Dataset": resource.NewPropertyMapFromMap(map[string]interface{}{
				"selfLink": "https://bigquery.googleapis.com/bigquery/v2/projects/mock/datasets/mock",
			}),
		},
	}
}

// PropMap is a convenience wrapper around resource.NewPropertyMapFromMap.
// Tests can use this instead of importing the resource package directly.
func PropMap(m map[string]interface{}) resource.PropertyMap {
	return resource.NewPropertyMapFromMap(m)
}

// NewResource implements pulumi.Mock.
func (t *ResourceTracker) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	t.mu.Lock()
	defer t.mu.Unlock()

	t.resources = append(t.resources, TrackedResource{
		TypeToken: args.TypeToken,
		Name:      args.Name,
		Inputs:    args.Inputs,
	})

	outputs := args.Inputs.Copy()
	if overrides, ok := t.OutputOverrides[args.TypeToken]; ok {
		for k, v := range overrides {
			outputs[k] = v
		}
	}

	return args.Name + "-id", outputs, nil
}

// Call implements pulumi.Mock.
func (t *ResourceTracker) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return resource.PropertyMap{}, nil
}

// ---------- Query helpers ----------

// All returns every tracked resource.
func (t *ResourceTracker) All() []TrackedResource {
	t.mu.Lock()
	defer t.mu.Unlock()
	out := make([]TrackedResource, len(t.resources))
	copy(out, t.resources)
	return out
}

// ByType returns all tracked resources matching the given type token.
func (t *ResourceTracker) ByType(typeToken string) []TrackedResource {
	t.mu.Lock()
	defer t.mu.Unlock()
	var out []TrackedResource
	for _, r := range t.resources {
		if r.TypeToken == typeToken {
			out = append(out, r)
		}
	}
	return out
}

// ByName returns the first tracked resource with the given name, or nil.
func (t *ResourceTracker) ByName(name string) *TrackedResource {
	t.mu.Lock()
	defer t.mu.Unlock()
	for _, r := range t.resources {
		if r.Name == name {
			return &TrackedResource{
				TypeToken: r.TypeToken,
				Name:      r.Name,
				Inputs:    r.Inputs,
			}
		}
	}
	return nil
}

// TypeCount returns the number of resources registered with the given type token.
func (t *ResourceTracker) TypeCount(typeToken string) int {
	return len(t.ByType(typeToken))
}

// ---------- Assertion helpers ----------

// RequireType asserts that exactly `count` resources of the given type were registered.
func (t *ResourceTracker) RequireType(tb testing.TB, typeToken string, count int) []TrackedResource {
	tb.Helper()
	resources := t.ByType(typeToken)
	require.Len(tb, resources, count, "expected %d resources of type %q, got %d", count, typeToken, len(resources))
	return resources
}

// AssertInputEquals asserts that a specific input property on a named resource equals the expected value.
func (t *ResourceTracker) AssertInputEquals(tb testing.TB, resourceName, inputKey, expectedValue string) {
	tb.Helper()
	r := t.ByName(resourceName)
	if !assert.NotNil(tb, r, "resource %q not found; available: %v", resourceName, t.names()) {
		return
	}
	actual := r.Inputs[resource.PropertyKey(inputKey)]
	if actual.IsNull() {
		tb.Errorf("resource %q input %q is null, expected %q", resourceName, inputKey, expectedValue)
		return
	}
	assert.Equal(tb, expectedValue, actual.StringValue(),
		"resource %q input %q", resourceName, inputKey)
}

// AssertInputBool asserts that a specific boolean input on a named resource equals the expected value.
func (t *ResourceTracker) AssertInputBool(tb testing.TB, resourceName, inputKey string, expected bool) {
	tb.Helper()
	r := t.ByName(resourceName)
	if !assert.NotNil(tb, r, "resource %q not found; available: %v", resourceName, t.names()) {
		return
	}
	actual := r.Inputs[resource.PropertyKey(inputKey)]
	if actual.IsNull() {
		tb.Errorf("resource %q input %q is null, expected %v", resourceName, inputKey, expected)
		return
	}
	assert.Equal(tb, expected, actual.BoolValue(),
		"resource %q input %q", resourceName, inputKey)
}

// names returns all resource names for diagnostics.
func (t *ResourceTracker) names() []string {
	t.mu.Lock()
	defer t.mu.Unlock()
	out := make([]string, len(t.resources))
	for i, r := range t.resources {
		out[i] = r.Name
	}
	return out
}

// Dump logs every registered resource (type + name) to the test log.
// Useful for debugging failing tests.
func (t *ResourceTracker) Dump(tb testing.TB) {
	tb.Helper()
	t.mu.Lock()
	defer t.mu.Unlock()
	tb.Logf("--- ResourceTracker dump (%d resources) ---", len(t.resources))
	for i, r := range t.resources {
		tb.Logf("  [%d] type=%q name=%q", i, r.TypeToken, r.Name)
	}
}
