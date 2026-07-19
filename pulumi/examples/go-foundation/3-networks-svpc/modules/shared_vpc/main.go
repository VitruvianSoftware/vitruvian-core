// Package shared_vpc mirrors terraform-example-foundation
// 3-networks-svpc/modules/shared_vpc for structural parity with upstream.
//
// Pulumi-port note: in this port the Shared VPC resource composition (VPC,
// subnets, routes, routers, firewall, PSC, DNS, NAT, VPC-SC) lives inline in
// the sibling base_env module — a documented structural divergence that keeps
// the original flat port's resource logical names intact. This package is a
// placeholder for the upstream module boundary.
package shared_vpc
