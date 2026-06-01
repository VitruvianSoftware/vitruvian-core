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

package applications

import (
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/resources"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/utils"
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	corev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// DeployRedis deploys the Bitnami Redis Helm chart for both Istio rate limiting and application usage
func DeployRedis(ctx *pulumi.Context, provider *kubernetes.Provider) (pulumi.Resource, error) {
	// Use config utils implementation
	cfg := utils.NewConfig(ctx)

	// Generate random Redis password
	redisPasswordResult := pulumi.String(utils.GenerateRandomPassword(16))

	// Create secret for Redis password
	redisSecret, err := corev1.NewSecret(ctx, "redis-password-secret", &corev1.SecretArgs{
		Metadata: &metav1.ObjectMetaArgs{
			Name:      pulumi.String("redis-password"),
			Namespace: pulumi.String("redis"),
		},
		StringData: pulumi.StringMap{
			"redis-password": redisPasswordResult,
		},
	}, pulumi.Provider(provider))
	if err != nil {
		return nil, err
	}

	// Create Redis chart resource using the resources package
	return resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "redis",
		ChartName:       "redis",
		Version:         cfg.GetString("redis_version", "18.19.1"),
		RepositoryURL:   "https://charts.bitnami.com/bitnami",
		Namespace:       "redis",
		CreateNamespace: true,
		ValuesFile:      "redis", // Will load values/redis.yaml
		// Only override values that come from configuration
		Values: map[string]interface{}{
			"auth": map[string]interface{}{
				"existingSecret":            "redis-password",
				"existingSecretPasswordKey": "redis-password",
			},
		},
		Wait:    true,
		Timeout: 1200,
	}, pulumi.DependsOn([]pulumi.Resource{redisSecret})) // End of DeployRedis
}
