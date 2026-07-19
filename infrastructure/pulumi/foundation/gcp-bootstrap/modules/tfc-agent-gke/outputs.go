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

// Mirrors: 0-bootstrap/modules/tfc-agent-gke/outputs.tf in the TF foundation
// — the module's output surface, exposed as fields on the TfcAgentGke
// component resource.

package tfcagentgke

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// TfcAgentGke is the component resource mirroring upstream
// 0-bootstrap/modules/tfc-agent-gke.
type TfcAgentGke struct {
	pulumi.ResourceState

	// KubernetesEndpoint mirrors upstream output "kubernetes_endpoint" (sensitive).
	KubernetesEndpoint pulumi.StringOutput
	// ServiceAccount mirrors upstream output "service_account" (node SA email).
	ServiceAccount pulumi.StringOutput
	// ClusterName mirrors upstream output "cluster_name".
	ClusterName pulumi.StringOutput
	// HubClusterMembershipID mirrors upstream output "hub_cluster_membership_id".
	HubClusterMembershipID pulumi.StringOutput
}
