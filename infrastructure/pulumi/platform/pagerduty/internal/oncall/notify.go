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

package oncall

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-pagerduty/sdk/v4/go/pagerduty"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Contact method types PagerDuty can notify through (API values).
var contactMethodTypes = map[string]bool{
	"email_contact_method":             true,
	"phone_contact_method":             true,
	"push_notification_contact_method": true,
	"sms_contact_method":               true,
}

// NotificationRule is one of the responder's personal notification rules:
// how and how soon PagerDuty reaches them for an incident of one urgency.
// PagerDuty stops working through the rules once the incident is
// acknowledged, so a later rule only fires if the earlier ones went
// unanswered.
//
// The contact method itself (the phone number or email) is never in this
// repository: the rule names an existing contact method by type and label,
// and the stack looks it up. Add or change numbers in PagerDuty's profile page.
type NotificationRule struct {
	Urgency      string `json:"urgency" yaml:"urgency"`
	Type         string `json:"type" yaml:"type"`
	Label        string `json:"label" yaml:"label"`
	DelayMinutes int    `json:"delayMinutes" yaml:"delayMinutes"`
	// AdoptID is the id of a rule that already exists on the user, so the
	// stack takes it over (Pulumi import) instead of adding a duplicate.
	AdoptID string `json:"adoptId" yaml:"adoptId"`
}

// key is the rule's stable Pulumi resource name.
func (r NotificationRule) key() string {
	return fmt.Sprintf("notify-%s-%s", r.Urgency, strings.TrimSuffix(strings.ReplaceAll(r.Type, "_", "-"), "-contact-method"))
}

func validateNotificationRules(rules []NotificationRule, add func(string, ...any)) {
	seen := map[string]bool{}
	for i, r := range rules {
		if r.Urgency != "high" && r.Urgency != "low" {
			add("notificationRules[%d].urgency %q must be high or low", i, r.Urgency)
		}
		if !contactMethodTypes[r.Type] {
			add("notificationRules[%d].type %q must be one of email_contact_method, phone_contact_method, push_notification_contact_method, sms_contact_method", i, r.Type)
		}
		if strings.TrimSpace(r.Label) == "" {
			add("notificationRules[%d].label must name the contact method's label in PagerDuty", i)
		}
		if r.DelayMinutes < 0 {
			add("notificationRules[%d].delayMinutes must be >= 0, got %d", i, r.DelayMinutes)
		}
		if r.AdoptID != "" && !pagerDutyIDPattern.MatchString(r.AdoptID) {
			add("notificationRules[%d].adoptId %q must be a PagerDuty id (^P[A-Z0-9]+$)", i, r.AdoptID)
		}
		// One rule per urgency and contact method: the resource name derives
		// from the pair, and a second rule there would only duplicate a ping.
		if seen[r.key()] {
			add("notificationRules[%d] repeats %s for %s urgency", i, r.Type, r.Urgency)
		}
		seen[r.key()] = true
	}
}

// reconcileNotificationRules manages the responder's notification rules.
func reconcileNotificationRules(ctx *pulumi.Context, providerOpt pulumi.ResourceOrInvokeOption, userID string, rules []NotificationRule) error {
	for _, r := range rules {
		cm, err := pagerduty.LookupUserContactMethod(ctx, &pagerduty.LookupUserContactMethodArgs{
			UserId: userID,
			Type:   r.Type,
			Label:  r.Label,
		}, providerOpt)
		if err != nil {
			return fmt.Errorf("lookup %s contact method labelled %q: %w", r.Type, r.Label, err)
		}
		opts := []pulumi.ResourceOption{providerOpt}
		if r.AdoptID != "" {
			// The provider imports a rule as "<user id>:<rule id>".
			opts = append(opts, pulumi.Import(pulumi.ID(userID+":"+r.AdoptID)))
		}
		_, err = pagerduty.NewUserNotificationRule(ctx, r.key(), &pagerduty.UserNotificationRuleArgs{
			UserId:              pulumi.String(userID),
			Urgency:             pulumi.String(r.Urgency),
			StartDelayInMinutes: pulumi.Int(r.DelayMinutes),
			ContactMethod: &pagerduty.UserNotificationRuleContactMethodArgs{
				Id:   pulumi.String(cm.Id),
				Type: pulumi.String(r.Type),
			},
		}, opts...)
		if err != nil {
			return fmt.Errorf("create notification rule %s: %w", r.key(), err)
		}
	}
	return nil
}
