/**
 * Cloud Build Private Pool Module
 * Mirrors: 0-bootstrap/modules/cb-private-pool
 * Creates a Cloud Build private worker pool with optional VPC peering and VPN.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { Network, FirewallRules } from "@vitruviansoftware/foundation-network";

export interface PrivateWorkerPoolConfig {
    region: string;
    enableNetworkPeering?: boolean;
    createPeeredNetwork?: boolean;
    peeredNetworkSubnetIp?: string;
    peeringAddress?: string;
    peeringPrefixLength?: number;
}

export interface VpnConfig {
    enableVpn?: boolean;
}

export interface VpcFlowLogsConfig {
    aggregationInterval?: string;
    flowSampling?: number;
    metadata?: string;
    metadataFields?: string[];
    filterExpr?: string;
}

export interface CbPrivatePoolArgs {
    projectId: pulumi.Input<string>;
    privateWorkerPool: PrivateWorkerPoolConfig;
    vpnConfiguration?: VpnConfig;
    vpcFlowLogs?: VpcFlowLogsConfig;
}

export class CbPrivatePool extends pulumi.ComponentResource {
    public readonly privateWorkerPoolId: pulumi.Output<string>;
    public readonly workerRangeId: pulumi.Output<string> | undefined;
    public readonly workerPeeredIpRange: pulumi.Output<string> | undefined;
    public readonly peeredNetworkId: pulumi.Output<string> | undefined;

    constructor(name: string, args: CbPrivatePoolArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:CbPrivatePool", name, args, opts);

        const pwp = args.privateWorkerPool;
        let networkId: pulumi.Output<string> | undefined;
        let peeredIpRange: pulumi.Output<string> | undefined;

        // Create peered network if requested
        if (pwp.createPeeredNetwork) {
            const networkName = `vpc-b-cbpools`;
            const peeredNetwork = new Network(`${name}-peered-network`, {
                projectId: args.projectId,
                networkName: networkName,
                deleteDefaultInternetGatewayRoutes: true,
                subnets: [{
                    subnetName: `sb-b-cbpools-${pwp.region}`,
                    subnetIp: pwp.peeredNetworkSubnetIp ?? "10.3.0.0/24",
                    subnetRegion: pwp.region,
                    subnetPrivateAccess: true,
                    subnetFlowLogs: true,
                    subnetFlowLogsInterval: args.vpcFlowLogs?.aggregationInterval,
                    subnetFlowLogsSampling: args.vpcFlowLogs?.flowSampling,
                    subnetFlowLogsMetadata: args.vpcFlowLogs?.metadata,
                    subnetFlowLogsMetadataFields: args.vpcFlowLogs?.metadataFields,
                    subnetFlowLogsFilter: args.vpcFlowLogs?.filterExpr,
                    description: "Peered subnet for Cloud Build private pool",
                }],
            }, { parent: this });

            networkId = peeredNetwork.networkId;

            // DNS policy
            new gcp.dns.Policy(`${name}-dns-policy`, {
                project: args.projectId,
                name: "dp-b-cbpools-default-policy",
                enableInboundForwarding: true,
                enableLogging: true,
                networks: [{
                    networkUrl: peeredNetwork.networkSelfLink,
                }],
            }, { parent: this });
        }

        // Network peering for worker pool
        if (pwp.enableNetworkPeering && networkId) {
            const workerPoolRange = new gcp.compute.GlobalAddress(`${name}-worker-range`, {
                name: "ga-b-cbpools-worker-pool-range",
                project: args.projectId,
                purpose: "VPC_PEERING",
                addressType: "INTERNAL",
                address: pwp.peeringAddress ?? "192.168.0.0",
                prefixLength: pwp.peeringPrefixLength ?? 24,
                network: networkId,
            }, { parent: this });

            this.workerRangeId = workerPoolRange.id;

            peeredIpRange = pulumi.interpolate`${workerPoolRange.address}/${workerPoolRange.prefixLength}`;
            this.workerPeeredIpRange = peeredIpRange;

            const conn = new gcp.servicenetworking.Connection(`${name}-worker-conn`, {
                network: networkId,
                service: "servicenetworking.googleapis.com",
                reservedPeeringRanges: [workerPoolRange.name],
            }, { parent: this });

            new gcp.compute.NetworkPeeringRoutesConfig(`${name}-peering-routes`, {
                project: args.projectId,
                peering: conn.peering,
                network: `vpc-b-cbpools`,
                importCustomRoutes: true,
                exportCustomRoutes: true,
            }, { parent: this });

            // Firewall: allow ingress from service networking
            new FirewallRules(`${name}-firewall`, {
                projectId: args.projectId,
                networkName: networkId,
                rules: [{
                    name: "fw-b-cbpools-100-i-a-all-all-all-service-networking",
                    description: "allow ingress from the IPs configured for service networking",
                    direction: "INGRESS",
                    priority: 100,
                    ranges: [peeredIpRange! as any],
                    allow: [{ protocol: "all" }],
                    logConfig: { metadata: "INCLUDE_ALL_METADATA" },
                }],
            }, { parent: this });
        }

        this.peeredNetworkId = networkId;

        // Create the private worker pool
        const pool = new gcp.cloudbuild.WorkerPool(`${name}-worker-pool`, {
            name: `cb-pool-${pwp.region}`,
            project: args.projectId,
            location: pwp.region,
            workerConfig: {
                diskSizeGb: 100,
                machineType: "e2-standard-4",
                noExternalIp: true,
            },
            networkConfig: networkId ? {
                peeredNetwork: networkId,
                peeredNetworkIpRange: "/29",
            } : undefined,
        }, { parent: this });

        this.privateWorkerPoolId = pool.id;

        this.registerOutputs({
            privateWorkerPoolId: this.privateWorkerPoolId,
        });
    }
}
