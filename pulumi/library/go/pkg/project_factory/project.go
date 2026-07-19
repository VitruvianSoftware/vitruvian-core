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

package project_factory

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/billing"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/resourcemanager"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// BudgetConfig configures a billing budget alert for the project.
// When provided (non-nil), a google_billing_budget resource is created,
// matching the TF project-factory budget module behavior.
type BudgetConfig struct {
	// Amount is the budget amount in the billing account's currency (e.g. USD).
	Amount float64
	// AlertSpentPercents is a list of percentages at which to alert.
	// Defaults to [0.5, 0.7, 1.0] if empty.
	AlertSpentPercents []float64
	// AlertPubSubTopic is an optional Pub/Sub topic for budget notifications,
	// in the form "projects/{project_id}/topics/{topic_id}".
	AlertPubSubTopic string
	// AlertSpendBasis is the type of basis: "CURRENT_SPEND" or "FORECASTED_SPEND".
	// Defaults to "CURRENT_SPEND".
	AlertSpendBasis string
}

// ProjectArgs configures the Project component.
// ActivateApis is a plain []string (not a Pulumi Input) because API names are
// always known at plan time. This ensures each projects.Service resource is
// properly registered in the Pulumi state graph — NOT created inside an
// ApplyT callback where errors are silently swallowed and resources are
// invisible to the engine.
type ProjectArgs struct {
	ProjectID         pulumi.StringInput
	Name              pulumi.StringInput
	FolderID          pulumi.StringInput
	BillingAccount    pulumi.StringInput
	ActivateApis      []string // plain Go slice — always known at plan time
	AutoCreateNetwork pulumi.BoolPtrInput
	Labels            pulumi.StringMapInput
	DeletionPolicy    pulumi.StringPtrInput

	// SAExecutors is a list of Service Account short names (e.g., "sa-terraform-bootstrap").
	// Each is CREATED in this project and granted roles/serviceusage.serviceUsageAdmin
	// on it, so that later applies running AS that SA (the CI/CD executor) can manage
	// this project's Service resources. Cold-deploy ordering is strictly:
	//   project -> ActivateApis Services (+ propagation wait) -> SA -> SUA grant.
	// The first apply's deployer is the project creator (and therefore owner), so it
	// never needs the grant to enable APIs itself; the grant only has to exist before
	// the NEXT apply runs as the executor SA. iam.googleapis.com is auto-appended to
	// ActivateApis because creating an SA in a fresh project requires it.
	SAExecutors []string

	// RandomProjectID appends a 4-character random hex suffix to ProjectID,
	// matching the upstream Terraform Example Foundation's use of the
	// project-factory module's random_project_id feature. The suffix is
	// generated once via a random.RandomId resource and persisted in Pulumi
	// state, so subsequent runs are idempotent. Example: "prj-b-seed-a1b2".
	RandomProjectID bool

	// Budget configures a billing budget alert for this project.
	// When nil, no budget is created. Mirrors the TF project-factory
	// budget_amount / budget_alert_* variables.
	Budget *BudgetConfig

	// DefaultServiceAccount controls the project's default service account.
	// Valid values: "delete", "deprivilege", "disable", or "keep" (default).
	// Mirrors the TF project-factory default_service_account variable.
	DefaultServiceAccount string

	// Lien adds a lien on the project to prevent accidental deletion.
	// Mirrors the TF project-factory lien variable.
	Lien bool

	// ApiPropagationSeconds inserts a delay after the project's APIs are enabled
	// (ActivateApis) before ApisReady resolves. A freshly-enabled GCP API is not
	// immediately usable — resources created against it can fail with
	// "API ... enabled recently, wait a few minutes and retry". Consumers that
	// create resources using those APIs should `DependsOn(project.ApisReady)`.
	// Mirrors the upstream Terraform foundation's `time_sleep` after
	// project_services. 0 (default) inserts no delay.
	ApiPropagationSeconds int

	// DisableServicesOnDestroy controls whether the ActivateApis services are
	// DISABLED when the Service resource / project is torn down, and whether their
	// dependent services are disabled with them. Upstream project-factory defaults
	// BOTH to true; we default to FALSE (nil) as a Pulumi destroy-safety stance —
	// disabling a service on teardown can cascade into dependent projects and is
	// rarely wanted during a `pulumi destroy`. Set true to match upstream exactly.
	DisableServicesOnDestroy *bool
}

