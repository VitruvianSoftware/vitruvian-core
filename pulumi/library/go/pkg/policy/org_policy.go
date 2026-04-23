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

package policy

import (
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/orgpolicy"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// OrgPolicyArgs configures an organization policy constraint.
//
// ParentID must be a full resource path like "organizations/123456" or
// "folders/789". Constraint should be the full constraint name like
// "constraints/compute.disableSerialPortAccess".
type OrgPolicyArgs struct {
	ParentID    pulumi.StringInput
	Constraint  pulumi.StringInput
	Boolean     pulumi.BoolPtrInput
	AllowValues pulumi.StringArrayInput
	DenyValues  pulumi.StringArrayInput
	DenyAll     pulumi.BoolPtrInput
	AllowAll    pulumi.BoolPtrInput
}

type OrgPolicy struct {
	pulumi.ResourceState
	Policy *orgpolicy.Policy
}

func NewOrgPolicy(ctx *pulumi.Context, name string, args *OrgPolicyArgs, opts ...pulumi.ResourceOption) (*OrgPolicy, error) {
	component := &OrgPolicy{}
	err := ctx.RegisterComponentResource("pkg:index:OrgPolicy", name, component, opts...)
	if err != nil {
		return nil, err
	}

	// Construct the proper policy resource name from parent + constraint.
	// The GCP org policy v2 API expects names like:
	//   "organizations/123456/policies/compute.disableSerialPortAccess"
	// Our callers pass constraint as "constraints/compute.disableSerialPortAccess",
	// so we strip the prefix and combine with the parent path.
	policyName := pulumi.All(args.ParentID, args.Constraint).ApplyT(func(vals []interface{}) string {
		parent := vals[0].(string)
		constraint := vals[1].(string)
		constraint = strings.TrimPrefix(constraint, "constraints/")
		return parent + "/policies/" + constraint
	}).(pulumi.StringOutput)

	policyArgs := &orgpolicy.PolicyArgs{
		Parent: args.ParentID,
		Name:   policyName,
	}

	var rules []orgpolicy.PolicySpecRuleInput

	if args.Boolean != nil {
		// Boolean constraint (e.g., enforce compute.disableSerialPortAccess)
		rules = append(rules, &orgpolicy.PolicySpecRuleArgs{
			Enforce: args.Boolean.ToBoolPtrOutput().ApplyT(func(b *bool) string {
				if b != nil && *b {
					return "TRUE"
				}
				return "FALSE"
			}).(pulumi.StringOutput),
		})
	} else if args.DenyAll != nil || args.AllowAll != nil || args.AllowValues != nil || args.DenyValues != nil {
		// List constraint
		ruleArgs := &orgpolicy.PolicySpecRuleArgs{}

		if args.DenyAll != nil {
			ruleArgs.DenyAll = args.DenyAll.ToBoolPtrOutput().ApplyT(func(b *bool) string {
				if b != nil && *b {
					return "TRUE"
				}
				return "FALSE"
			}).(pulumi.StringOutput)
		} else if args.AllowAll != nil {
			ruleArgs.AllowAll = args.AllowAll.ToBoolPtrOutput().ApplyT(func(b *bool) string {
				if b != nil && *b {
					return "TRUE"
				}
				return "FALSE"
			}).(pulumi.StringOutput)
		} else {
			valuesArgs := &orgpolicy.PolicySpecRuleValuesArgs{}
			if args.AllowValues != nil {
				valuesArgs.AllowedValues = args.AllowValues
			}
			if args.DenyValues != nil {
				valuesArgs.DeniedValues = args.DenyValues
			}
			ruleArgs.Values = valuesArgs
		}

		rules = append(rules, ruleArgs)
	}

	if len(rules) > 0 {
		policyArgs.Spec = &orgpolicy.PolicySpecArgs{
			Rules: orgpolicy.PolicySpecRuleArray(rules),
		}
	}

	p, err := orgpolicy.NewPolicy(ctx, name, policyArgs, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Policy = p

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}
