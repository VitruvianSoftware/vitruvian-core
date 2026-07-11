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

// Package hierarchical_firewall_policy is the Pulumi port of upstream
// terraform-example-foundation 3-networks-hub-and-spoke/modules/
// hierarchical_firewall_policy. It creates the org/folder-level hierarchical
// firewall policy and associates it with the foundation folders (hub only).
package hierarchical_firewall_policy

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// Args are the inputs to the hierarchical firewall policy module.
type Args struct {
	ParentID      string
	Associations  []string // foundation folders; defaults to [ParentID] when empty
	EnableLogging bool
}

// New creates the hierarchical firewall policy. Mirrors upstream, associating
// the policy with the foundation folders (common, network, bootstrap, dev,
// prod, nonprod).
func New(ctx *pulumi.Context, args *Args) error {
	associations := args.Associations
	if len(associations) == 0 {
		associations = []string{args.ParentID}
	}
	_, err := networking.NewHierarchicalFirewallPolicy(ctx, "hierarchical-fw", &networking.HierarchicalFirewallPolicyArgs{
		ParentID:      pulumi.String(args.ParentID),
		ShortName:     "fw-hub-svpc-hierarchical",
		Description:   "Hierarchical firewall rules for hub-and-spoke foundation",
		Associations:  associations,
		EnableLogging: args.EnableLogging,
	})
	return err
}
