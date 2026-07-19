# modules / shared_vpc

Placeholder for upstream terraform-example-foundation
[`3-networks-svpc/modules/shared_vpc`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-svpc/modules/shared_vpc).

Pulumi-port note: in this port the Shared VPC resource composition (VPC,
subnets, routes, routers, firewall, PSC, DNS, NAT, VPC-SC) lives inline in
the sibling `base_env` module — a documented structural divergence that
keeps the original flat port's resource logical names intact. This package
(`main.go`) marks the upstream module boundary; the upstream per-concern
split (`dns.tf`, `firewall.tf`, `nat.tf`, `private_service_connect.tf`,
`service_control.tf`, …) maps onto the numbered sections of
`../base_env/main.go`.
