package networking

import (
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
)

type VpnHaMock struct{}

func (m VpnHaMock) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "-id", args.Inputs, nil
}

func (m VpnHaMock) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func TestVpnHa(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		mode := "CUSTOM"
		desc := "test-range"
		ike := 2

		_, err := NewVpnHa(ctx, "test-vpn", &VpnHaArgs{
			ProjectID: pulumi.String("test-project"),
			Region:    pulumi.String("us-central1"),
			Network:   pulumi.String("test-net"),
			Name:      "my-vpn",
			RouterAsn: 64514,
			RouterAdvertiseConfig: &RouterAdvertiseConfig{
				Mode:   &mode,
				Groups: []string{"ALL_SUBNETS"},
				IpRanges: []RouterAdvertiseIpRange{
					{
						Range:       "10.0.0.0/24",
						Description: &desc,
					},
				},
			},
			Tunnels: []VpnHaTunnelConfig{
				{
					BgpSessionRange:     "169.254.0.1/30",
					PeerBgpSessionRange: "169.254.0.2/30",
					PeerAsn:             64515,
					SharedSecret:        "secret",
					VpnGatewayInterface: 0,
					IkeVersion:          &ike,
				},
			},
		})
		assert.NoError(t, err)

		return nil
	}, pulumi.WithMocks("project", "stack", VpnHaMock{}))
	assert.NoError(t, err)
}
