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

package data

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewDataPlatform_DefaultDatasetIDs(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		dp, err := NewDataPlatform(ctx, "test-data", &DataPlatformArgs{
			ProjectID: pulumi.String("prj-data"),
			Location:  pulumi.String("US"),
		})
		require.NoError(t, err)
		assert.NotNil(t, dp.RawDataset)
		assert.NotNil(t, dp.CuratedDataset)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	datasets := tracker.RequireType(t, "gcp:bigquery/dataset:Dataset", 2)
	ids := map[string]bool{}
	for _, ds := range datasets {
		ids[ds.Inputs["datasetId"].StringValue()] = true
	}
	assert.True(t, ids["raw_data"])
	assert.True(t, ids["curated_data"])
}

func TestNewDataPlatform_CustomDatasetIDs(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDataPlatform(ctx, "test-custom", &DataPlatformArgs{
			ProjectID:        pulumi.String("prj-custom"),
			Location:         pulumi.String("EU"),
			RawDatasetID:     "my_raw_events",
			CuratedDatasetID: "my_curated_analytics",
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	datasets := tracker.RequireType(t, "gcp:bigquery/dataset:Dataset", 2)
	ids := map[string]bool{}
	for _, ds := range datasets {
		ids[ds.Inputs["datasetId"].StringValue()] = true
	}
	assert.True(t, ids["my_raw_events"])
	assert.True(t, ids["my_curated_analytics"])
}

func TestNewDataPlatform_LocationPropagated(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDataPlatform(ctx, "test-loc", &DataPlatformArgs{
			ProjectID: pulumi.String("prj-loc"),
			Location:  pulumi.String("europe-west1"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	for _, ds := range tracker.RequireType(t, "gcp:bigquery/dataset:Dataset", 2) {
		assert.Equal(t, "europe-west1", ds.Inputs["location"].StringValue())
	}
}

func TestNewDataPlatform_ProjectPropagated(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDataPlatform(ctx, "test-proj-prop", &DataPlatformArgs{
			ProjectID: pulumi.String("prj-prop-check"),
			Location:  pulumi.String("US"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	for _, ds := range tracker.RequireType(t, "gcp:bigquery/dataset:Dataset", 2) {
		assert.Equal(t, "prj-prop-check", ds.Inputs["project"].StringValue())
	}
}

func TestNewDataPlatform_PartialCustomIDs(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDataPlatform(ctx, "test-partial", &DataPlatformArgs{
			ProjectID:    pulumi.String("prj-partial"),
			Location:     pulumi.String("US"),
			RawDatasetID: "custom_raw",
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	datasets := tracker.RequireType(t, "gcp:bigquery/dataset:Dataset", 2)
	ids := map[string]bool{}
	for _, ds := range datasets {
		ids[ds.Inputs["datasetId"].StringValue()] = true
	}
	assert.True(t, ids["custom_raw"])
	assert.True(t, ids["curated_data"], "empty CuratedDatasetID should default")
}

func TestNewDataPlatform_ResourceNames(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDataPlatform(ctx, "my-dp", &DataPlatformArgs{
			ProjectID: pulumi.String("prj-names"),
			Location:  pulumi.String("US"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	// Resource names should follow component naming convention
	raw := tracker.ByName("my-dp-raw")
	require.NotNil(t, raw, "raw dataset resource not found")
	curated := tracker.ByName("my-dp-curated")
	require.NotNil(t, curated, "curated dataset resource not found")
}
