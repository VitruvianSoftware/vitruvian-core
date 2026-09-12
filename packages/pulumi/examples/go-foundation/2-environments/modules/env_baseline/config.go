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

// Module inputs — the Pulumi analog of upstream env_baseline/variables.tf.
// Args carries the 6 upstream module inputs plus the values our port resolves
// from Pulumi config / a stack reference instead of terraform_remote_state;
// the budget helpers apply upstream's variable defaults.

package env_baseline

import (
	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// PerProjectBudget holds the budget configuration for a single project.
type PerProjectBudget struct {
	Amount             float64
	AlertSpentPercents []float64
	AlertPubSubTopic   string
	AlertSpendBasis    string
}

// EnvProjectBudgetConfig mirrors the upstream project_budget variable.
// SharedNetwork is retained for config-schema parity with upstream variables.tf
// but is a no-op here: env_baseline creates only the KMS + Secrets projects (the
// network project belongs to stage 3).
type EnvProjectBudgetConfig struct {
	SharedNetwork PerProjectBudget
	KMS           PerProjectBudget
	Secret        PerProjectBudget
}

// AssuredWorkloadConfig mirrors the upstream assured_workload_configuration variable.
type AssuredWorkloadConfig struct {
	Enabled          bool
	Location         string
	DisplayName      string
	ComplianceRegime string
	ResourceType     string
}

// Args are the inputs to the env_baseline module — the 6 upstream module inputs
// plus the values our port resolves from Pulumi config / a stack reference
// instead of terraform_remote_state (org_id, billing, prefixes, parent, tags).
type Args struct {
	Env                      string // upstream env
	EnvCode                  string // upstream environment_code
	Parent                   string // remote.tf local.parent
	OrgID                    string
	BillingAccount           string
	ProjectPrefix            string
	FolderPrefix             string
	RandomSuffix             bool
	DefaultServiceAccount    string
	ProjectDeletionPolicy    string
	FolderDeletionProtection bool
	ProjectBudget            *EnvProjectBudgetConfig
	// ApiPropagationSeconds gates project children (Budget, default-SA
	// deprivilege) on a post-enablement wait: on a cold deploy a
	// freshly-enabled API (billingbudgets, iam, ...) is not immediately
	// usable, so dependents race it without this propagation delay.
	ApiPropagationSeconds int
	AssuredWorkload       AssuredWorkloadConfig
	Tags                  pulumi.Output // 1-org "tags" map (StackReference output); may be nil
}

func budgetFor(pb *PerProjectBudget) *project.BudgetConfig {
	if pb == nil {
		return nil
	}
	amount := pb.Amount
	if amount == 0 {
		amount = 1000 // upstream default
	}
	alertPercents := pb.AlertSpentPercents
	if len(alertPercents) == 0 {
		alertPercents = []float64{1.2} // upstream default
	}
	spendBasis := pb.AlertSpendBasis
	if spendBasis == "" {
		spendBasis = "FORECASTED_SPEND" // upstream default
	}
	return &project.BudgetConfig{
		Amount:             amount,
		AlertSpentPercents: alertPercents,
		AlertPubSubTopic:   pb.AlertPubSubTopic,
		AlertSpendBasis:    spendBasis,
	}
}

// getEnvProjectBudget returns the per-project budget for the named project type.
func getEnvProjectBudget(pb *EnvProjectBudgetConfig, projectType string) *PerProjectBudget {
	if pb == nil {
		return nil
	}
	switch projectType {
	case "shared_network":
		return &pb.SharedNetwork
	case "kms":
		return &pb.KMS
	case "secret":
		return &pb.Secret
	default:
		return nil
	}
}
