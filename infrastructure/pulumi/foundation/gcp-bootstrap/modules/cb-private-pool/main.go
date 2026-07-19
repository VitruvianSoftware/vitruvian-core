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

// Package cbprivatepool mirrors the upstream terraform-example-foundation
// 0-bootstrap/modules/cb-private-pool module: a Cloud Build private worker
// pool, optionally peered (via Private Service Access) to a VPC network that
// this module can create, and optionally connected to on-prem through HA VPN.
//
// The module follows upstream's file-per-concern layout:
//
//	main.go      — main.tf      (the private worker pool)
//	network.go   — network.tf   (optional peered network + PSA peering)
//	vpn_ha.go    — vpn_ha.tf    (optional HA VPN to on-prem)
//	variables.go — variables.tf (inputs, defaults, validations)
//	outputs.go   — outputs.tf   (component outputs)
package cbprivatepool

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudbuild"
	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// NewCbPrivatePool provisions the Cloud Build private worker pool and its
// optional peered network / HA VPN, mirroring upstream main.tf, network.tf
// and vpn_ha.tf.
func NewCbPrivatePool(ctx *pulumi.Context, name string, args *CbPrivatePoolArgs, opts ...pulumi.ResourceOption) (*CbPrivatePool, error) {
	pw, vpn, fl, err := resolveAndValidate(args)
	if err != nil {
		return nil, err
	}

	var resource CbPrivatePool
	err = ctx.RegisterComponentResource("modules:cb-private-pool:CbPrivatePool", name, &resource, opts...)
	if err != nil {
		return nil, err
	}

	// Mirrors: random_string.suffix.
	suffix, err := random.NewRandomString(ctx, fmt.Sprintf("%s-suffix", name), &random.RandomStringArgs{
		Length:  pulumi.Int(4),
		Special: pulumi.Bool(false),
		Upper:   pulumi.Bool(false),
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	// Mirrors: local.private_pool_name.
	var poolName pulumi.StringInput
	if pw.Name != "" {
		poolName = pulumi.String(pw.Name)
	} else {
		poolName = pulumi.Sprintf("private-pool-%s", suffix.Result)
	}

	// network.tf — optional peered network (see network.go).
	net, err := deployNetwork(ctx, name, &resource, args, pw, fl)
	if err != nil {
		return nil, err
	}

	// ------------------------------------------------------------------
	// main.tf — the Cloud Build private worker pool
	// ------------------------------------------------------------------
	workerPoolArgs := &cloudbuild.WorkerPoolArgs{
		Project:  args.ProjectID,
		Name:     poolName,
		Location: pulumi.String(pw.Region),
		WorkerConfig: &cloudbuild.WorkerPoolWorkerConfigArgs{
			DiskSizeGb:   pulumi.Int(pw.DiskSizeGb),
			MachineType:  pulumi.String(pw.MachineType),
			NoExternalIp: pulumi.Bool(pw.NoExternalIP),
		},
	}
	if pw.EnableNetworkPeering {
		workerPoolArgs.NetworkConfig = &cloudbuild.WorkerPoolNetworkConfigArgs{
			PeeredNetwork: net.peeredNetworkID,
		}
	}
	privatePool, err := cloudbuild.NewWorkerPool(ctx, fmt.Sprintf("%s-private-pool", name), workerPoolArgs,
		pulumi.Parent(&resource), pulumi.DependsOn(net.poolDependencies))
	if err != nil {
		return nil, err
	}

	// vpn_ha.tf — optional HA VPN to on-prem (see vpn_ha.go).
	if err := deployVPNHA(ctx, name, &resource, args, pw, vpn, net); err != nil {
		return nil, err
	}

	resource.PrivateWorkerPoolID = privatePool.ID().ToStringOutput().ApplyT(func(id string) string { return id }).(pulumi.StringOutput)
	resource.WorkerRangeID = net.workerRangeID
	resource.WorkerPeeredIPRange = net.peeredIPRange
	resource.PeeredNetworkID = pulumi.ToOutput(net.peeredNetworkID).ApplyT(func(id interface{}) string {
		s, _ := id.(string)
		return s
	}).(pulumi.StringOutput)

	return &resource, nil
}
