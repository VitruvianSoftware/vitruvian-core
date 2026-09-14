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

// createNAT provisions the per-region NAT routers (conditional), mirroring
// upstream shared_vpc/nat.tf. Each router is chained behind the previous
// route-modifying resource; the last router is returned so the caller can
// continue the serialisation chain.
func createNAT(ctx *pulumi.Context, args *Args, vpc *networking.Networking, routeDependency pulumi.Resource) (pulumi.Resource, error) {
	for _, reg := range []string{args.Region1, args.Region2} {
		natRouter, err := networking.NewCloudRouter(ctx, fmt.Sprintf("%s-nat-%s", args.Mode, reg), &networking.RouterArgs{
			ProjectID:       args.ProjectID,
			Region:          reg,
			Network:         vpc.VPC.SelfLink,
			BgpAsn:          args.NatBgpAsn,
			EnableNat:       true,
			NatNumAddresses: args.NatNumAddresses,
		}, pulumi.DependsOn([]pulumi.Resource{routeDependency}))
		if err != nil {
			return nil, err
		}
		routeDependency = natRouter.Router
	}
	return routeDependency, nil
}
