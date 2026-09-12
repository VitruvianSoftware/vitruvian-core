# modules / dedicated_interconnect

Stand-in for upstream terraform-example-foundation
[`3-networks-hub-and-spoke/modules/dedicated_interconnect`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-hub-and-spoke/modules/dedicated_interconnect).

Engine adaptation: Dedicated Interconnect is optional and site-specific, so
this port ships it as a rename-to-activate example (`main.go.example`)
instead of an always-compiled module. See also the leaf-level example in
`../../envs/shared/interconnect.go.example`.
