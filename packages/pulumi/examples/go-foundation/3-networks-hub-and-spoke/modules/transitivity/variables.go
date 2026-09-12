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

package transitivity

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Args are the inputs to the transitivity module.
type Args struct {
	ProjectID      pulumi.StringInput
	EnvCode        string
	Region1        string
	Region2        string
	Network        pulumi.StringInput // hub VPC self link
	NetworkName    string
	Subnetworks    map[string]pulumi.StringInput
	FirewallPolicy pulumi.StringInput // hub firewall policy name
	VPC            pulumi.Resource    // hub VPC, for DependsOn serialisation
}
