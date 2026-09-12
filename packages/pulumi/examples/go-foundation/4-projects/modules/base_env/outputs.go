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
// 4-projects/modules/base_env/outputs.tf.

package base_env

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// BUProjects holds outputs from business unit project deployment.
type BUProjects struct {
	SVPCProjectID                pulumi.StringOutput
	SVPCProjectNumber            pulumi.StringOutput
	FloatingProjectID            pulumi.StringOutput
	PeeringProjectID             pulumi.StringOutput
	PeeringNetworkSelfLink       pulumi.StringOutput
	PeeringSubnetSelfLink        pulumi.StringOutput
	IAPFirewallTags              pulumi.MapOutput
	CMEKBucket                   *pulumi.StringOutput
	CMEKKeyring                  *pulumi.StringOutput
	CMEKKeys                     *pulumi.StringArrayOutput
	ConfSpaceProjectID           *pulumi.StringOutput
	ConfSpaceProjectNumber       *pulumi.StringOutput
	ConfSpaceWorkloadSA          *pulumi.StringOutput
	SubnetsSelfLinks             pulumi.StringArrayOutput
	VPCSCPerimeterName           pulumi.StringOutput
	PeeringComplete              pulumi.BoolOutput
	AccessContextManagerPolicyID pulumi.StringOutput
	RestrictedEnabledApis        []string
}
