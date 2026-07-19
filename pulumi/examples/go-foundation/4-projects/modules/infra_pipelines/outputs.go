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

// Module outputs — the Pulumi analogue of upstream
// 4-projects/modules/infra_pipelines/outputs.tf.

package infra_pipelines

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Result holds the module outputs. Upstream outputs the Cloud Build plumbing
// (terraform_service_accounts, repos, buckets, trigger ids); under the WIF
// model the pipeline project id is the only output consumers need (upstream's
// cloudbuild_project_id analogue, exported by the shared leaf as
// infra_pipeline_project_id).
type Result struct {
	ProjectID pulumi.StringOutput
}
