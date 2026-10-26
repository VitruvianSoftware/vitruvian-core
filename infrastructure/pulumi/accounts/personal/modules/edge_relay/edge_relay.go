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

package edge_relay

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// DeployEdgeRelayArgs configures the public L4 TCP relay for Headscale.
type DeployEdgeRelayArgs struct {
	ProjectID    string
	Region       string
	Zone         string
	SSHPublicKey string
}

// EdgeRelayResult holds the provisioned static IP and compute instance.
type EdgeRelayResult struct {
	StaticIP pulumi.StringOutput
	Instance *compute.Instance
}

// DeployEdgeRelay provisions an Always-Free e2-micro instance in us-central1
// with a static external IPv4 address that relays TCP :443 to an outbound SSH
// reverse tunnel (:8443) initiated by the homelab k3s cluster.
func DeployEdgeRelay(ctx *pulumi.Context, name string, args *DeployEdgeRelayArgs, opts ...pulumi.ResourceOption) (*EdgeRelayResult, error) {
	address, err := compute.NewAddress(ctx, fmt.Sprintf("%s-ip", name), &compute.AddressArgs{
		Project:     pulumi.String(args.ProjectID),
		Region:      pulumi.String(args.Region),
		Description: pulumi.String("Static external IPv4 for Headscale L4 edge relay"),
		AddressType: pulumi.String("EXTERNAL"),
	}, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to create static IP: %w", err)
	}

	_, err = compute.NewFirewall(ctx, fmt.Sprintf("%s-allow-ingress", name), &compute.FirewallArgs{
		Project:     pulumi.String(args.ProjectID),
		Network:     pulumi.String("default"),
		Description: pulumi.String("Allow TCP 22 and 443 for Headscale edge relay"),
		Allows: compute.FirewallAllowArray{
			&compute.FirewallAllowArgs{
				Protocol: pulumi.String("tcp"),
				Ports: pulumi.StringArray{
					pulumi.String("22"),
					pulumi.String("443"),
				},
			},
		},
		SourceRanges: pulumi.StringArray{
			pulumi.String("0.0.0.0/0"),
		},
		TargetTags: pulumi.StringArray{
			pulumi.String("headscale-edge-relay"),
		},
	}, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to create firewall rule: %w", err)
	}

	startupScript := `#!/bin/bash
set -euo pipefail

id -u tunnel &>/dev/null || useradd -m -s /bin/bash tunnel
mkdir -p /home/tunnel/.ssh
chmod 700 /home/tunnel/.ssh
chown tunnel:tunnel /home/tunnel/.ssh

cat << 'EOF' > /etc/ssh/sshd_config.d/headscale-tunnel.conf
Match User tunnel
    AllowTcpForwarding yes
    X11Forwarding no
    AllowAgentForwarding no
    ClientAliveInterval 15
    ClientAliveCountMax 2
EOF
systemctl restart sshd

if ! command -v socat >/dev/null 2>&1; then
    apt-get update && apt-get install -y socat
fi

cat << 'EOF' > /etc/systemd/system/headscale-tcp-relay.service
[Unit]
Description=Headscale TCP 443 to Reverse Tunnel Relay
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=/usr/bin/socat TCP-LISTEN:443,fork,reuseaddr TCP:127.0.0.1:8443

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now headscale-tcp-relay.service
`

	instance, err := compute.NewInstance(ctx, fmt.Sprintf("%s-vm", name), &compute.InstanceArgs{
		Project:     pulumi.String(args.ProjectID),
		Zone:        pulumi.String(args.Zone),
		MachineType: pulumi.String("e2-micro"),
		Tags: pulumi.StringArray{
			pulumi.String("headscale-edge-relay"),
		},
		BootDisk: &compute.InstanceBootDiskArgs{
			InitializeParams: &compute.InstanceBootDiskInitializeParamsArgs{
				Image: pulumi.String("debian-cloud/debian-12"),
				Size:  pulumi.Int(30),
				Type:  pulumi.String("pd-standard"),
			},
		},
		NetworkInterfaces: compute.InstanceNetworkInterfaceArray{
			&compute.InstanceNetworkInterfaceArgs{
				Network: pulumi.String("default"),
				AccessConfigs: compute.InstanceNetworkInterfaceAccessConfigArray{
					&compute.InstanceNetworkInterfaceAccessConfigArgs{
						NatIp: address.Address,
					},
				},
			},
		},
		Metadata: pulumi.StringMap{
			"ssh-keys":       pulumi.Sprintf("tunnel:%s", args.SSHPublicKey),
			"startup-script": pulumi.String(startupScript),
		},
	}, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to create compute instance: %w", err)
	}

	ctx.Export("headscaleEdgeIP", address.Address)

	return &EdgeRelayResult{
		StaticIP: address.Address,
		Instance: instance,
	}, nil
}
