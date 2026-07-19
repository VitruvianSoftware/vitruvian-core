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

// Mirrors: 0-bootstrap/modules/gitlab-oidc/variables.tf in the TF foundation
// — the module's input surface and defaults.

package gitlaboidc

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// defaultServiceList mirrors upstream var.service_list.
var defaultServiceList = []string{
	"iam.googleapis.com",
	"cloudresourcemanager.googleapis.com",
	"sts.googleapis.com",
	"iamcredentials.googleapis.com",
}

// defaultAttributeMapping mirrors upstream var.attribute_mapping (GitLab
// standard + custom claims).
var defaultAttributeMapping = map[string]string{
	// Principal IAM
	"google.subject": "assertion.sub",
	// standard claims
	"attribute.sub": "attribute.sub",
	"attribute.iss": "attribute.iss",
	"attribute.aud": "attribute.aud",
	"attribute.exp": "attribute.exp",
	"attribute.nbf": "attribute.nbf",
	"attribute.iat": "attribute.iat",
	"attribute.jti": "attribute.jti",
	// GitLab custom claims
	"attribute.namespace_id":   "assertion.namespace_id",
	"attribute.namespace_path": "assertion.namespace_path",
	"attribute.project_id":     "assertion.project_id",
	"attribute.project_path":   "assertion.project_path",
	"attribute.user_id":        "assertion.user_id",
	"attribute.user_login":     "assertion.user_login",
	"attribute.user_email":     "assertion.user_email",
}

// SAMappingEntry mirrors one entry of upstream var.sa_mapping: a service
// account resource name and the WIF provider attribute granted access to it.
// If Attribute is set to `*` all identities in the pool are granted access.
type SAMappingEntry struct {
	SAName    pulumi.StringInput // full SA resource name (projects/.../serviceAccounts/...)
	Attribute string             // e.g. "attribute.project_path/my-org/my-repo" or "*"
}

// GitlabOidcArgs mirrors upstream variables.tf.
type GitlabOidcArgs struct {
	// ProjectID is the project in which to create the Workload Identity Pool.
	ProjectID pulumi.StringInput
	// ServiceList is the set of Google Cloud APIs required for the project.
	// Defaults to iam, cloudresourcemanager, sts and iamcredentials.
	ServiceList []string
	// PoolID is the Workload Identity Pool ID.
	PoolID string
	// PoolDisplayName is the optional Workload Identity Pool display name.
	PoolDisplayName string
	// PoolDescription defaults to "Workload Identity Pool managed by Pulumi".
	PoolDescription string
	// ProviderID is the Workload Identity Pool Provider ID.
	ProviderID string
	// IssuerURI defaults to "https://gitlab.com".
	IssuerURI string
	// ProviderDisplayName is the optional provider display name.
	ProviderDisplayName string
	// ProviderDescription defaults to "Workload Identity Pool Provider managed by Pulumi".
	ProviderDescription string
	// AttributeCondition is the optional provider attribute condition expression.
	AttributeCondition pulumi.StringInput
	// AttributeMapping defaults to the GitLab claim mapping (see
	// defaultAttributeMapping), mirroring upstream var.attribute_mapping.
	AttributeMapping map[string]string
	// AllowedAudiences is the optional list of provider allowed audiences.
	AllowedAudiences []string
	// SAMapping maps arbitrary keys to service accounts + provider attributes.
	SAMapping map[string]SAMappingEntry
}
