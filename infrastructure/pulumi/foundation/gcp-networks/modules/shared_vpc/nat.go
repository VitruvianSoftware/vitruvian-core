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
