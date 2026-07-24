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

package main

import (
	"encoding/json"
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp"
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/billing"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/accounts/personal/modules/cloud_build"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/accounts/personal/modules/cloud_run"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/accounts/personal/modules/iam"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/accounts/personal/modules/project_api_services"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/accounts/personal/modules/secret_manager"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/accounts/personal/modules/service_accounts"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/accounts/personal/modules/storage"
)

const (
	projectID = "personal-llc"
	userEmail = "james.nguyen@gmail.com" // Replace with your actual email
	gcpRegion = "us-central1"            // Example region, adjust as needed
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		// Create a GCP provider instance, explicitly targeting the 'personal-llc' project.
		_, err := gcp.NewProvider(ctx, "gcp-provider", &gcp.ProviderArgs{
			Project: pulumi.String(projectID),
		})
		if err != nil {
			return err
		}

		// 1. Enable required API services
		enabledAPIServices, err := project_api_services.EnableAPIServices(ctx, "personal-llc-apis", &project_api_services.EnableAPIServicesArgs{
			ProjectID: projectID,
			Services: []string{
				"cloudapis.googleapis.com",
				"compute.googleapis.com",
				"iam.googleapis.com",
				"secretmanager.googleapis.com",
				"cloudbuild.googleapis.com",
				"artifactregistry.googleapis.com",
				"run.googleapis.com",
				"storage.googleapis.com", // Required for the storage bucket
			},
		})
		if err != nil {
			return err
		}

		// 2. Create a Cloud Storage bucket using the storage module.
		_, err = storage.CreateBucket(ctx, "personal-llc-bucket", &storage.CreateBucketArgs{
			ProjectID:  projectID,
			NamePrefix: "personal-llc",
			Location:   "US", // Buckets are global, but location can be specified for data residency
		})
		if err != nil {
			return err
		}

		// 3. Create a service account and grant roles
		_, err = service_accounts.CreateServiceAccount(ctx, "personal-llc-sa", &service_accounts.CreateServiceAccountArgs{
			ProjectID:   projectID,
			AccountID:   "personal-llc-builder",
			DisplayName: "Personal LLC Builder Service Account",
			Roles: []string{
				"roles/editor", // Grant editor role for broad access for prototyping
			},
		})
		if err != nil {
			return err
		}

		// 3.1. Create a service account and grant roles
		// https://cloud.google.com/iam/docs/roles-permissions
		_, err = service_accounts.CreateServiceAccount(ctx, "personal-llc-app-sa", &service_accounts.CreateServiceAccountArgs{
			ProjectID:   projectID,
			AccountID:   "personal-llc-app",
			DisplayName: "Personal LLC Application Service Account",
			Roles: []string{
				"roles/editor", // Grant editor role for broad access for prototyping
				"roles/artifactregistry.writer",
				"roles/run.admin",
				"roles/logging.logWriter",
				"roles/secretmanager.secretAccessor",
				"roles/iam.serviceAccountUser",
			},
		})
		if err != nil {
			return err
		}

		// Also try project-scoped config for pulumi_lab_gmail
		projCfg := config.New(ctx, "pulumi_lab_gmail")

		// 4. Create secrets from config
		var secrets []struct {
			Name string `json:"name"`
		}
		projCfg.GetObject("secrets", &secrets)

		for _, secretConfig := range secrets {
			_, err = secret_manager.CreateSecret(ctx, projectID, secretConfig.Name)
			if err != nil {
				return err
			}
		}

		// 5. Grant IAM roles to the user
		err = iam.GrantIAMRole(ctx, "personal-llc-viewer", &iam.GrantIAMRoleArgs{
			ProjectID: projectID,
			Member:    "user:" + userEmail,
			Role:      "roles/viewer", // Grant viewer role to your personal email
		})
		if err != nil {
			return err
		}

		// 5b. Cross-account billing grant.
		// James funds the Vitruvian foundation's bu1/bu2 projects from this PERSONAL
		// billing account (008CAA-C364C4-B29B67). For that to work, the Vitruvian
		// projects-stage service account (sa-terraform-proj, which the gcp-projects
		// stage runs as) needs roles/billing.user on this account so it can associate
		// the bu1/bu2 projects with it. The grant lives HERE, in the personal-account
		// stack, because only this stack's identity (james.nguyen@gmail.com) admins the
		// billing account — the Vitruvian foundation SAs cannot grant IAM on it. This
		// stack must apply BEFORE gcp-projects re-links bu1/bu2 (which reads the new
		// billing_account from its leaf yamls).
		_, err = billing.NewAccountIamMember(ctx, "vitruvian-proj-sa-billing-user", &billing.AccountIamMemberArgs{
			BillingAccountId: pulumi.String("008CAA-C364C4-B29B67"),
			Role:             pulumi.String("roles/billing.user"),
			Member:           pulumi.String("serviceAccount:sa-terraform-proj@prj-b-seed-c010.iam.gserviceaccount.com"),
		})
		if err != nil {
			return err
		}

		// 6. Configure Cloud Build (placeholder for now, will write cloudbuild.yaml directly)
		err = cloud_build.ConfigureCloudBuild(ctx, "personal-llc-cloudbuild", &cloud_build.CloudBuildArgs{
			ProjectID: projectID,
			// RepoURL: "https://github.com/your-repo/your-project", // Uncomment and set if using triggers
		})
		if err != nil {
			return err
		}

		// 7. Deploy a Cloud Run service, explicitly depending on the Cloud Run API being enabled.
		// Provide a CustomDomain so the service will be mapped to my-first-service.run.ipv1337.dev
		// Read Cloudflare zone ID and proxied flag from Pulumi config (optional)
		pulCfg := config.New(ctx, "")
		cfZone := pulCfg.Get("cloudflare:zoneId")
		if cfZone == "" {
			cfZone = projCfg.Get("cloudflare:zoneId")
		}
		cfProxied, _ := pulCfg.TryBool("cloudflare:proxied")
		customDomain := pulCfg.Get("customDomain")

		// (Removed verbose debug exports; rely on module outputs.)

		deployArgs := &cloud_run.DeployServiceArgs{
			ProjectID:         projectID,
			ServiceName:       "hello",
			ImageName:         "gcr.io/cloudrun/hello", // Example image
			Location:          gcpRegion,
			CloudflareZoneID:  cfZone,
			CloudflareProxied: cfProxied,
		}
		if customDomain != "" {
			deployArgs.CustomDomain = customDomain
		}

		_, err = cloud_run.DeployService(ctx, "personal-llc-cloudrun", deployArgs, pulumi.DependsOn([]pulumi.Resource{enabledAPIServices["run.googleapis.com"]}))
		if err != nil {
			return err
		}

		// Multi-service deployment pattern: optional config key "multiServices" containing JSON array.
		// Example value:
		// [
		//   {"name":"api","image":"gcr.io/cloudrun/hello","customDomain":"api.run.ipv1337.dev"},
		//   {"name":"worker","image":"gcr.io/cloudrun/hello"}
		// ]
		msRaw := pulCfg.Get("multiServices")
		if msRaw != "" {
			var svcDefs []struct {
				Name         string            `json:"name"`
				Image        string            `json:"image"`
				CustomDomain string            `json:"customDomain"`
				Region       string            `json:"region"`
				Env          map[string]string `json:"env"`
			}
			if err := json.Unmarshal([]byte(msRaw), &svcDefs); err != nil {
				return fmt.Errorf("failed to parse multiServices JSON: %w", err)
			}
			for _, def := range svcDefs {
				if def.Name == "" || def.Image == "" {
					return fmt.Errorf("multiServices entries must include at least 'name' and 'image'")
				}
				region := def.Region
				if region == "" {
					region = gcpRegion
				}
				msArgs := &cloud_run.DeployServiceArgs{
					ProjectID:         projectID,
					ServiceName:       def.Name,
					ImageName:         def.Image,
					Location:          region,
					CloudflareZoneID:  cfZone,
					CloudflareProxied: cfProxied,
					Env:               def.Env,
				}
				if def.CustomDomain != "" {
					msArgs.CustomDomain = def.CustomDomain
				}
				// Resource name prefix ensures uniqueness per service definition.
				_, err := cloud_run.DeployService(ctx, fmt.Sprintf("personal-llc-%s-cloudrun", def.Name), msArgs, pulumi.DependsOn([]pulumi.Resource{enabledAPIServices["run.googleapis.com"]}))
				if err != nil {
					return err
				}
			}
		}

		return nil
	})
}
