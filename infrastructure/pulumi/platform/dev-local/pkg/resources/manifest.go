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

package resources

import (
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/yaml"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// K8sManifestConfig defines the configuration for a Kubernetes manifest
type K8sManifestConfig struct {
	Name           string
	YAML           string
	RetainOnDelete bool // Keep the object(s) in the cluster when removed from the program
}

// CreateK8sManifest creates a Kubernetes manifest from YAML
func CreateK8sManifest(ctx *pulumi.Context, provider *kubernetes.Provider, config K8sManifestConfig, opts ...pulumi.ResourceOption) (*yaml.ConfigGroup, error) {
	// Add provider to options
	opts = append(opts, pulumi.Provider(provider))
	if config.RetainOnDelete {
		opts = append(opts, pulumi.RetainOnDelete(true))
	}

	// Create the manifest
	return yaml.NewConfigGroup(ctx, config.Name, &yaml.ConfigGroupArgs{
		YAML: []string{config.YAML},
	}, opts...)
}
