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
