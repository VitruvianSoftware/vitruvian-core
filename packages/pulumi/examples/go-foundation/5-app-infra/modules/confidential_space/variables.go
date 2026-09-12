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
