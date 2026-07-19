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

package shared_vpc

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// createPSC provisions the Private Service Connect endpoint, mirroring upstream
// shared_vpc/private_service_connect.tf.
func createPSC(ctx *pulumi.Context, args *Args, vpc *networking.Networking) error {
	resourceName := fmt.Sprintf("%s-psc", args.Mode)
	_, err := networking.NewPrivateServiceConnect(ctx, resourceName, &networking.PrivateServiceConnectArgs{
		ProjectID:            args.ProjectID,
		NetworkSelfLink:      vpc.VPC.SelfLink,
		DnsCode:              fmt.Sprintf("dz-%s-%s", args.Code, args.Mode),
		IPAddress:            args.PscIP,
		ForwardingRuleTarget: "vpc-sc",
	}, pulumi.DependsOn([]pulumi.Resource{vpc.VPC}))
	return err
}
