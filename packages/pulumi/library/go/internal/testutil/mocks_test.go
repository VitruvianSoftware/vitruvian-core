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

package testutil

import (
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewTracker_HasDefaultOverrides(t *testing.T) {
	tracker := NewTracker()
	assert.Contains(t, tracker.OutputOverrides, "gcp:organizations/project:Project")
	assert.Contains(t, tracker.OutputOverrides, "random:index/randomId:RandomId")
}

func TestResourceTracker_RecordsResources(t *testing.T) {
	tracker := NewTracker()
	id, outputs, err := tracker.NewResource(pulumi.MockResourceArgs{
		TypeToken: "test:index:Widget",
		Name:      "my-widget",
		Inputs: resource.NewPropertyMapFromMap(map[string]interface{}{
			"color": "blue",
		}),
	})
	require.NoError(t, err)
	assert.Equal(t, "my-widget-id", id)
	assert.Equal(t, "blue", outputs["color"].StringValue())

	all := tracker.All()
	assert.Len(t, all, 1)
	assert.Equal(t, "test:index:Widget", all[0].TypeToken)
}

func TestResourceTracker_ByType(t *testing.T) {
	tracker := NewTracker()
	tracker.NewResource(pulumi.MockResourceArgs{TypeToken: "type-a", Name: "a1", Inputs: resource.PropertyMap{}})
	tracker.NewResource(pulumi.MockResourceArgs{TypeToken: "type-b", Name: "b1", Inputs: resource.PropertyMap{}})
	tracker.NewResource(pulumi.MockResourceArgs{TypeToken: "type-a", Name: "a2", Inputs: resource.PropertyMap{}})

	assert.Len(t, tracker.ByType("type-a"), 2)
	assert.Len(t, tracker.ByType("type-b"), 1)
	assert.Len(t, tracker.ByType("type-c"), 0)
}

func TestResourceTracker_ByName(t *testing.T) {
	tracker := NewTracker()
	tracker.NewResource(pulumi.MockResourceArgs{TypeToken: "test:index:Thing", Name: "foo", Inputs: resource.PropertyMap{}})
	tracker.NewResource(pulumi.MockResourceArgs{TypeToken: "test:index:Thing", Name: "bar", Inputs: resource.PropertyMap{}})

	r := tracker.ByName("foo")
	require.NotNil(t, r)
	assert.Equal(t, "test:index:Thing", r.TypeToken)

	assert.Nil(t, tracker.ByName("nonexistent"))
}

func TestResourceTracker_TypeCount(t *testing.T) {
	tracker := NewTracker()
	tracker.NewResource(pulumi.MockResourceArgs{TypeToken: "x", Name: "1", Inputs: resource.PropertyMap{}})
	tracker.NewResource(pulumi.MockResourceArgs{TypeToken: "x", Name: "2", Inputs: resource.PropertyMap{}})

	assert.Equal(t, 2, tracker.TypeCount("x"))
	assert.Equal(t, 0, tracker.TypeCount("y"))
}

func TestResourceTracker_OutputOverrides(t *testing.T) {
	tracker := NewTracker()
	tracker.OutputOverrides["test:index:Foo"] = resource.NewPropertyMapFromMap(map[string]interface{}{
		"computed": "magic-value",
	})

	_, outputs, _ := tracker.NewResource(pulumi.MockResourceArgs{
		TypeToken: "test:index:Foo",
		Name:      "foo",
		Inputs: resource.NewPropertyMapFromMap(map[string]interface{}{
			"input": "hello",
		}),
	})
	assert.Equal(t, "hello", outputs["input"].StringValue())
	assert.Equal(t, "magic-value", outputs["computed"].StringValue())
}

func TestResourceTracker_Call(t *testing.T) {
	tracker := NewTracker()
	result, err := tracker.Call(pulumi.MockCallArgs{})
	require.NoError(t, err)
	assert.Empty(t, result)
}

func TestResourceTracker_Assertions(t *testing.T) {
	tracker := NewTracker()
	_, _, err := tracker.NewResource(pulumi.MockResourceArgs{
		TypeToken: "type-a",
		Name:      "a1",
		Inputs: resource.NewPropertyMapFromMap(map[string]interface{}{
			"foo": "bar",
			"baz": true,
		}),
	})
	require.NoError(t, err)

	pm := PropMap(map[string]interface{}{"is_mock": true})
	require.NotNil(t, pm)

	tracker.RequireType(t, "type-a", 1)
	tracker.AssertInputEquals(t, "a1", "foo", "bar")
	tracker.AssertInputBool(t, "a1", "baz", true)

	// Test nonexistent branches with dummy T
	dummyT := new(testing.T)
	tracker.AssertInputEquals(dummyT, "nonexistent", "foo", "bar")
	tracker.AssertInputBool(dummyT, "nonexistent", "baz", true)

	tracker.Dump(t)
}
