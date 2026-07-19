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
