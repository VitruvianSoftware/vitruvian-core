/**
 * Local module: network
 * Re-exports the Network library for 1-org DNS hub / base network setup.
 * Mirrors: terraform-example-foundation/1-org/modules/network
 */
export { Network, SubnetConfig } from "@vitruviansoftware/foundation-network";
export { DnsHub, DnsHubArgs } from "@vitruviansoftware/foundation-dns-hub";
