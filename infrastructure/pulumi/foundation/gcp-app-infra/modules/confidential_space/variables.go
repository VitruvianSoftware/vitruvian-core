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

// variables.go mirrors upstream 5-app-infra/modules/confidential_space/variables.tf —
// the module's input surface. Engine adaptation: upstream's
// remote_state_bucket variable has no equivalent here because the calling
// leaf resolves the 4-projects Stack References itself (see the leaf's
// remote.go) and passes resolved values in.

package confidential_space

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// ConfidentialSpaceArgs configures a Confidential Space VM deployment,
// matching the upstream Terraform confidential_space module.
type ConfidentialSpaceArgs struct {
	Env                      string
	BusinessUnit             string
	ProjectID                pulumi.StringInput
	ProjectNumber            pulumi.StringInput // from 4-projects stack export
	Region                   pulumi.StringInput
	SubnetworkSelfLink       pulumi.StringInput
	WorkloadSAEmail          pulumi.StringInput
	ConfidentialImageDigest  string
	ConfidentialMachineType  string
	ConfidentialInstanceType string
	CpuPlatform              string
	CloudBuildProjectID      pulumi.StringInput
}
