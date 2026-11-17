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

// Package oncall loads, validates, and reconciles the PagerDuty responder
// lookup, on-call schedule, escalation policy, services, and Events API v2
// integrations.
package oncall

import (
	"fmt"
	"net/mail"
	"regexp"
	"strings"
	"time"

	"github.com/pulumi/pulumi-pagerduty/sdk/v4/go/pagerduty"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// Namespace is the Pulumi stack config namespace (`name:` in Pulumi.yaml).
const Namespace = "vitruvian-pagerduty"

// UrgencySeverityBased is the PagerDuty API value for "set the incident's
// urgency from the event's severity" (dynamic notifications).
const UrgencySeverityBased = "severity_based"

var serviceKeyPattern = regexp.MustCompile(`^[a-z][a-z0-9-]*$`)

// PagerDuty object ids are a "P" followed by upper-case letters and digits.
var pagerDutyIDPattern = regexp.MustCompile(`^P[A-Z0-9]+$`)

// Escalation configures the single free-tier escalation policy.
type Escalation struct {
	Name         string `json:"name" yaml:"name"`
	DelayMinutes int    `json:"delayMinutes" yaml:"delayMinutes"`
	Loops        int    `json:"loops" yaml:"loops"`
	// AdoptID is the id of an escalation policy that already exists in the
	// account. When set, the stack takes it over (Pulumi import) instead of
	// creating a new one. PagerDuty's free plan allows a single escalation
	// policy and every account starts with one called "Default", so creating
	// a second would fail. After the first apply the policy is in state and
	// the import is a no-op; the other fields then update it in place.
	AdoptID string `json:"adoptId" yaml:"adoptId"`
}

// Schedule configures the single free-tier on-call schedule. It has one
// rotation: Members take turns of ShiftDays each, in list order, starting at
// Start. The escalation policy pages whoever is on call in it.
type Schedule struct {
	Name     string `json:"name" yaml:"name"`
	TimeZone string `json:"timeZone" yaml:"timeZone"`
	// Start is when the first shift began (RFC 3339). Keep it fixed: it
	// anchors the rotation, so changing it shifts every handover.
	Start     string `json:"start" yaml:"start"`
	ShiftDays int    `json:"shiftDays" yaml:"shiftDays"`
	// Members are the PagerDuty users' emails, in rotation order. Empty
	// means the responder alone. Every member must already exist in the
	// account (the free plan allows five users); Pulumi never creates them.
	Members []string `json:"members" yaml:"members"`
}

// members returns the rotation's emails, defaulting to the responder alone.
func (s Settings) members() []string {
	if len(s.Schedule.Members) == 0 {
		return []string{s.ResponderEmail}
	}
	return s.Schedule.Members
}

// Recurrence is the RFC 5545 rule that repeats a shift every shiftDays days.
func Recurrence(shiftDays int) string {
	if shiftDays%7 == 0 {
		if shiftDays == 7 {
			return "RRULE:FREQ=WEEKLY"
		}
		return fmt.Sprintf("RRULE:FREQ=WEEKLY;INTERVAL=%d", shiftDays/7)
	}
	if shiftDays == 1 {
		return "RRULE:FREQ=DAILY"
	}
	return fmt.Sprintf("RRULE:FREQ=DAILY;INTERVAL=%d", shiftDays)
}

func utc(t time.Time) string { return t.UTC().Format(time.RFC3339) }

// Service describes one PagerDuty service and its Events API v2 integration.
type Service struct {
	Key         string `json:"key" yaml:"key"`
	Name        string `json:"name" yaml:"name"`
	Description string `json:"description" yaml:"description"`
}

// Settings holds the non-secret stack configuration under vitruvian-pagerduty.
type Settings struct {
	ResponderEmail string     `json:"responderEmail" yaml:"responderEmail"`
	Escalation     Escalation `json:"escalation" yaml:"escalation"`
	Schedule       Schedule   `json:"schedule" yaml:"schedule"`
	// NotificationRules are the responder's own rules. Empty leaves the
	// user's rules unmanaged.
	NotificationRules []NotificationRule `json:"notificationRules" yaml:"notificationRules"`
	Services          []Service          `json:"services" yaml:"services"`
}

// ServiceOutputs carries the exported Pulumi outputs for a single service.
type ServiceOutputs struct {
	ServiceID      pulumi.IDOutput
	IntegrationKey pulumi.StringOutput
}

// Outputs carries all stack outputs created by Reconcile.
type Outputs struct {
	ScheduleID         pulumi.IDOutput
	EscalationPolicyID pulumi.IDOutput
	Services           map[string]ServiceOutputs
}

// Load reads Settings from cfg and validates all constraints.
func Load(cfg *config.Config) (Settings, error) {
	var s Settings
	s.ResponderEmail = cfg.Get("responderEmail")
	if err := cfg.GetObject("escalation", &s.Escalation); err != nil {
		return Settings{}, fmt.Errorf("decode %s:escalation: %w", Namespace, err)
	}
	if err := cfg.GetObject("schedule", &s.Schedule); err != nil {
		return Settings{}, fmt.Errorf("decode %s:schedule: %w", Namespace, err)
	}
	if err := cfg.GetObject("notificationRules", &s.NotificationRules); err != nil {
		return Settings{}, fmt.Errorf("decode %s:notificationRules: %w", Namespace, err)
	}
	if err := cfg.GetObject("services", &s.Services); err != nil {
		return Settings{}, fmt.Errorf("decode %s:services: %w", Namespace, err)
	}
	if err := s.Validate(); err != nil {
		return Settings{}, err
	}
	return s, nil
}

// Validate checks that all required PagerDuty config fields and invariants hold.
func (s Settings) Validate() error {
	var errs []string
	add := func(format string, a ...any) { errs = append(errs, fmt.Sprintf(format, a...)) }

	if strings.TrimSpace(s.ResponderEmail) == "" {
		add("responderEmail must be non-empty")
	} else if a, err := mail.ParseAddress(s.ResponderEmail); err != nil || a.Address != s.ResponderEmail {
		add("responderEmail %q must be a bare email address", s.ResponderEmail)
	}
	if strings.TrimSpace(s.Escalation.Name) == "" {
		add("escalation.name must be non-empty")
	}
	if s.Escalation.DelayMinutes < 1 {
		add("escalation.delayMinutes must be >= 1, got %d", s.Escalation.DelayMinutes)
	}
	if s.Escalation.Loops < 0 {
		add("escalation.loops must be >= 0, got %d", s.Escalation.Loops)
	}
	if s.Escalation.AdoptID != "" && !pagerDutyIDPattern.MatchString(s.Escalation.AdoptID) {
		add("escalation.adoptId %q must be a PagerDuty id (^P[A-Z0-9]+$)", s.Escalation.AdoptID)
	}
	if strings.TrimSpace(s.Schedule.Name) == "" {
		add("schedule.name must be non-empty")
	}
	if _, err := time.LoadLocation(s.Schedule.TimeZone); s.Schedule.TimeZone == "" || err != nil {
		add("schedule.timeZone %q must be an IANA time zone such as America/Los_Angeles", s.Schedule.TimeZone)
	}
	if _, err := time.Parse(time.RFC3339, s.Schedule.Start); err != nil {
		add("schedule.start %q must be an RFC 3339 time such as 2026-11-17T09:00:00-08:00", s.Schedule.Start)
	}
	if s.Schedule.ShiftDays < 1 {
		add("schedule.shiftDays must be >= 1, got %d", s.Schedule.ShiftDays)
	}
	seenMember := map[string]bool{}
	for i, m := range s.Schedule.Members {
		if a, err := mail.ParseAddress(m); err != nil || a.Address != m {
			add("schedule.members[%d] %q must be a bare email address", i, m)
		}
		if seenMember[m] {
			add("schedule.members[%d] %q is duplicated", i, m)
		}
		seenMember[m] = true
	}
	validateNotificationRules(s.NotificationRules, add)
	if len(s.Services) == 0 {
		add("services must contain at least one entry")
	}

	seen := make(map[string]bool, len(s.Services))
	for i, svc := range s.Services {
		if !serviceKeyPattern.MatchString(svc.Key) {
			add("services[%d].key %q must match ^[a-z][a-z0-9-]*$", i, svc.Key)
		}
		if seen[svc.Key] {
			add("services[%d].key %q is duplicated; service keys must be unique", i, svc.Key)
		}
		seen[svc.Key] = true
		if strings.TrimSpace(svc.Name) == "" {
			add("services[%d].name must be non-empty", i)
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("invalid %s config:\n  - %s", Namespace, strings.Join(errs, "\n  - "))
	}
	return nil
}

// Reconcile looks up the schedule members, creates the on-call schedule and
// the escalation policy that pages it, and
// registers one PagerDuty service + Events API v2 integration per entry.
func Reconcile(ctx *pulumi.Context, provider *pagerduty.Provider, s Settings) (*Outputs, error) {
	if err := s.Validate(); err != nil {
		return nil, err
	}

	providerOpt := pulumi.Provider(provider)
	// Each user is looked up once, however many roles they have here.
	ids := map[string]string{}
	lookup := func(email string) (string, error) {
		if id, ok := ids[email]; ok {
			return id, nil
		}
		user, err := pagerduty.LookupUser(ctx, &pagerduty.LookupUserArgs{
			Email: email,
		}, providerOpt)
		if err != nil {
			return "", fmt.Errorf("lookup user %q: %w", email, err)
		}
		ids[email] = user.Id
		return user.Id, nil
	}
	var userIDs pulumi.StringArray
	for _, email := range s.members() {
		id, err := lookup(email)
		if err != nil {
			return nil, err
		}
		userIDs = append(userIDs, pulumi.String(id))
	}
	if len(s.NotificationRules) > 0 {
		responderID, err := lookup(s.ResponderEmail)
		if err != nil {
			return nil, err
		}
		if err := reconcileNotificationRules(ctx, providerOpt, responderID, s.NotificationRules); err != nil {
			return nil, err
		}
	}

	// A shift-based (v3) schedule: the legacy Schedule resource is deprecated.
	// One event repeats every ShiftDays, and the members take it in turns.
	// No Teams: free-tier accounts lack them. The free plan allows one
	// schedule, which this is.
	start, _ := time.Parse(time.RFC3339, s.Schedule.Start) // checked by Validate
	shift := time.Duration(s.Schedule.ShiftDays) * 24 * time.Hour
	var members pagerduty.Schedulev2RotationEventAssignmentStrategyMemberArray
	for _, id := range userIDs {
		members = append(members, &pagerduty.Schedulev2RotationEventAssignmentStrategyMemberArgs{
			Type:   pulumi.String("user_member"),
			UserId: id,
		})
	}
	schedule, err := pagerduty.NewSchedulev2(ctx, "oncall", &pagerduty.Schedulev2Args{
		Name:     pulumi.String(s.Schedule.Name),
		TimeZone: pulumi.String(s.Schedule.TimeZone),
		Rotations: pagerduty.Schedulev2RotationArray{
			&pagerduty.Schedulev2RotationArgs{
				Events: pagerduty.Schedulev2RotationEventArray{
					&pagerduty.Schedulev2RotationEventArgs{
						Name: pulumi.String("On call"),
						// PagerDuty stores these in UTC; sending UTC keeps the
						// preview free of no-op diffs.
						StartTime:      pulumi.String(utc(start)),
						EndTime:        pulumi.String(utc(start.Add(shift))),
						EffectiveSince: pulumi.String(utc(start)),
						Recurrences:    pulumi.StringArray{pulumi.String(Recurrence(s.Schedule.ShiftDays))},
						AssignmentStrategies: pagerduty.Schedulev2RotationEventAssignmentStrategyArray{
							&pagerduty.Schedulev2RotationEventAssignmentStrategyArgs{
								Type:            pulumi.String("rotating_member_assignment_strategy"),
								ShiftsPerMember: pulumi.Int(1),
								Members:         members,
							},
						},
					},
				},
			},
		},
	}, providerOpt)
	if err != nil {
		return nil, fmt.Errorf("create schedule: %w", err)
	}
	ctx.Export("scheduleId", schedule.ID())

	// Do not set Teams or EscalationRuleAssignmentStrategy: PagerDuty free-tier
	// accounts lack Teams and reject those fields with 403 Forbidden.
	policyOpts := []pulumi.ResourceOption{providerOpt}
	if s.Escalation.AdoptID != "" {
		policyOpts = append(policyOpts, pulumi.Import(pulumi.ID(s.Escalation.AdoptID)))
	}
	policy, err := pagerduty.NewEscalationPolicy(ctx, "oncall", &pagerduty.EscalationPolicyArgs{
		Name:     pulumi.String(s.Escalation.Name),
		NumLoops: pulumi.Int(s.Escalation.Loops),
		Rules: pagerduty.EscalationPolicyRuleArray{
			&pagerduty.EscalationPolicyRuleArgs{
				EscalationDelayInMinutes: pulumi.Int(s.Escalation.DelayMinutes),
				Targets: pagerduty.EscalationPolicyRuleTargetArray{
					&pagerduty.EscalationPolicyRuleTargetArgs{
						Type: pulumi.String("schedule_reference"),
						Id:   schedule.ID(),
					},
				},
			},
		},
	}, policyOpts...)
	if err != nil {
		return nil, fmt.Errorf("create escalation policy: %w", err)
	}
	ctx.Export("escalationPolicyId", policy.ID())

	out := &Outputs{
		ScheduleID:         schedule.ID(),
		EscalationPolicyID: policy.ID(),
		Services:           make(map[string]ServiceOutputs, len(s.Services)),
	}

	for _, svc := range s.Services {
		// Derive resource names from svc.Key so display name edits never replace.
		pdService, err := pagerduty.NewService(ctx, svc.Key, &pagerduty.ServiceArgs{
			Name:             pulumi.String(svc.Name),
			Description:      pulumi.String(svc.Description),
			EscalationPolicy: policy.ID(),
			AlertCreation:    pulumi.String("create_alerts_and_incidents"),
			// The event's own severity decides how loudly PagerDuty notifies:
			// critical and error are high urgency (phone, escalates), warning
			// and info are low urgency (no escalation). Alertmanager sends
			// severity=page as critical and severity=warning as warning, so
			// only real pages wake anyone. PagerDuty offers this on every
			// plan, free included (support.pagerduty.com/docs/dynamic-notifications).
			IncidentUrgencyRule: &pagerduty.ServiceIncidentUrgencyRuleArgs{
				Type:    pulumi.String("constant"),
				Urgency: pulumi.String(UrgencySeverityBased),
			},
		}, providerOpt)
		if err != nil {
			return nil, fmt.Errorf("create service %q: %w", svc.Key, err)
		}

		integration, err := pagerduty.NewServiceIntegration(ctx, svc.Key+"-events-v2", &pagerduty.ServiceIntegrationArgs{
			Name:    pulumi.String(svc.Name + " (Events API v2)"),
			Service: pdService.ID(),
			Type:    pulumi.String("events_api_v2_inbound_integration"),
		}, providerOpt)
		if err != nil {
			return nil, fmt.Errorf("create integration for %q: %w", svc.Key, err)
		}

		secretKey := pulumi.ToSecret(integration.IntegrationKey).(pulumi.StringOutput)
		ctx.Export(svc.Key+"ServiceId", pdService.ID())
		ctx.Export(svc.Key+"IntegrationKey", secretKey)

		out.Services[svc.Key] = ServiceOutputs{
			ServiceID:      pdService.ID(),
			IntegrationKey: secretKey,
		}
	}

	return out, nil
}
