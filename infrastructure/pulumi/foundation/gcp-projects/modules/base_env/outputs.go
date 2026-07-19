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
	OSSFloatingProjectID         pulumi.StringOutput
	OSSFloatingProjectNumber     pulumi.StringOutput
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