type Project struct {
	pulumi.ResourceState
	Project  *organizations.Project
	Services []*projects.Service
	// ApisReady resolves only after ActivateApis are enabled AND (if
	// ApiPropagationSeconds > 0) the propagation delay has elapsed. DependsOn it
	// for resources that use the just-enabled APIs. Never nil, but note: when
	// ApiPropagationSeconds is 0 it falls back to the project itself and does NOT
	// gate on the Service resources — belt-and-braces consumers should DependsOn
	// the Services slice as well (or simply set ApiPropagationSeconds > 0).
	ApisReady pulumi.Resource
	// SAExecutorAccounts are the executor service accounts created for
	// args.SAExecutors, in the same order.
	SAExecutorAccounts []*serviceaccount.Account
}

func NewProject(ctx *pulumi.Context, name string, args *ProjectArgs, opts ...pulumi.ResourceOption) (*Project, error) {
	component := &Project{}
	err := ctx.RegisterComponentResource("pkg:index:Project", name, component, opts...)
	if err != nil {
		return nil, err
	}

	// Default to false for autoCreateNetwork — security best practice:
	// the default VPC has overly permissive firewall rules.
	autoCreateNetwork := args.AutoCreateNetwork
	if autoCreateNetwork == nil {
		autoCreateNetwork = pulumi.Bool(false)
	}

	// Determine the effective project ID. When RandomProjectID is true,
	// a 4-character hex suffix is appended (2 bytes = 4 hex chars), matching
	// the upstream terraform-google-project-factory random_id configuration.
	var projectID pulumi.StringInput
	var projectName pulumi.StringInput
	if args.RandomProjectID {
		suffix, err := random.NewRandomId(ctx, fmt.Sprintf("%s-suffix", name), &random.RandomIdArgs{
			ByteLength: pulumi.Int(2),
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}
		projectID = pulumi.All(args.ProjectID, suffix.Hex).ApplyT(func(vals []interface{}) string {
			return fmt.Sprintf("%s-%s", vals[0], vals[1])
		}).(pulumi.StringOutput)
		// Keep the display name without the suffix for readability, matching
		// upstream behavior where name != project_id.
		projectName = args.Name
	} else {
		projectID = args.ProjectID
		projectName = args.Name
	}

	// 1. Create the Project
	pArgs := &organizations.ProjectArgs{
		ProjectId:         projectID,
		Name:              projectName,
		FolderId:          args.FolderID,
		BillingAccount:    args.BillingAccount,
		AutoCreateNetwork: autoCreateNetwork,
		Labels:            args.Labels,
	}

	if args.DeletionPolicy != nil {
		pArgs.DeletionPolicy = args.DeletionPolicy
	}

	p, err := organizations.NewProject(ctx, name, pArgs, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Project = p

	// 2. Enable APIs — each Service is a first-class Pulumi resource,
	// properly tracked in state with correct dependency ordering. On a cold
	// deploy the deployer is the project creator (and therefore owner), so it
	// can always enable services itself — nothing may be ordered BEFORE the
	// Services, or a from-empty apply deadlocks on resources (SAs, bindings)
	// that themselves need a freshly-enabled API.
	svcOpts := []pulumi.ResourceOption{pulumi.Parent(p)}

	// Auto-enable billingbudgets.googleapis.com whenever a Budget is requested —
	// the google_billing_budget created below needs that API on. Upstream
	// project-factory appends it to activate_apis for exactly this reason; doing
	// it here means a caller who sets Budget can never forget the API.
	activateApis := append([]string{}, args.ActivateApis...)
	if args.Budget != nil {
		activateApis = appendIfMissing(activateApis, "billingbudgets.googleapis.com")
	}
	// Auto-enable iam.googleapis.com whenever executor SAs are requested
	// (creating a service account in a fresh project requires the IAM API) or
	// the default service account is managed (disable/delete/deprivilege calls
	// the IAM API on this project).
	if len(args.SAExecutors) > 0 ||
		(args.DefaultServiceAccount != "" && strings.ToUpper(args.DefaultServiceAccount) != "KEEP") {
		activateApis = appendIfMissing(activateApis, "iam.googleapis.com")
	}

	// disable-on-destroy: default false (Pulumi destroy-safety), override via arg.
	disableOnDestroy := false
	if args.DisableServicesOnDestroy != nil {
		disableOnDestroy = *args.DisableServicesOnDestroy
	}

	for _, api := range activateApis {
		svc, err := projects.NewService(ctx, fmt.Sprintf("%s-%s", name, api), &projects.ServiceArgs{
			Project:                  p.ProjectId,
			Service:                  pulumi.String(api),
			DisableOnDestroy:         pulumi.Bool(disableOnDestroy),
			DisableDependentServices: pulumi.Bool(disableOnDestroy),
		}, svcOpts...)
		if err != nil {
			return nil, err
		}
		component.Services = append(component.Services, svc)
	}

	// 2b. API propagation wait — a freshly-enabled API is not immediately usable,
	// so resources created against it can fail with "API ... enabled recently,
	// wait a few minutes and retry". When ApiPropagationSeconds > 0, block on a
	// local sleep that depends on all Services; ApisReady is that gate (consumers
	// DependsOn it). Mirrors the upstream foundation's time_sleep. Falls back to
	// the project itself when there is nothing to wait for.
	component.ApisReady = p
	if args.ApiPropagationSeconds > 0 && len(component.Services) > 0 {
		svcDeps := make([]pulumi.Resource, len(component.Services))
		for i, s := range component.Services {
			svcDeps[i] = s
		}
		wait, err := local.NewCommand(ctx, name+"-apis-propagation", &local.CommandArgs{
			Create: pulumi.Sprintf("sleep %d", args.ApiPropagationSeconds),
			// Re-run the wait if the set of enabled APIs changes.
			Triggers: pulumi.Array{pulumi.String(strings.Join(activateApis, ","))},
		}, pulumi.Parent(p), pulumi.DependsOn(svcDeps))
		if err != nil {
			return nil, err
		}
		component.ApisReady = wait
	}

	// apisGate collects everything a consumer of the freshly-enabled APIs must
	// wait on: every Service resource plus the propagation wait (ApisReady falls
	// back to the project when no wait is configured, so the Services are listed
	// explicitly — belt and braces).
	apisGate := make([]pulumi.Resource, 0, len(component.Services)+1)
	for _, s := range component.Services {
		apisGate = append(apisGate, s)
	}
	apisGate = append(apisGate, component.ApisReady)

	// 2c. Executor Service Accounts + Service Usage Admin grants.
	// Each executor SA is created IN this project and granted SUA on it so that
	// FUTURE applies running as that SA (the CI/CD executor) can manage this
	// project's Service resources. Strict cold-deploy ordering:
	//   Services (+ propagation) -> SA -> SUA grant
	// The SA must come after iam.googleapis.com is enabled+propagated (creating
	// an SA in a fresh project fails otherwise), and the grant must come after
	// the SA exists (GCP rejects IAM members for nonexistent service accounts).
	for _, saName := range args.SAExecutors {
		sa, err := serviceaccount.NewAccount(ctx, fmt.Sprintf("%s-sa-%s", name, saName), &serviceaccount.AccountArgs{
			Project:   p.ProjectId,
			AccountId: pulumi.String(saName),
			// The consuming stack may also manage this SA (e.g. the foundation's
			// granular-SA module) — tolerate either creation order.
			CreateIgnoreAlreadyExists: pulumi.Bool(true),
		}, pulumi.Parent(p),
			// SA creation needs iam.googleapis.com enabled+propagated on the
			// fresh project (auto-appended to ActivateApis above).
			pulumi.DependsOn(apisGate),
			// Shared ownership: never delete the underlying SA out from under a
			// consuming stack that also references it.
			pulumi.RetainOnDelete(true))
		if err != nil {
			return nil, err
		}
		component.SAExecutorAccounts = append(component.SAExecutorAccounts, sa)

		member := sa.Email.ApplyT(func(email string) string {
			return fmt.Sprintf("serviceAccount:%s", email)
		}).(pulumi.StringOutput)

		if _, err := projects.NewIAMMember(ctx, fmt.Sprintf("%s-sua-%s", name, saName), &projects.IAMMemberArgs{
			Project: p.ProjectId,
			Role:    pulumi.String("roles/serviceusage.serviceUsageAdmin"),
			Member:  member,
		}, pulumi.Parent(p),
			// The grant references the SA by email — it must never race the SA's
			// creation (the member email also flows from sa.Email, but keep the
			// edge explicit).
			pulumi.DependsOn([]pulumi.Resource{sa})); err != nil {
			return nil, err
		}
	}

	// 3. Budget alert — conditionally created when BudgetConfig is provided.
	// Mirrors the TF project-factory's budget sub-module:
	// creates a google_billing_budget with threshold rules per percent.
	if args.Budget != nil {
		if err := createBudget(ctx, name, p, args, component, apisGate); err != nil {
			return nil, err
		}
	}

	// 4. Default Service Account management — mirrors TF's
	// google_project_default_service_accounts resource.
	if args.DefaultServiceAccount != "" && strings.ToUpper(args.DefaultServiceAccount) != "KEEP" {
		if _, err := projects.NewDefaultServiceAccounts(ctx, fmt.Sprintf("%s-default-sa", name), &projects.DefaultServiceAccountsArgs{
			Project:       p.ProjectId,
			Action:        pulumi.String(strings.ToUpper(args.DefaultServiceAccount)),
			RestorePolicy: pulumi.String("REVERT_AND_IGNORE_FAILURE"),
			// Disabling/deleting the default SAs calls the IAM API on the fresh
			// project — wait for API enablement AND propagation, not just the
			// Service resources.
		}, pulumi.Parent(component), pulumi.DependsOn(apisGate)); err != nil {
			return nil, err
		}
	}

	// 5. Project lien — prevents accidental project deletion.
	if args.Lien {
		if _, err := resourcemanager.NewLien(ctx, fmt.Sprintf("%s-lien", name), &resourcemanager.LienArgs{
			Parent: p.Number.ApplyT(func(n string) string {
				return fmt.Sprintf("projects/%s", n)
			}).(pulumi.StringOutput),
			Restrictions: pulumi.StringArray{pulumi.String("resourcemanager.projects.delete")},
			Origin:       pulumi.String("project-factory"),
			Reason:       pulumi.String("Project Factory lien"),
		}, pulumi.Parent(component)); err != nil {
			return nil, err
		}
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"projectId": p.ProjectId,
	})

	return component, nil
}

// createBudget creates a google_billing_budget for the project. apisGate is
// the API-enablement gate (Services + propagation wait) — the budget must not
// race the auto-enabled billingbudgets.googleapis.com.
func createBudget(ctx *pulumi.Context, name string, p *organizations.Project, args *ProjectArgs, component *Project, apisGate []pulumi.Resource) error {
	budget := args.Budget

	// Apply defaults matching TF project-factory
	alertPercents := budget.AlertSpentPercents
	if len(alertPercents) == 0 {
		alertPercents = []float64{0.5, 0.7, 1.0}
	}
	spendBasis := budget.AlertSpendBasis
	if spendBasis == "" {
		spendBasis = "CURRENT_SPEND"
	}

	// Build threshold rules
	thresholdRules := make(billing.BudgetThresholdRuleArray, len(alertPercents))
	for i, pct := range alertPercents {
		thresholdRules[i] = &billing.BudgetThresholdRuleArgs{
			ThresholdPercent: pulumi.Float64(pct),
			SpendBasis:       pulumi.String(spendBasis),
		}
	}

	budgetArgs := &billing.BudgetArgs{
		BillingAccount: args.BillingAccount,
		DisplayName: p.ProjectId.ApplyT(func(id string) string {
			return fmt.Sprintf("Budget For %s", id)
		}).(pulumi.StringOutput),
		Amount: &billing.BudgetAmountArgs{
			SpecifiedAmount: &billing.BudgetAmountSpecifiedAmountArgs{
				Units: pulumi.String(fmt.Sprintf("%d", int(budget.Amount))),
			},
		},
		BudgetFilter: &billing.BudgetBudgetFilterArgs{
			Projects: pulumi.StringArray{
				p.Number.ApplyT(func(n string) string {
					return fmt.Sprintf("projects/%s", n)
				}).(pulumi.StringOutput),
			},
		},
		ThresholdRules: thresholdRules,
	}

	// Optional Pub/Sub notification
	if budget.AlertPubSubTopic != "" {
		budgetArgs.AllUpdatesRule = &billing.BudgetAllUpdatesRuleArgs{
			PubsubTopic: pulumi.String(budget.AlertPubSubTopic),
		}
	}

	// Budget creation needs billingbudgets.googleapis.com enabled+propagated
	// (auto-appended to ActivateApis when a Budget is requested).
	if _, err := billing.NewBudget(ctx, fmt.Sprintf("%s-budget", name), budgetArgs, pulumi.Parent(component), pulumi.DependsOn(apisGate)); err != nil {
		return err
	}

	return nil
}

// appendIfMissing appends s to the slice if it's not already present.
func appendIfMissing(slice []string, s string) []string {
	for _, item := range slice {
		if item == s {
			return slice
		}
	}
	return append(slice, s)
}
