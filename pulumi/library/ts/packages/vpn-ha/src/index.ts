/**
 * VPN HA Module
 * Mirrors: terraform-google-modules/vpn/google//modules/vpn_ha
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface VpnHaTunnelConfig {
    /** BGP session range for this tunnel. */
    bgpSessionRange: string;
    /** Peer BGP session range. */
    peerBgpSessionRange: string;
    /** Peer ASN. */
    peerAsn: number;
    /** Shared secret for the tunnel. */
    sharedSecret: string;
    /** VPN gateway interface. */
    vpnGatewayInterface: number;
}

export interface VpnHaArgs {
    /** Project ID. */
    projectId: pulumi.Input<string>;
    /** Region. */
    region: string;
    /** Network self-link or ID. */
    network: pulumi.Input<string>;
    /** Name for the VPN gateway. */
    name: string;
    /** Router ASN. */
    routerAsn: number;
    /** Peer VPN gateway self-link (for GCP-to-GCP). */
    peerGcpGateway?: pulumi.Input<string>;
    /** External peer gateway config (for on-prem). */
    peerExternalGateway?: {
        name: string;
        redundancyType?: string;
        interfaces: { id: number; ipAddress: string }[];
    };
    /** Tunnel configurations. */
    tunnels: VpnHaTunnelConfig[];
}

export class VpnHa extends pulumi.ComponentResource {
    public readonly gateway: gcp.compute.HaVpnGateway;
    public readonly router: gcp.compute.Router;

    constructor(name: string, args: VpnHaArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:VpnHa", name, args, opts);

        // Create HA VPN Gateway
        this.gateway = new gcp.compute.HaVpnGateway(`${name}-gateway`, {
            name: args.name,
            project: args.projectId,
            region: args.region,
            network: args.network,
        }, { parent: this });

        // Create Cloud Router
        this.router = new gcp.compute.Router(`${name}-router`, {
            name: `cr-${args.name}`,
            project: args.projectId,
            region: args.region,
            network: args.network,
            bgp: {
                asn: args.routerAsn,
            },
        }, { parent: this });

        // Create external peer gateway if needed
        let peerGateway: gcp.compute.ExternalVpnGateway | undefined;
        if (args.peerExternalGateway) {
            peerGateway = new gcp.compute.ExternalVpnGateway(`${name}-peer-gw`, {
                name: args.peerExternalGateway.name,
                project: args.projectId,
                redundancyType: args.peerExternalGateway.redundancyType ?? "TWO_IPS_REDUNDANCY",
                interfaces: args.peerExternalGateway.interfaces.map(i => ({
                    id: i.id,
                    ipAddress: i.ipAddress,
                })),
            }, { parent: this });
        }

        // Create tunnels
        for (let i = 0; i < args.tunnels.length; i++) {
            const tunnelCfg = args.tunnels[i];
            const tunnel = new gcp.compute.VPNTunnel(`${name}-tunnel-${i}`, {
                name: `${args.name}-tunnel-${i}`,
                project: args.projectId,
                region: args.region,
                vpnGateway: this.gateway.id,
                vpnGatewayInterface: tunnelCfg.vpnGatewayInterface,
                peerGcpGateway: args.peerGcpGateway,
                peerExternalGateway: peerGateway?.id,
                peerExternalGatewayInterface: peerGateway ? tunnelCfg.vpnGatewayInterface : undefined,
                sharedSecret: tunnelCfg.sharedSecret,
                router: this.router.id,
            }, { parent: this });

            const iface = new gcp.compute.RouterInterface(`${name}-iface-${i}`, {
                name: `${args.name}-iface-${i}`,
                project: args.projectId,
                region: args.region,
                router: this.router.name,
                ipRange: tunnelCfg.bgpSessionRange,
                vpnTunnel: tunnel.name,
            }, { parent: this });

            new gcp.compute.RouterPeer(`${name}-peer-${i}`, {
                name: `${args.name}-peer-${i}`,
                project: args.projectId,
                region: args.region,
                router: this.router.name,
                peerAsn: tunnelCfg.peerAsn,
                peerIpAddress: tunnelCfg.peerBgpSessionRange.split("/")[0],
                interface: iface.name,
            }, { parent: this });
        }

        this.registerOutputs({
            gatewayId: this.gateway.id,
            routerId: this.router.id,
        });
    }
}
