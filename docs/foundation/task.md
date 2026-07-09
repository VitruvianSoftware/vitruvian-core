# Foundation Audit Fixes — Task Tracker

## Priority 1 — Critical

- `[x]` 1. Deploy VPC Service Controls in live networks (access levels, regular perimeter, bridge perimeters, `time.NewSleep` 60s create+destroy)
- `[x]` 2. Add Bridge Perimeter (`PERIMETER_TYPE_BRIDGE`) for spoke→hub in example + live
- `[x]` 3. Add hub proxy-only subnets (`REGIONAL_MANAGED_PROXY`) for both regions in live
- `[x]` 4. Export missing outputs from live networks
- `[x]` 5. Make transitivity conditional (default `false`) in example + live
- `[x]` 6. Make NAT conditional (default `false`) in example + live
- `[x]` 7. Fix hub CIDRs to match upstream (`10.8.0.0/18`, `10.9.0.0/18`) in example + live
- `[x]` 8. Fix secondary ranges to R1 only in example + live
- `[x]` 9. Fix spoke peering export routes (spoke NOT export to hub) in live
- `[x]` 10. Fix hub-and-spoke SA roles — remove spoke project grants, hub only

## Priority 2 — Should Fix

- `[x]` 11. Add Windows KMS route (conditional, default `false`) in example + live
- `[x]` 12. Fix hierarchical FW associations — config-driven, accepts list of folder IDs
- `[x]` 13. Add `.go.example` files for interconnect/VPN to live foundation
- `[x]` 14. Add `destroy_duration` to VPC-SC `time.NewSleep` in example
- `[x]` 15. Fix labels — `primary_contact: "james_nguyen"`, `secondary_contact: "christine_kim"` in live
- `[x]` 16. Fix example 2-environments to use 1-stack-per-env model
