# modules / vpn-ha

Stand-in for upstream terraform-example-foundation
[`3-networks-hub-and-spoke/modules/vpn-ha`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-hub-and-spoke/modules/vpn-ha).

Engine adaptation: HA VPN is optional and site-specific, so this port ships
it as a rename-to-activate example in `../base_env/vpn.go.example` (the
upstream `base_env/vpn.tf.example` instantiation point) backed by the
pulumi-library networking components, instead of an always-compiled module.
