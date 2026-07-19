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
