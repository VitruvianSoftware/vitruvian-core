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
// 4-projects/modules/single_project/outputs.tf.

package single_project

import (
	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Result holds the created project. Project is the raw project-factory handle,
// surfaced so callers can attach it to a Shared VPC / VPC-SC perimeter, hang CMEK
// storage off it, or build peering infrastructure on it — exactly as the inline
// code did with the `*project.Project` return value.
type Result struct {
	Project       *project.Project
	ProjectID     pulumi.StringOutput
	ProjectNumber pulumi.StringOutput
	// ApisReadyProjectID is the project id as a DATA dependency on the API
	// propagation gate: it resolves only after the factory's ApisReady wait has
	// run. Thread it (instead of ProjectID) into library components whose inner
	// resources must not race freshly-enabled APIs — a component-level DependsOn
	// does NOT propagate to a component's children in the Pulumi Go SDK, so a
	// data dependency is the only way to gate them from outside the library.
	ApisReadyProjectID pulumi.StringOutput
}
