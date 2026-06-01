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
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/resources"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/utils"
)

// DeployDatabase sets up a PostgreSQL database
func DeployDatabase(ctx *pulumi.Context, provider *kubernetes.Provider) error {
	// Get configuration
	conf := utils.NewConfig(ctx)
	enabled := conf.GetBool("database_enabled", true)

	if !enabled {
		ctx.Log.Info("Database is disabled, skipping deployment", nil)
		return nil
	}

	// Create namespace
	namespace := conf.GetString("database:namespace", "database")
	ns, err := resources.CreateK8sNamespace(ctx, provider, resources.K8sNamespaceConfig{
		Name: namespace,
	})

	if err != nil {
		return err
	}

	// Deploy PostgreSQL
	_, err = resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "postgresql",
		Namespace:       namespace,
		ChartName:       "postgresql",
		RepositoryURL:   "https://charts.bitnami.com/bitnami",
		Version:         "12.5.7",
		CreateNamespace: false,
		Values: map[string]interface{}{
			"auth": map[string]interface{}{
				"username":         "postgres",
				"password":         "postgres",
				"database":         "postgres",
				"postgresPassword": "postgres",
			},
			"primary": map[string]interface{}{
				"persistence": map[string]interface{}{
					"enabled": true,
					"size":    "1Gi",
				},
				"resources": map[string]interface{}{
					"requests": map[string]interface{}{
						"cpu":    "100m",
						"memory": "256Mi",
					},
				},
			},
		},
		Wait:    true,
		Timeout: 300,
	}, pulumi.DependsOn([]pulumi.Resource{ns}))

	// Export database connection information
	ctx.Export("databaseNamespace", pulumi.String(namespace))
	ctx.Export("databaseHost", pulumi.String("postgresql."+namespace+".svc.cluster.local"))
	ctx.Export("databasePort", pulumi.Int(5432))
	ctx.Export("databaseUsername", pulumi.String("postgres"))
	ctx.Export("databasePassword", pulumi.String("postgres"))
	ctx.Export("databaseName", pulumi.String("postgres"))

	return err
}
