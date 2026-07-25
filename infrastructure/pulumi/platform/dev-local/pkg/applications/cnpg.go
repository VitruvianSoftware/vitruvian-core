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
	"encoding/base64"
	"fmt"

	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	kubernetescorev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/yaml"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/dev-local/pkg/resources"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/dev-local/pkg/utils"
)

// CNPGCRDs is a list of all CloudNativePG CRDs - Kept for reference if needed later
var CNPGCRDs = []string{
	"backups.postgresql.cnpg.io",
	"clusterimagecatalog.postgresql.cnpg.io",
	"cluster.postgresql.cnpg.io",
	"database.postgresql.cnpg.io",
	"imagecatalog.postgresql.cnpg.io",
	"pooler.postgresql.cnpg.io",
	"publication.postgresql.cnpg.io",
	"scheduledbackup.postgresql.cnpg.io",
	"subscription.postgresql.cnpg.io",
}

// DeployCloudNativePGOperator installs the CloudNativePG operator Helm chart.
// It returns the Helm release resource and an error if any occurred.
func DeployCloudNativePGOperator(ctx *pulumi.Context, provider *kubernetes.Provider) (pulumi.Resource, error) {
	// Get configuration for the operator
	conf := utils.NewConfig(ctx)
	operatorVersion := conf.GetString("cnpg_operator_version", "0.23.2")
	operatorNamespace := conf.GetString("cnpg_operator_namespace", "cnpg-system")
	haEnabled := conf.GetBool("high_availability_enabled", false)
	replicas := 1
	if haEnabled {
		replicas = 2
	}

	// Phase 1: Deploy CRDs
	cnpgCrds, err := yaml.NewConfigFile(
		ctx, "cnpg-crds",
		&yaml.ConfigFileArgs{
			File: "crds/cnpg.crds.yaml",
		}, pulumi.Provider(provider),
		// Retain on cutover: deleting these CRDs cascade-deletes every CNPG Cluster
		// (the live Postgres data). Must survive cnpg_enabled=false.
		pulumi.RetainOnDelete(true),
	)
	if err != nil {
		return nil, err
	}

	// Deploy CloudNativePG Operator using the common function
	operatorRelease, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "cnpg-operator",                           // Changed name to be specific
		Namespace:       operatorNamespace,                         // Use operator specific namespace
		ChartName:       "cloudnative-pg",                          // This is the correct chart for the operator
		RepositoryURL:   "https://cloudnative-pg.github.io/charts", // Repository URL remains the same
		Version:         operatorVersion,                           // Use operator specific version
		CreateNamespace: true,                                      // Operator needs its namespace
		SkipCRDs:        true,
		ValuesFile:      "cnpg-operator", // Use the renamed values file
		Values: map[string]interface{}{
			"replicaCount": replicas,
			// Hard spread (leader-elected operator). The chart has no PDB
			// support — a raw PodDisruptionBudget is created below.
			"affinity": hostnameAntiAffinity(map[string]interface{}{
				"app.kubernetes.io/name": "cloudnative-pg",
			}),
			"crds": map[string]interface{}{
				"create": false,
			},
		},
		Wait:           false,
		CleanupCRDs:    false, // CRDs managed by Phase 1
		CRDsToCleanup:  CNPGCRDs,
		Timeout:        600,  // Standard timeout
		RetainOnDelete: true, // handed off to ArgoCD (gitops/argocd/platform/cnpg); retain operator + ns
	}, pulumi.DependsOn([]pulumi.Resource{cnpgCrds}))
	if err != nil {
		ctx.Log.Error("Failed to deploy CloudNativePG Operator Helm chart.", &pulumi.LogArgs{Resource: nil})
		return nil, err
	}

	ctx.Log.Info("CloudNativePG Operator Helm chart deployed successfully.", nil)

	// The cloudnative-pg chart exposes no PDB values (verified at 0.23.2);
	// guard the leader-elected operator against drains with a raw PDB.
	if _, err := resources.CreateK8sManifest(ctx, provider, resources.K8sManifestConfig{
		Name:           "cnpg-operator-pdb",
		RetainOnDelete: true, // handed off with the operator
		YAML: `apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: cnpg-operator
  namespace: ` + operatorNamespace + `
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: cloudnative-pg
`,
	}, pulumi.DependsOn([]pulumi.Resource{operatorRelease})); err != nil {
		return nil, err
	}

	// Export CloudNativePG Operator information
	ctx.Export("cnpgOperatorNamespace", pulumi.String(operatorNamespace))

	return operatorRelease, nil
}

