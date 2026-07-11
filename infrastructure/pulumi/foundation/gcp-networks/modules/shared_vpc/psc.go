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
