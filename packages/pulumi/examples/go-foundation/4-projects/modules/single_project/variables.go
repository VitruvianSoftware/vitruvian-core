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

// Module inputs — the Pulumi analogue of upstream
// 4-projects/modules/single_project/variables.tf.

package single_project

import (
	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Args are the inputs to a single project creation. ProjectID doubles as the
// display Name in every upstream call site, so New sets both from this one field
// (matching the pre-refactor inline `ProjectID`/`Name` pair, which were always
// the same fmt.Sprintf string).
type Args struct {
	ProjectID             string
	FolderID              pulumi.StringOutput
	BillingAccount        string
	RandomProjectID       bool
	Labels                pulumi.StringMapInput
	Budget                *project.BudgetConfig
	ActivateApis          []string
	DefaultServiceAccount string
	// ApiPropagationSeconds is forwarded to the project factory: >0 makes the
	// factory's ApisReady handle a `sleep N` gated on all enabled Services (see
	// project_factory.ProjectArgs), 0 leaves ApisReady = the project itself.
	ApiPropagationSeconds int
}