// DeployCnpgCluster creates the initial application credentials secret and deploys the CNPG Cluster Helm chart.
// It depends on the successful deployment of the CNPG operator.
// Returns the Helm release resource and an error if any occurred.
func DeployCnpgCluster(ctx *pulumi.Context, provider *kubernetes.Provider, operatorRelease pulumi.Resource) (pulumi.Resource, error) {
	conf := utils.NewConfig(ctx)
	// --- Configuration --- //
	clusterNamespace := conf.GetString("cnpg_cluster_namespace", "cnpg-cluster")
	clusterVersion := conf.GetString("cnpg_cluster_version", "0.2.1")
	appDbName := conf.GetString("cnpg_app_db_name", "app")
	appDbUser := conf.GetString("cnpg_app_db_user", "app_user")

	// Read the app DB password from config (the same key external_secrets.go uses),
	// so it is deterministic and consistent across the stack. Previously this
	// generated a new random password on every run, which made the Secret churn
	// (replace) on every `pulumi up` and diverge from the value external-secrets
	// manages.
	appDbPasswordOutputResult := conf.RequireSecret(ctx, "cnpg_app_db_password")

	// Ensure we have a dependency on the operator being ready
	var dependsOnOperator pulumi.ResourceOption
	if operatorRelease != nil {
		dependsOnOperator = pulumi.DependsOn([]pulumi.Resource{operatorRelease})
	} else {
		// If operator deployment was skipped, we cannot proceed with cluster deployment.
		ctx.Log.Error("Cannot deploy CNPG Cluster: Operator resource is nil (likely disabled or failed).", nil)
		return nil, fmt.Errorf("CNPG operator deployment is required but was not successful")
	}

	// --- Secret Creation --- //
	initialSecretName := "cnpg-initial-app-credentials"
	appCredentialsSecret, err := kubernetescorev1.NewSecret(ctx, initialSecretName, &kubernetescorev1.SecretArgs{
		Metadata: &metav1.ObjectMetaArgs{
			Name:      pulumi.String(initialSecretName),
			Namespace: pulumi.String(clusterNamespace), // Create secret in the cluster namespace
		},
		Type: pulumi.String("kubernetes.io/basic-auth"),
		// base64 `data` (not `stringData`) to avoid Pulumi's perpetual replace diff
		// (the API never returns stringData). The password is a secret config Output,
		// base64-encoded via Apply — secretness is preserved through the Apply.
		Data: pulumi.StringMap{
			"username": pulumi.String(base64.StdEncoding.EncodeToString([]byte(appDbUser))),
			"password": appDbPasswordOutputResult.ApplyT(func(p string) string {
				return base64.StdEncoding.EncodeToString([]byte(p))
			}).(pulumi.StringOutput),
		},
	}, pulumi.Provider(provider), dependsOnOperator, pulumi.RetainOnDelete(true)) // Depend on operator; retain on cutover (the cnpg Cluster reads this secret)
	if err != nil {
		return nil, fmt.Errorf("failed to create CNPG initial app credentials secret: %w", err)
	}

	// --- Helm Chart Deployment --- //
	// The cluster Helm chart requires the operator and the credentials secret to exist first.
	clusterDependsOn := []pulumi.Resource{appCredentialsSecret, operatorRelease}

	clusterRelease, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "cnpg-cluster",                            // Specific name for the cluster release
		Namespace:       clusterNamespace,                          // Deploy into the cluster namespace
		ChartName:       "cluster",                                 // Use the 'cluster' chart from the CNPG repo
		RepositoryURL:   "https://cloudnative-pg.github.io/charts", // Same repo URL as operator
		Version:         clusterVersion,                            // Use cluster specific version
		CreateNamespace: true,                                      // Ensure the cluster namespace exists
		RetainOnDelete:  true,                                      // handed off to ArgoCD (gitops/argocd/platform/cnpg-cluster); retain Cluster + PVCs (Postgres data) + ns
		ValuesFile:      "cnpg-cluster",                            // Use the new values file
		Values: map[string]interface{}{ // Dynamic values mirroring Terraform template
			"cluster": map[string]interface{}{
				// Spread instances 1-per-node so a single node loss can't take the
				// whole DB down. hostname (nodes have no zone label, so the chart
				// default topology.kubernetes.io/zone is a no-op). Mirrors the live
				// gitops cnpg-cluster AppSet + grafana.go. NOTE: hostnameAntiAffinity()
				// is the OPERATOR helper — the cluster takes a CNPG AffinityConfiguration.
				// See docs/operations/incidents/2026-06-21-fedora-freeze-cluster-cascade.md
				"affinity": map[string]interface{}{
					"topologyKey": "kubernetes.io/hostname",
				},
				"initdb": map[string]interface{}{
					"database": appDbName,
					"owner":    appDbUser, // Owner derived from secret
					"secret": map[string]interface{}{
						"name": initialSecretName, // Reference the created secret
					},
				},
			},
		},
		Wait:    false, // Changed from true based on Terraform (wait = false)
		Timeout: 600,   // Standard timeout
	}, pulumi.DependsOn(clusterDependsOn))
	if err != nil {
		ctx.Log.Error(fmt.Sprintf("Failed to deploy CNPG Cluster Helm chart %s", "cnpg-cluster"), &pulumi.LogArgs{Resource: clusterRelease})
		return nil, err
	}

	ctx.Log.Info(fmt.Sprintf("CNPG Cluster Helm chart %s deployed successfully", "cnpg-cluster"), nil)

	// Export Cluster Information
	ctx.Export("cnpgClusterNamespace", pulumi.String(clusterNamespace))
	ctx.Export("cnpgInitialAppSecretName", appCredentialsSecret.Metadata.Name())

	return clusterRelease, nil
}
