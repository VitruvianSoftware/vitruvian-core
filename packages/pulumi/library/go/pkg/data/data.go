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
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/bigquery"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// DataPlatformArgs configures a BigQuery data platform with raw and curated
// datasets. Dataset IDs are parameterized to avoid collisions when deploying
// multiple DataPlatform instances in the same project.
type DataPlatformArgs struct {
	ProjectID        pulumi.StringInput
	Location         pulumi.StringInput
	RawDatasetID     string // defaults to "raw_data" if empty
	CuratedDatasetID string // defaults to "curated_data" if empty
}

type DataPlatform struct {
	pulumi.ResourceState
	RawDataset     *bigquery.Dataset
	CuratedDataset *bigquery.Dataset
}

func NewDataPlatform(ctx *pulumi.Context, name string, args *DataPlatformArgs, opts ...pulumi.ResourceOption) (*DataPlatform, error) {
	component := &DataPlatform{}
	err := ctx.RegisterComponentResource("pkg:index:DataPlatform", name, component, opts...)
	if err != nil {
		return nil, err
	}

	rawID := args.RawDatasetID
	if rawID == "" {
		rawID = "raw_data"
	}
	curatedID := args.CuratedDatasetID
	if curatedID == "" {
		curatedID = "curated_data"
	}

	raw, err := bigquery.NewDataset(ctx, name+"-raw", &bigquery.DatasetArgs{
		DatasetId: pulumi.String(rawID),
		Project:   args.ProjectID,
		Location:  args.Location,
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.RawDataset = raw

	curated, err := bigquery.NewDataset(ctx, name+"-curated", &bigquery.DatasetArgs{
		DatasetId: pulumi.String(curatedID),
		Project:   args.ProjectID,
		Location:  args.Location,
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.CuratedDataset = curated

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"rawDatasetId":     raw.DatasetId,
		"curatedDatasetId": curated.DatasetId,
	})

	return component, nil
}
