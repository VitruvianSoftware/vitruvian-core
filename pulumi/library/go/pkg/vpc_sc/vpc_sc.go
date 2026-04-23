/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package vpc_sc

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func GetDefaultRestrictedServices() []string {
	return []string{
		"accessapproval.googleapis.com",
		"adsdatahub.googleapis.com",
		"aiplatform.googleapis.com",
		"alloydb.googleapis.com",
		"analyticshub.googleapis.com",
		"apigee.googleapis.com",
		"apigeeconnect.googleapis.com",
		"artifactregistry.googleapis.com",
		"assuredworkloads.googleapis.com",
		"automl.googleapis.com",
		"baremetalsolution.googleapis.com",
		"batch.googleapis.com",
		"bigquery.googleapis.com",
		"bigquerydatapolicy.googleapis.com",
		"bigquerydatatransfer.googleapis.com",
		"bigquerymigration.googleapis.com",
		"bigqueryreservation.googleapis.com",
		"bigtable.googleapis.com",
		"binaryauthorization.googleapis.com",
		"cloud.googleapis.com",
		"cloudasset.googleapis.com",
		"cloudbuild.googleapis.com",
		"clouddebugger.googleapis.com",
		"clouddeploy.googleapis.com",
		"clouderrorreporting.googleapis.com",
		"cloudfunctions.googleapis.com",
		"cloudkms.googleapis.com",
		"cloudprofiler.googleapis.com",
		"cloudresourcemanager.googleapis.com",
		"cloudscheduler.googleapis.com",
		"cloudsearch.googleapis.com",
		"cloudtrace.googleapis.com",
		"composer.googleapis.com",
		"compute.googleapis.com",
		"confidentialcomputing.googleapis.com",
		"connectgateway.googleapis.com",
		"contactcenterinsights.googleapis.com",
		"container.googleapis.com",
		"containeranalysis.googleapis.com",
		"containerfilesystem.googleapis.com",
		"containerregistry.googleapis.com",
		"containerthreatdetection.googleapis.com",
		"datacatalog.googleapis.com",
		"dataflow.googleapis.com",
		"datafusion.googleapis.com",
		"datamigration.googleapis.com",
		"dataplex.googleapis.com",
		"dataproc.googleapis.com",
		"datastream.googleapis.com",
		"dialogflow.googleapis.com",
		"dlp.googleapis.com",
		"dns.googleapis.com",
		"documentai.googleapis.com",
		"domains.googleapis.com",
		"eventarc.googleapis.com",
		"file.googleapis.com",
		"firebaseappcheck.googleapis.com",
		"firebaserules.googleapis.com",
		"firestore.googleapis.com",
		"gameservices.googleapis.com",
		"gkebackup.googleapis.com",
		"gkeconnect.googleapis.com",
		"gkehub.googleapis.com",
		"healthcare.googleapis.com",
		"iam.googleapis.com",
		"iamcredentials.googleapis.com",
		"iaptunnel.googleapis.com",
		"ids.googleapis.com",
		"integrations.googleapis.com",
		"kmsinventory.googleapis.com",
		"krmapihosting.googleapis.com",
		"language.googleapis.com",
		"lifesciences.googleapis.com",
		"logging.googleapis.com",
		"managedidentities.googleapis.com",
		"memcache.googleapis.com",
		"meshca.googleapis.com",
		"meshconfig.googleapis.com",
		"metastore.googleapis.com",
		"ml.googleapis.com",
		"monitoring.googleapis.com",
		"networkconnectivity.googleapis.com",
		"networkmanagement.googleapis.com",
		"networksecurity.googleapis.com",
		"networkservices.googleapis.com",
		"notebooks.googleapis.com",
		"opsconfigmonitoring.googleapis.com",
		"orgpolicy.googleapis.com",
		"osconfig.googleapis.com",
		"oslogin.googleapis.com",
		"privateca.googleapis.com",
		"pubsub.googleapis.com",
		"pubsublite.googleapis.com",
		"recaptchaenterprise.googleapis.com",
		"recommender.googleapis.com",
		"redis.googleapis.com",
		"retail.googleapis.com",
		"run.googleapis.com",
		"secretmanager.googleapis.com",
		"servicecontrol.googleapis.com",
		"servicedirectory.googleapis.com",
		"spanner.googleapis.com",
		"speakerid.googleapis.com",
		"speech.googleapis.com",
		"sqladmin.googleapis.com",
		"storage.googleapis.com",
		"storagetransfer.googleapis.com",
		"sts.googleapis.com",
		"texttospeech.googleapis.com",
		"timeseriesinsights.googleapis.com",
		"tpu.googleapis.com",
		"trafficdirector.googleapis.com",
		"transcoder.googleapis.com",
		"translate.googleapis.com",
		"videointelligence.googleapis.com",
		"vision.googleapis.com",
		"visionai.googleapis.com",
		"vmmigration.googleapis.com",
		"vpcaccess.googleapis.com",
		"webrisk.googleapis.com",
		"workflows.googleapis.com",
		"workstations.googleapis.com",
	}
}

type VpcServiceControlsArgs struct {
	PolicyID                 pulumi.StringInput
	Prefix                   string
	Members                  []string
	MembersDryRun            []string
	ProjectNumbers           []string
	RestrictedServices       []string
	RestrictedServicesDryRun []string
	Enforce                  bool
	IngressPolicies          accesscontextmanager.ServicePerimeterStatusIngressPolicyArray
	EgressPolicies           accesscontextmanager.ServicePerimeterStatusEgressPolicyArray
	IngressPoliciesDryRun    accesscontextmanager.ServicePerimeterSpecIngressPolicyArray
	EgressPoliciesDryRun     accesscontextmanager.ServicePerimeterSpecEgressPolicyArray
}

type VpcServiceControls struct {
	pulumi.ResourceState
	AccessLevel       *accesscontextmanager.AccessLevel
	AccessLevelDryRun *accesscontextmanager.AccessLevel
	Perimeter         *accesscontextmanager.ServicePerimeter
}

func NewVpcServiceControls(ctx *pulumi.Context, name string, args *VpcServiceControlsArgs, opts ...pulumi.ResourceOption) (*VpcServiceControls, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}

	component := &VpcServiceControls{}
	err := ctx.RegisterComponentResource("pkg:index:VpcServiceControls", name, component, opts...)
	if err != nil {
		return nil, err
	}

	var members pulumi.StringArray
	for _, m := range args.Members {
		members = append(members, pulumi.String(m))
	}

	// Workaround for unknown policy ID during preview:
	alNameInput := args.PolicyID.ToStringOutput().ApplyT(func(pid string) string {
		// handle "organizations/123" input which might not just be a bare ID
		parts := strings.Split(pid, "/")
		id := parts[len(parts)-1]
		return fmt.Sprintf("accessPolicies/%s/accessLevels/alp_%s_members", id, args.Prefix)
	}).(pulumi.StringOutput)

	al, err := accesscontextmanager.NewAccessLevel(ctx, name+"-al", &accesscontextmanager.AccessLevelArgs{
		Parent: args.PolicyID.ToStringOutput().ApplyT(func(pid string) string {
			parts := strings.Split(pid, "/")
			if len(parts) > 1 && parts[0] == "accessPolicies" {
				return pid
			}
			id := parts[len(parts)-1]
			return "accessPolicies/" + id
		}).(pulumi.StringOutput),
		Name:  alNameInput,
		Title: pulumi.String(fmt.Sprintf("%s Access Level", args.Prefix)),
		Basic: &accesscontextmanager.AccessLevelBasicArgs{
			Conditions: accesscontextmanager.AccessLevelBasicConditionArray{
				&accesscontextmanager.AccessLevelBasicConditionArgs{
					Members: members,
				},
			},
		},
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.AccessLevel = al

	var membersDry pulumi.StringArray
	for _, m := range args.MembersDryRun {
		membersDry = append(membersDry, pulumi.String(m))
	}

	alDryRunNameInput := args.PolicyID.ToStringOutput().ApplyT(func(pid string) string {
		parts := strings.Split(pid, "/")
		id := parts[len(parts)-1]
		return fmt.Sprintf("accessPolicies/%s/accessLevels/alp_%s_members_dry_run", id, args.Prefix)
	}).(pulumi.StringOutput)

	alDry, err := accesscontextmanager.NewAccessLevel(ctx, name+"-al-dry", &accesscontextmanager.AccessLevelArgs{
		Parent: args.PolicyID.ToStringOutput().ApplyT(func(pid string) string {
			parts := strings.Split(pid, "/")
			if len(parts) > 1 && parts[0] == "accessPolicies" {
				return pid
			}
			id := parts[len(parts)-1]
			return "accessPolicies/" + id
		}).(pulumi.StringOutput),
		Name:  alDryRunNameInput,
		Title: pulumi.String(fmt.Sprintf("%s Access Level (Dry Run)", args.Prefix)),
		Basic: &accesscontextmanager.AccessLevelBasicArgs{
			Conditions: accesscontextmanager.AccessLevelBasicConditionArray{
				&accesscontextmanager.AccessLevelBasicConditionArgs{
					Members: membersDry,
				},
			},
		},
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.AccessLevelDryRun = alDry

	var resources pulumi.StringArray
	for _, p := range args.ProjectNumbers {
		resources = append(resources, pulumi.String(fmt.Sprintf("projects/%s", p)))
	}

	var svcs pulumi.StringArray
	for _, s := range args.RestrictedServices {
		svcs = append(svcs, pulumi.String(s))
	}

	perimNameInput := args.PolicyID.ToStringOutput().ApplyT(func(pid string) string {
		parts := strings.Split(pid, "/")
		id := parts[len(parts)-1]
		return fmt.Sprintf("accessPolicies/%s/servicePerimeters/sp_%s_default_perimeter", id, args.Prefix)
	}).(pulumi.StringOutput)

	var statusPtr *accesscontextmanager.ServicePerimeterStatusArgs
	if args.Enforce {
		statusPtr = &accesscontextmanager.ServicePerimeterStatusArgs{
			Resources:          resources,
			AccessLevels:       pulumi.StringArray{al.Name},
			RestrictedServices: svcs,
			VpcAccessibleServices: &accesscontextmanager.ServicePerimeterStatusVpcAccessibleServicesArgs{
				EnableRestriction: pulumi.Bool(true),
				AllowedServices:   pulumi.StringArray{pulumi.String("RESTRICTED-SERVICES")},
			},
			IngressPolicies: args.IngressPolicies,
			EgressPolicies:  args.EgressPolicies,
		}
	}

	var svcsDryRun pulumi.StringArray
	for _, s := range args.RestrictedServicesDryRun {
		svcsDryRun = append(svcsDryRun, pulumi.String(s))
	}
	if len(svcsDryRun) == 0 {
		svcsDryRun = svcs
	}

	spec := &accesscontextmanager.ServicePerimeterSpecArgs{
		Resources:          resources,
		AccessLevels:       pulumi.StringArray{alDry.Name},
		RestrictedServices: svcsDryRun,
		VpcAccessibleServices: &accesscontextmanager.ServicePerimeterSpecVpcAccessibleServicesArgs{
			EnableRestriction: pulumi.Bool(true),
			AllowedServices:   pulumi.StringArray{pulumi.String("RESTRICTED-SERVICES")},
		},
		IngressPolicies: args.IngressPoliciesDryRun,
		EgressPolicies:  args.EgressPoliciesDryRun,
	}

	perim, err := accesscontextmanager.NewServicePerimeter(ctx, name+"-perim", &accesscontextmanager.ServicePerimeterArgs{
		Parent: args.PolicyID.ToStringOutput().ApplyT(func(pid string) string {
			parts := strings.Split(pid, "/")
			if len(parts) > 1 && parts[0] == "accessPolicies" {
				return pid
			}
			id := parts[len(parts)-1]
			return "accessPolicies/" + id
		}).(pulumi.StringOutput),
		Name:                  perimNameInput,
		Title:                 pulumi.String(fmt.Sprintf("%s Default Perimeter", args.Prefix)),
		PerimeterType:         pulumi.String("PERIMETER_TYPE_REGULAR"),
		Status:                statusPtr,
		Spec:                  spec,
		UseExplicitDryRunSpec: pulumi.Bool(true),
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Perimeter = perim

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"accessLevelId":       al.ID(),
		"accessLevelDryRunId": alDry.ID(),
		"perimeterId":         perim.ID(),
	})

	return component, nil
}
