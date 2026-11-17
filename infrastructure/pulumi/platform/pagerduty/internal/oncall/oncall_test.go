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
	"os"
	"regexp"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi-pagerduty/sdk/v4/go/pagerduty"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"gopkg.in/yaml.v3"
)

func validSettings() Settings {
	return Settings{
		ResponderEmail: "responder@example.com",
		Escalation: Escalation{
			Name:         "Primary on-call",
			DelayMinutes: 30,
			Loops:        2,
		},
		Schedule: Schedule{
			Name:      "Primary rotation",
			TimeZone:  "America/Los_Angeles",
			Start:     "2026-11-16T09:00:00-08:00",
			ShiftDays: 7,
		},
		Services: []Service{
			{
				Key:         "sentry",
				Name:        "Sentry",
				Description: "Self-hosted Sentry alerts",
			},
		},
	}
}

func TestValidateAcceptsGoodConfig(t *testing.T) {
	if err := validSettings().Validate(); err != nil {
		t.Fatalf("expected valid config to pass, got %v", err)
	}
}

func TestValidateAcceptsZeroLoops(t *testing.T) {
	s := validSettings()
	s.Escalation.Loops = 0
	if err := s.Validate(); err != nil {
		t.Fatalf("expected loops == 0 to be valid, got %v", err)
	}
}

func TestValidateRejectsBadConfig(t *testing.T) {
	cases := map[string]struct {
		mutate func(*Settings)
		want   string
	}{
		"empty email": {
			mutate: func(s *Settings) { s.ResponderEmail = "" },
			want:   "responderEmail",
		},
		"whitespace email": {
			mutate: func(s *Settings) { s.ResponderEmail = "   " },
			want:   "responderEmail",
		},
		"responderEmail that is not an email": {
			mutate: func(s *Settings) { s.ResponderEmail = "not-an-email" },
			want:   "responderEmail",
		},
		"responderEmail with a display name": {
			mutate: func(s *Settings) { s.ResponderEmail = "James <james@vitruviansoftware.dev>" },
			want:   "responderEmail",
		},
		"adoptId that is not a PagerDuty id": {
			mutate: func(s *Settings) { s.Escalation.AdoptID = "default" },
			want:   "escalation.adoptId",
		},
		"empty escalation name": {
			mutate: func(s *Settings) { s.Escalation.Name = "  " },
			want:   "escalation.name",
		},
		"zero delayMinutes": {
			mutate: func(s *Settings) { s.Escalation.DelayMinutes = 0 },
			want:   "escalation.delayMinutes",
		},
		"negative delayMinutes": {
			mutate: func(s *Settings) { s.Escalation.DelayMinutes = -5 },
			want:   "escalation.delayMinutes",
		},
		"negative loops": {
			mutate: func(s *Settings) { s.Escalation.Loops = -1 },
			want:   "escalation.loops",
		},
		"empty schedule name": {
			mutate: func(s *Settings) { s.Schedule.Name = " " },
			want:   "schedule.name",
		},
		"unknown time zone": {
			mutate: func(s *Settings) { s.Schedule.TimeZone = "Pacific" },
			want:   "schedule.timeZone",
		},
		"empty time zone": {
			mutate: func(s *Settings) { s.Schedule.TimeZone = "" },
			want:   "schedule.timeZone",
		},
		"start without an offset": {
			mutate: func(s *Settings) { s.Schedule.Start = "2026-11-16T09:00:00" },
			want:   "schedule.start",
		},
		"schedule adoptId that is not an id": {
			mutate: func(s *Settings) { s.Schedule.AdoptID = "rotation" },
			want:   "schedule.adoptId",
		},
		"zero shiftDays": {
			mutate: func(s *Settings) { s.Schedule.ShiftDays = 0 },
			want:   "schedule.shiftDays",
		},
		"member that is not an email": {
			mutate: func(s *Settings) { s.Schedule.Members = []string{"james"} },
			want:   "schedule.members[0]",
		},
		"duplicate member": {
			mutate: func(s *Settings) { s.Schedule.Members = []string{"a@b.dev", "a@b.dev"} },
			want:   "duplicated",
		},
		"bad rule urgency": {
			mutate: func(s *Settings) {
				s.NotificationRules = []NotificationRule{{Urgency: "urgent", Type: "email_contact_method", Label: "Default"}}
			},
			want: "notificationRules[0].urgency",
		},
		"bad rule type": {
			mutate: func(s *Settings) {
				s.NotificationRules = []NotificationRule{{Urgency: "high", Type: "pager", Label: "Default"}}
			},
			want: "notificationRules[0].type",
		},
		"rule without a label": {
			mutate: func(s *Settings) {
				s.NotificationRules = []NotificationRule{{Urgency: "high", Type: "sms_contact_method"}}
			},
			want: "notificationRules[0].label",
		},
		"negative rule delay": {
			mutate: func(s *Settings) {
				s.NotificationRules = []NotificationRule{{Urgency: "high", Type: "sms_contact_method", Label: "Mobile", DelayMinutes: -1}}
			},
			want: "notificationRules[0].delayMinutes",
		},
		"rule adoptId that is not an id": {
			mutate: func(s *Settings) {
				s.NotificationRules = []NotificationRule{{Urgency: "high", Type: "sms_contact_method", Label: "Mobile", AdoptID: "sms"}}
			},
			want: "notificationRules[0].adoptId",
		},
		"repeated rule": {
			mutate: func(s *Settings) {
				r := NotificationRule{Urgency: "low", Type: "email_contact_method", Label: "Default"}
				s.NotificationRules = []NotificationRule{r, r}
			},
			want: "repeats",
		},
		"no services": {
			mutate: func(s *Settings) { s.Services = nil },
			want:   "at least one",
		},
		"empty service key": {
			mutate: func(s *Settings) { s.Services[0].Key = "" },
			want:   "services[0].key",
		},
		"uppercase service key": {
			mutate: func(s *Settings) { s.Services[0].Key = "Sentry" },
			want:   "services[0].key",
		},
		"digit-prefixed service key": {
			mutate: func(s *Settings) { s.Services[0].Key = "1sentry" },
			want:   "services[0].key",
		},
		"underscore service key": {
			mutate: func(s *Settings) { s.Services[0].Key = "sentry_prod" },
			want:   "services[0].key",
		},
		"duplicate service keys": {
			mutate: func(s *Settings) {
				s.Services = append(s.Services, Service{Key: "sentry", Name: "Sentry Duplicate"})
			},
			want: "duplicated",
		},
		"empty service name": {
			mutate: func(s *Settings) { s.Services[0].Name = " " },
			want:   "services[0].name",
		},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			s := validSettings()
			tc.mutate(&s)
			err := s.Validate()
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("expected error containing %q, got %v", tc.want, err)
			}
		})
	}
}

// pagerDutyTokenPattern matches PagerDuty REST v2 user/general API tokens
// (typically prefixed with u+, y+, or w+ followed by base64/url-safe characters).
var pagerDutyTokenPattern = regexp.MustCompile(`^[yuw]\+[A-Za-z0-9_-]{16,}$`)

func scanForPlaintextTokens(node *yaml.Node, path string) error {
	if node == nil {
		return nil
	}
	if node.Kind == yaml.ScalarNode && node.Tag == "!!str" {
		val := strings.TrimSpace(node.Value)
		if pagerDutyTokenPattern.MatchString(val) {
			return fmt.Errorf("YAML value at %s resembles a plaintext PagerDuty API token", path)
		}
	}
	if node.Kind == yaml.MappingNode {
		for i := 0; i+1 < len(node.Content); i += 2 {
			k := node.Content[i].Value
			if err := scanForPlaintextTokens(node.Content[i+1], path+"."+k); err != nil {
				return err
			}
		}
		return nil
	}
	for i, child := range node.Content {
		if err := scanForPlaintextTokens(child, fmt.Sprintf("%s[%d]", path, i)); err != nil {
			return err
		}
	}
	return nil
}

func checkStackConfigBytes(raw []byte) (Settings, error) {
	var root yaml.Node
	if err := yaml.Unmarshal(raw, &root); err != nil {
		return Settings{}, fmt.Errorf("parse stack yaml: %w", err)
	}
	if err := scanForPlaintextTokens(&root, "root"); err != nil {
		return Settings{}, err
	}

	var doc struct {
		Config map[string]yaml.Node `yaml:"config"`
	}
	if err := yaml.Unmarshal(raw, &doc); err != nil {
		return Settings{}, fmt.Errorf("parse config map: %w", err)
	}

	// If pagerduty:token appears at all, it must be Pulumi ciphertext (`secure:`),
	// never a plaintext scalar string.
	if n, ok := doc.Config["pagerduty:token"]; ok {
		var secure struct {
			Secure string `yaml:"secure"`
		}
		if n.Kind != yaml.MappingNode || n.Decode(&secure) != nil || strings.TrimSpace(secure.Secure) == "" {
			return Settings{}, fmt.Errorf("pagerduty:token must be encrypted Pulumi ciphertext, never plaintext")
		}
	}
	// Allowlist: any key not named here is rejected, so a token pasted under
	// a new or misspelt key fails the build whatever its format.
	allowed := map[string]bool{
		Namespace + ":responderEmail":    true,
		Namespace + ":escalation":        true,
		Namespace + ":schedule":          true,
		Namespace + ":notificationRules": true,
		Namespace + ":dependencies":      true,
		Namespace + ":businessServices":  true,
		Namespace + ":services":          true,
		"pagerduty:token":                true, // only as ciphertext, checked above
	}
	for k := range doc.Config {
		if !allowed[k] {
			return Settings{}, fmt.Errorf("unexpected config key %q: only responderEmail, escalation, schedule, notificationRules, dependencies, businessServices, services and an encrypted pagerduty:token are allowed", k)
		}
	}
	if _, ok := doc.Config[Namespace+":token"]; ok {
		return Settings{}, fmt.Errorf("%s:token must not appear; use PAGERDUTY_TOKEN or encrypted pagerduty:token", Namespace)
	}

	decode := func(key string, into any) error {
		n, ok := doc.Config[Namespace+":"+key]
		if !ok {
			return fmt.Errorf("missing config key %s:%s", Namespace, key)
		}
		if err := n.Decode(into); err != nil {
			return fmt.Errorf("decode %s:%s: %w", Namespace, key, err)
		}
		return nil
	}

	var s Settings
	if err := decode("responderEmail", &s.ResponderEmail); err != nil {
		return Settings{}, err
	}
	if err := decode("escalation", &s.Escalation); err != nil {
		return Settings{}, err
	}
	if err := decode("schedule", &s.Schedule); err != nil {
		return Settings{}, err
	}
	for key, into := range map[string]any{"dependencies": &s.Dependencies, "businessServices": &s.BusinessServices} {
		if n, ok := doc.Config[Namespace+":"+key]; ok {
			if err := n.Decode(into); err != nil {
				return Settings{}, fmt.Errorf("decode %s:%s: %w", Namespace, key, err)
			}
		}
	}
	// notificationRules is optional: empty leaves the user's rules alone.
	if n, ok := doc.Config[Namespace+":notificationRules"]; ok {
		if err := n.Decode(&s.NotificationRules); err != nil {
			return Settings{}, fmt.Errorf("decode %s:notificationRules: %w", Namespace, err)
		}
	}
	if err := decode("services", &s.Services); err != nil {
		return Settings{}, err
	}
	if err := s.Validate(); err != nil {
		return Settings{}, err
	}
	return s, nil
}

func loadCommittedProductionConfig(t *testing.T) Settings {
	t.Helper()
	raw, err := os.ReadFile("../../Pulumi.production.yaml")
	if err != nil {
		t.Fatalf("read Pulumi.production.yaml: %v", err)
	}
	s, err := checkStackConfigBytes(raw)
	if err != nil {
		t.Fatalf("Pulumi.production.yaml validation failed: %v", err)
	}
	return s
}

func TestCommittedProductionConfig(t *testing.T) {
	s := loadCommittedProductionConfig(t)
	if s.ResponderEmail != "james@vitruviansoftware.dev" {
		t.Fatalf("unexpected responderEmail: %q", s.ResponderEmail)
	}
	// Free plan: one escalation policy, so production must adopt the
	// account's built-in one instead of creating a second.
	if s.Escalation.AdoptID == "" {
		t.Fatal("production must set escalation.adoptId: the free plan allows only one escalation policy")
	}
	var keys []string
	for _, svc := range s.Services {
		keys = append(keys, svc.Key)
	}
	// Alertmanager routes to cluster, data and apps by the pagerduty_service
	// rule label, and notify-ci-issues sends to ci through repo-config's
	// PAGERDUTY_CI_ROUTING_KEY; dropping one here silently strands those alerts.
	if got, want := strings.Join(keys, ","), "sentry,cluster,data,apps,ci"; got != want {
		t.Fatalf("production services = %q, want %q", got, want)
	}
}

func TestPlaintextTokenGuardRejectsSecrets(t *testing.T) {
	baseYAML := `config:
  vitruvian-pagerduty:responderEmail: responder@example.com
  vitruvian-pagerduty:escalation:
    name: Vitruvian on-call
    delayMinutes: 30
    loops: 2
  vitruvian-pagerduty:schedule:
    name: Rotation
    timeZone: America/Los_Angeles
    start: "2026-11-16T09:00:00-08:00"
    shiftDays: 7
  vitruvian-pagerduty:services:
    - key: sentry
      name: Sentry
      description: Alerts
`
	if _, err := checkStackConfigBytes([]byte(baseYAML + "  pagerduty:token: plaintext-value\n")); err == nil {
		t.Fatal("expected guard to reject plaintext pagerduty:token")
	}
	if _, err := checkStackConfigBytes([]byte(baseYAML + "  vitruvian-pagerduty:token:\n    secure: v1:fake\n")); err == nil {
		t.Fatal("expected guard to reject vitruvian-pagerduty:token")
	}
	// Construct the token pattern dynamically so secret scanners do not trip on test fixtures.
	fakeRestToken := "u+" + strings.Repeat("A", 18)
	if _, err := checkStackConfigBytes([]byte(baseYAML + "  vitruvian-pagerduty:extra: " + fakeRestToken + "\n")); err == nil {
		t.Fatal("expected guard to reject value matching PagerDuty API token pattern")
	}
	if _, err := checkStackConfigBytes([]byte(baseYAML + "  pagerduty:token:\n    secure: v1:encrypted-blob\n")); err != nil {
		t.Fatalf("expected encrypted pagerduty:token to pass, got %v", err)
	}
}

type recordedResource struct {
	Type     string
	Name     string
	ID       string
	ImportID string
	Inputs   resource.PropertyMap
}

type recordedInvoke struct {
	Token string
	Args  resource.PropertyMap
}

type pagerdutyMocks struct {
	mu        sync.Mutex
	invokes   []recordedInvoke
	resources []recordedResource
}

func (m *pagerdutyMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	m.mu.Lock()
	m.invokes = append(m.invokes, recordedInvoke{Token: args.Token, Args: args.Args})
	m.mu.Unlock()

	if args.Token == "pagerduty:index/getUserContactMethod:getUserContactMethod" {
		return resource.PropertyMap{
			"id":      resource.NewStringProperty("PCM_" + args.Args["type"].StringValue()),
			"address": resource.NewStringProperty("redacted"),
			"label":   args.Args["label"],
			"type":    args.Args["type"],
		}, nil
	}
	if args.Token == "pagerduty:index/getUser:getUser" {
		return resource.PropertyMap{
			"id":    resource.NewStringProperty("PUSER01"),
			"name":  resource.NewStringProperty("James"),
			"email": args.Args["email"],
		}, nil
	}
	return args.Args, nil
}

func (m *pagerdutyMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	var id string
	outputs := resource.PropertyMap{}
	for k, v := range args.Inputs {
		outputs[k] = v
	}

	switch args.TypeToken {
	case "pagerduty:index/escalationPolicy:EscalationPolicy":
		id = "PESCPOL01"
	case "pagerduty:index/schedulev2:Schedulev2":
		id = "PSCHED01"
	case "pagerduty:index/service:Service":
		id = "PSVC_" + args.Name
		outputs["type"] = resource.NewStringProperty("service")
	case "pagerduty:index/businessService:BusinessService":
		id = "PBIZ_" + args.Name
		outputs["type"] = resource.NewStringProperty("business_service")
	case "pagerduty:index/serviceIntegration:ServiceIntegration":
		id = "PINT_" + args.Name
		outputs["integrationKey"] = resource.NewStringProperty("fake-routing-key-0000000000000001")
	default:
		id = args.Name + "_id"
	}

	m.mu.Lock()
	m.resources = append(m.resources, recordedResource{
		Type:     args.TypeToken,
		Name:     args.Name,
		ID:       id,
		ImportID: args.ID,
		Inputs:   args.Inputs,
	})
	m.mu.Unlock()

	return id, outputs, nil
}

func (m *pagerdutyMocks) byType(typ string) []recordedResource {
	m.mu.Lock()
	defer m.mu.Unlock()
	var matched []recordedResource
	for _, r := range m.resources {
		if r.Type == typ {
			matched = append(matched, r)
		}
	}
	return matched
}

func TestReconcileWithMocks(t *testing.T) {
	s := loadCommittedProductionConfig(t)
	m := &pagerdutyMocks{}

	var (
		policyID          string
		policySecret      bool
		sentryServiceID   string
		sentryServiceSec  bool
		sentryIntegKey    string
		sentryIntegKeySec bool
	)

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		provider, err := pagerduty.NewProvider(ctx, "pagerduty", &pagerduty.ProviderArgs{
			Token: pulumi.ToSecret(pulumi.String("mock-token")).(pulumi.StringOutput),
		})
		if err != nil {
			return err
		}
		out, err := Reconcile(ctx, provider, s)
		if err != nil {
			return err
		}

		policySecret = pulumi.IsSecret(out.EscalationPolicyID)
		sentryOut := out.Services["sentry"]
		sentryServiceSec = pulumi.IsSecret(sentryOut.ServiceID)
		sentryIntegKeySec = pulumi.IsSecret(sentryOut.IntegrationKey)

		waitStr := func(o pulumi.StringOutput, dst *string) {
			ch := make(chan string, 1)
			o.ApplyT(func(v string) string {
				ch <- v
				return v
			})
			*dst = <-ch
		}
		waitID := func(o pulumi.IDOutput, dst *string) {
			ch := make(chan string, 1)
			o.ApplyT(func(v string) string {
				ch <- v
				return v
			})
			*dst = <-ch
		}

		waitID(out.EscalationPolicyID, &policyID)
		waitID(sentryOut.ServiceID, &sentryServiceID)
		waitStr(sentryOut.IntegrationKey, &sentryIntegKey)
		return nil
	}, pulumi.WithMocks("vitruvian-pagerduty", "production", m))
	if err != nil {
		t.Fatalf("mocked run failed: %v", err)
	}

	var userInvokes []recordedInvoke
	for _, inv := range m.invokes {
		if inv.Token == "pagerduty:index/getUser:getUser" {
			userInvokes = append(userInvokes, inv)
		}
	}
	if len(userInvokes) != 1 || m.invokes[0].Token != "pagerduty:index/getUser:getUser" {
		t.Fatalf("expected the responder looked up once, first; got %+v", m.invokes)
	}
	if got := m.invokes[0].Args["email"].StringValue(); got != "james@vitruviansoftware.dev" {
		t.Fatalf("expected getUser email james@vitruviansoftware.dev, got %q", got)
	}

	policies := m.byType("pagerduty:index/escalationPolicy:EscalationPolicy")
	if len(policies) != 1 {
		t.Fatalf("expected 1 escalation policy, got %d", len(policies))
	}
	p := policies[0]
	if _, hasTeams := p.Inputs["teams"]; hasTeams {
		t.Fatal("escalation policy must not set teams on PagerDuty free tier")
	}
	if _, hasStrat := p.Inputs["escalationRuleAssignmentStrategy"]; hasStrat {
		t.Fatal("escalation policy must not set escalationRuleAssignmentStrategy on PagerDuty free tier")
	}
	if got := p.Inputs["numLoops"].NumberValue(); got != 2 {
		t.Fatalf("expected numLoops 2, got %v", got)
	}
	rules := p.Inputs["rules"].ArrayValue()
	if len(rules) != 1 {
		t.Fatalf("expected 1 escalation rule, got %d", len(rules))
	}
	ruleObj := rules[0].ObjectValue()
	if got := ruleObj["escalationDelayInMinutes"].NumberValue(); got != 30 {
		t.Fatalf("expected delay 30 minutes, got %v", got)
	}
	targets := ruleObj["targets"].ArrayValue()
	if len(targets) != 1 {
		t.Fatalf("expected 1 rule target, got %d", len(targets))
	}
	targetObj := targets[0].ObjectValue()
	if targetObj["type"].StringValue() != "schedule_reference" || targetObj["id"].StringValue() != "PSCHED01" {
		t.Fatalf("expected target schedule_reference PSCHED01, got %v", targetObj)
	}

	schedules := m.byType("pagerduty:index/schedulev2:Schedulev2")
	if len(schedules) != 1 {
		t.Fatalf("expected 1 schedule (the free plan allows one), got %d", len(schedules))
	}
	sched := schedules[0]
	if _, hasTeams := sched.Inputs["teams"]; hasTeams {
		t.Fatal("schedule must not set teams on PagerDuty free tier")
	}
	if got := sched.Inputs["description"].StringValue(); got != ScheduleDescription {
		t.Fatalf("schedule description = %q: it must always be set, or the provider fails the apply", got)
	}
	if sched.ImportID != "PE5D9GC" {
		t.Fatalf("production must adopt the orphaned schedule PE5D9GC, got import id %q", sched.ImportID)
	}
	if got := sched.Inputs["timeZone"].StringValue(); got != "America/Los_Angeles" {
		t.Fatalf("schedule timeZone = %q, want America/Los_Angeles", got)
	}
	rotations := sched.Inputs["rotations"].ArrayValue()
	if len(rotations) != 1 {
		t.Fatalf("expected 1 rotation, got %d", len(rotations))
	}
	events := rotations[0].ObjectValue()["events"].ArrayValue()
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	ev := events[0].ObjectValue()
	// Committed start is 2026-11-16 09:00 Pacific = 17:00 UTC; a weekly shift.
	if ev["startTime"].StringValue() != "2026-11-16T17:00:00Z" ||
		ev["effectiveSince"].StringValue() != "2026-11-16T17:00:00Z" ||
		ev["endTime"].StringValue() != "2026-11-23T17:00:00Z" {
		t.Fatalf("event times must be the start and start+7d in UTC, got %v", ev)
	}
	if rec := ev["recurrences"].ArrayValue(); len(rec) != 1 || rec[0].StringValue() != "RRULE:FREQ=WEEKLY" {
		t.Fatalf("expected RRULE:FREQ=WEEKLY, got %v", rec)
	}
	strat := ev["assignmentStrategies"].ArrayValue()[0].ObjectValue()
	if strat["type"].StringValue() != "rotating_member_assignment_strategy" || strat["shiftsPerMember"].NumberValue() != 1 {
		t.Fatalf("expected one shift each in turn, got %v", strat)
	}
	users := strat["members"].ArrayValue()
	if len(users) != 1 || users[0].ObjectValue()["userId"].StringValue() != "PUSER01" ||
		users[0].ObjectValue()["type"].StringValue() != "user_member" {
		t.Fatalf("expected the responder alone (PUSER01) in the rotation, got %v", users)
	}

	services := m.byType("pagerduty:index/service:Service")
	serviceByName := map[string]recordedResource{}
	for _, svc := range services {
		serviceByName[svc.Name] = svc
	}
	if _, ok := serviceByName["sentry"]; len(services) != len(s.Services) || !ok {
		t.Fatalf("expected %d services including sentry, got %+v", len(s.Services), services)
	}
	for _, svc := range services {
		rule := svc.Inputs["incidentUrgencyRule"].ObjectValue()
		if rule["type"].StringValue() != "constant" || rule["urgency"].StringValue() != UrgencySeverityBased {
			t.Fatalf("service %s: urgency rule = %v, want constant/%s so warnings stay low urgency", svc.Name, rule, UrgencySeverityBased)
		}
	}
	svc := serviceByName["sentry"]
	if got := svc.Inputs["escalationPolicy"].StringValue(); got != "PESCPOL01" {
		t.Fatalf("expected sentry service to reference PESCPOL01, got %q", got)
	}
	if got := svc.Inputs["alertCreation"].StringValue(); got != "create_alerts_and_incidents" {
		t.Fatalf("expected alertCreation create_alerts_and_incidents, got %q", got)
	}

	integrations := m.byType("pagerduty:index/serviceIntegration:ServiceIntegration")
	integrationByName := map[string]recordedResource{}
	for _, in := range integrations {
		integrationByName[in.Name] = in
	}
	for _, svc := range s.Services {
		if _, ok := integrationByName[svc.Key+"-events-v2"]; !ok {
			t.Fatalf("no Events API v2 integration for service %q, got %+v", svc.Key, integrations)
		}
	}
	if len(integrations) != len(s.Services) {
		t.Fatalf("expected %d integrations, got %d", len(s.Services), len(integrations))
	}
	integ := integrationByName["sentry-events-v2"]
	if got := integ.Inputs["type"].StringValue(); got != "events_api_v2_inbound_integration" {
		t.Fatalf("expected integration type events_api_v2_inbound_integration, got %q", got)
	}
	if got := integ.Inputs["name"].StringValue(); got != "Sentry (Events API v2)" {
		t.Fatalf("expected integration display name %q, got %q", "Sentry (Events API v2)", got)
	}
	if got := integ.Inputs["service"].StringValue(); got != "PSVC_sentry" {
		t.Fatalf("expected integration service PSVC_sentry, got %q", got)
	}

	if !sentryIntegKeySec || sentryIntegKey != "fake-routing-key-0000000000000001" {
		t.Fatalf("expected sentryIntegrationKey to be a secret output with mocked key, secret=%v val=%q", sentryIntegKeySec, sentryIntegKey)
	}
	if policySecret || policyID != "PESCPOL01" {
		t.Fatalf("expected plain-text escalationPolicyId PESCPOL01, secret=%v id=%q", policySecret, policyID)
	}
	if sentryServiceSec || sentryServiceID != "PSVC_sentry" {
		t.Fatalf("expected plain-text sentryServiceId PSVC_sentry, secret=%v id=%q", sentryServiceSec, sentryServiceID)
	}
}

func TestResourceNamesDeriveFromServiceKey(t *testing.T) {
	s := validSettings()
	s.Services[0].Name = "Renamed Sentry Display"
	m := &pagerdutyMocks{}

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		provider, err := pagerduty.NewProvider(ctx, "pagerduty", &pagerduty.ProviderArgs{
			Token: pulumi.ToSecret(pulumi.String("mock-token")).(pulumi.StringOutput),
		})
		if err != nil {
			return err
		}
		_, err = Reconcile(ctx, provider, s)
		return err
	}, pulumi.WithMocks("vitruvian-pagerduty", "production", m))
	if err != nil {
		t.Fatalf("mocked run failed: %v", err)
	}

	services := m.byType("pagerduty:index/service:Service")
	if len(services) != 1 || services[0].Name != "sentry" {
		t.Fatalf("expected stable Pulumi resource name sentry, got %+v", services)
	}
	if got := services[0].Inputs["name"].StringValue(); got != "Renamed Sentry Display" {
		t.Fatalf("expected updated display name, got %q", got)
	}

	integrations := m.byType("pagerduty:index/serviceIntegration:ServiceIntegration")
	if len(integrations) != 1 || integrations[0].Name != "sentry-events-v2" {
		t.Fatalf("expected stable integration resource name sentry-events-v2, got %+v", integrations)
	}
	if got := integrations[0].Inputs["name"].StringValue(); got != "Renamed Sentry Display (Events API v2)" {
		t.Fatalf("expected updated integration name, got %q", got)
	}
}

func TestEscalationPolicyImportsOnlyWhenAdoptIDSet(t *testing.T) {
	cases := []struct {
		name    string
		adoptID string
	}{
		{name: "adoptId set", adoptID: "PS9GPWM"},
		{name: "adoptId empty", adoptID: ""},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := validSettings()
			s.Escalation.AdoptID = tc.adoptID
			m := &pagerdutyMocks{}

			err := pulumi.RunErr(func(ctx *pulumi.Context) error {
				provider, err := pagerduty.NewProvider(ctx, "pagerduty", &pagerduty.ProviderArgs{
					Token: pulumi.ToSecret(pulumi.String("mock-token")).(pulumi.StringOutput),
				})
				if err != nil {
					return err
				}
				_, err = Reconcile(ctx, provider, s)
				return err
			}, pulumi.WithMocks("vitruvian-pagerduty", "production", m))
			if err != nil {
				t.Fatalf("mocked run failed: %v", err)
			}

			policies := m.byType("pagerduty:index/escalationPolicy:EscalationPolicy")
			if len(policies) != 1 {
				t.Fatalf("expected 1 escalation policy, got %d", len(policies))
			}
			if policies[0].ImportID != tc.adoptID {
				t.Fatalf("expected ImportID %q, got %q", tc.adoptID, policies[0].ImportID)
			}
		})
	}
}

func TestStackConfigRejectsUnknownKeys(t *testing.T) {
	for name, extra := range map[string]string{
		"token under a new key":         "  vitruvian-pagerduty:apiKey: y_NbAkKc66ryYTWUXYEu\n",
		"provider key other than token": "  pagerduty:serviceRegion: us\n",
	} {
		t.Run(name, func(t *testing.T) {
			raw := []byte("config:\n" + extra +
				"  vitruvian-pagerduty:responderEmail: a@b.dev\n" +
				"  vitruvian-pagerduty:escalation: {name: x, delayMinutes: 30, loops: 0}\n" +
				"  vitruvian-pagerduty:services: [{key: sentry, name: Sentry}]\n")
			if _, err := checkStackConfigBytes(raw); err == nil || !strings.Contains(err.Error(), "unexpected config key") {
				t.Fatalf("want unexpected-config-key error, got %v", err)
			}
		})
	}
}

func TestScheduleRotatesMembersInOrder(t *testing.T) {
	s := validSettings()
	s.Schedule.Members = []string{"second@example.com", "first@example.com"}
	m := &pagerdutyMocks{}

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		provider, err := pagerduty.NewProvider(ctx, "pagerduty", &pagerduty.ProviderArgs{
			Token: pulumi.ToSecret(pulumi.String("mock-token")).(pulumi.StringOutput),
		})
		if err != nil {
			return err
		}
		_, err = Reconcile(ctx, provider, s)
		return err
	}, pulumi.WithMocks("vitruvian-pagerduty", "production", m))
	if err != nil {
		t.Fatalf("mocked run failed: %v", err)
	}

	var looked []string
	for _, inv := range m.invokes {
		looked = append(looked, inv.Args["email"].StringValue())
	}
	if strings.Join(looked, ",") != "second@example.com,first@example.com" {
		t.Fatalf("members must be looked up in rotation order, got %v", looked)
	}
	for _, inv := range m.invokes {
		if inv.Args["email"].StringValue() == s.ResponderEmail {
			t.Fatal("an explicit member list must replace the responder, not add to it")
		}
	}
	ev := m.byType("pagerduty:index/schedulev2:Schedulev2")[0].Inputs["rotations"].ArrayValue()[0].ObjectValue()["events"].ArrayValue()[0].ObjectValue()
	if n := len(ev["assignmentStrategies"].ArrayValue()[0].ObjectValue()["members"].ArrayValue()); n != 2 {
		t.Fatalf("expected 2 users in the rotation, got %d", n)
	}
}

func TestRecurrence(t *testing.T) {
	for days, want := range map[int]string{
		1:  "RRULE:FREQ=DAILY",
		3:  "RRULE:FREQ=DAILY;INTERVAL=3",
		7:  "RRULE:FREQ=WEEKLY",
		14: "RRULE:FREQ=WEEKLY;INTERVAL=2",
	} {
		if got := Recurrence(days); got != want {
			t.Errorf("Recurrence(%d) = %q, want %q", days, got, want)
		}
	}
}

func TestNotificationRules(t *testing.T) {
	s := validSettings()
	s.NotificationRules = []NotificationRule{
		{Urgency: "high", Type: "push_notification_contact_method", Label: "Phone", DelayMinutes: 0, AdoptID: "PRULE01"},
		{Urgency: "high", Type: "sms_contact_method", Label: "Mobile", DelayMinutes: 5},
		{Urgency: "low", Type: "email_contact_method", Label: "Default", DelayMinutes: 0},
	}
	m := &pagerdutyMocks{}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		provider, err := pagerduty.NewProvider(ctx, "pagerduty", &pagerduty.ProviderArgs{
			Token: pulumi.ToSecret(pulumi.String("mock-token")).(pulumi.StringOutput),
		})
		if err != nil {
			return err
		}
		_, err = Reconcile(ctx, provider, s)
		return err
	}, pulumi.WithMocks("vitruvian-pagerduty", "production", m))
	if err != nil {
		t.Fatalf("mocked run failed: %v", err)
	}

	users := 0
	for _, inv := range m.invokes {
		switch inv.Token {
		case "pagerduty:index/getUser:getUser":
			users++
		case "pagerduty:index/getUserContactMethod:getUserContactMethod":
			if inv.Args["userId"].StringValue() != "PUSER01" {
				t.Fatalf("contact method looked up on the wrong user: %v", inv.Args)
			}
		}
	}
	if users != 1 {
		t.Fatalf("the responder is both member and rule owner; want 1 user lookup, got %d", users)
	}

	rules := map[string]recordedResource{}
	for _, r := range m.byType("pagerduty:index/userNotificationRule:UserNotificationRule") {
		rules[r.Name] = r
	}
	if len(rules) != 3 {
		t.Fatalf("expected 3 rules, got %v", rules)
	}
	push, sms, low := rules["notify-high-push-notification"], rules["notify-high-sms"], rules["notify-low-email"]
	if push.ImportID != "PUSER01:PRULE01" || sms.ImportID != "" || low.ImportID != "" {
		t.Fatalf("only the rule with adoptId may be imported: push=%q sms=%q low=%q", push.ImportID, sms.ImportID, low.ImportID)
	}
	if got := sms.Inputs["startDelayInMinutes"].NumberValue(); got != 5 {
		t.Fatalf("sms delay = %v, want 5", got)
	}
	if got := low.Inputs["urgency"].StringValue(); got != "low" {
		t.Fatalf("low rule urgency = %q", got)
	}
	cm := sms.Inputs["contactMethod"].ObjectValue()
	if cm["id"].StringValue() != "PCM_sms_contact_method" || cm["type"].StringValue() != "sms_contact_method" {
		t.Fatalf("sms rule must point at the looked-up sms contact method, got %v", cm)
	}
	if got := sms.Inputs["userId"].StringValue(); got != "PUSER01" {
		t.Fatalf("rule userId = %q, want PUSER01", got)
	}
}

func TestNoNotificationRulesLeavesUserAlone(t *testing.T) {
	m := &pagerdutyMocks{}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		provider, err := pagerduty.NewProvider(ctx, "pagerduty", &pagerduty.ProviderArgs{
			Token: pulumi.ToSecret(pulumi.String("mock-token")).(pulumi.StringOutput),
		})
		if err != nil {
			return err
		}
		_, err = Reconcile(ctx, provider, validSettings())
		return err
	}, pulumi.WithMocks("vitruvian-pagerduty", "production", m))
	if err != nil {
		t.Fatalf("mocked run failed: %v", err)
	}
	if n := len(m.byType("pagerduty:index/userNotificationRule:UserNotificationRule")); n != 0 {
		t.Fatalf("no notificationRules config must manage no rules, got %d", n)
	}
}

func depSettings() Settings {
	s := validSettings()
	s.Services = []Service{{Key: "cluster", Name: "Cluster"}, {Key: "ci", Name: "CI"}, {Key: "data", Name: "Data"}}
	return s
}

func TestValidateDependencies(t *testing.T) {
	cases := map[string]struct {
		deps []Dependency
		biz  []BusinessService
		want string
	}{
		"unknown service":     {deps: []Dependency{{Service: "web", DependsOn: []string{"cluster"}}}, want: "dependencies[0].service"},
		"unknown supporter":   {deps: []Dependency{{Service: "ci", DependsOn: []string{"web"}}}, want: "dependsOn \"web\""},
		"no supporters":       {deps: []Dependency{{Service: "ci"}}, want: "at least one"},
		"self":                {deps: []Dependency{{Service: "ci", DependsOn: []string{"ci"}}}, want: "itself"},
		"repeat":              {deps: []Dependency{{Service: "ci", DependsOn: []string{"cluster"}}, {Service: "ci", DependsOn: []string{"cluster"}}}, want: "already depends"},
		"cycle":               {deps: []Dependency{{Service: "ci", DependsOn: []string{"data"}}, {Service: "data", DependsOn: []string{"cluster"}}, {Service: "cluster", DependsOn: []string{"ci"}}}, want: "cycle: ci -> data -> cluster -> ci"},
		"business bad key":    {biz: []BusinessService{{Key: "Home", Name: "H", DependsOn: []string{"ci"}}}, want: "businessServices[0].key"},
		"business key clash":  {biz: []BusinessService{{Key: "ci", Name: "H", DependsOn: []string{"cluster"}}}, want: "already used"},
		"business no name":    {biz: []BusinessService{{Key: "home", DependsOn: []string{"ci"}}}, want: "businessServices[0].name"},
		"business unknown":    {biz: []BusinessService{{Key: "home", Name: "H", DependsOn: []string{"web"}}}, want: "is not a services key"},
		"business repeat":     {biz: []BusinessService{{Key: "home", Name: "H", DependsOn: []string{"ci", "ci"}}}, want: "repeats"},
		"business no members": {biz: []BusinessService{{Key: "home", Name: "H"}}, want: "at least one"},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			s := depSettings()
			s.Dependencies, s.BusinessServices = tc.deps, tc.biz
			err := s.Validate()
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("want error containing %q, got %v", tc.want, err)
			}
		})
	}
	ok := depSettings()
	ok.Dependencies = []Dependency{{Service: "ci", DependsOn: []string{"cluster"}}, {Service: "data", DependsOn: []string{"cluster"}}}
	ok.BusinessServices = []BusinessService{{Key: "home", Name: "Home", DependsOn: []string{"ci", "data"}}}
	if err := ok.Validate(); err != nil {
		t.Fatalf("a valid map must pass: %v", err)
	}
}

func TestDependencyResources(t *testing.T) {
	s := depSettings()
	s.Dependencies = []Dependency{{Service: "ci", DependsOn: []string{"cluster", "data"}}}
	s.BusinessServices = []BusinessService{{Key: "home", Name: "Home", Description: "d", DependsOn: []string{"cluster"}}}
	m := &pagerdutyMocks{}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		provider, err := pagerduty.NewProvider(ctx, "pagerduty", &pagerduty.ProviderArgs{
			Token: pulumi.ToSecret(pulumi.String("mock-token")).(pulumi.StringOutput),
		})
		if err != nil {
			return err
		}
		_, err = Reconcile(ctx, provider, s)
		return err
	}, pulumi.WithMocks("vitruvian-pagerduty", "production", m))
	if err != nil {
		t.Fatalf("mocked run failed: %v", err)
	}
	deps := map[string]recordedResource{}
	for _, r := range m.byType("pagerduty:index/serviceDependency:ServiceDependency") {
		deps[r.Name] = r
	}
	if len(deps) != 3 {
		t.Fatalf("want one dependency per pair (3), got %v", deps)
	}
	pair := func(name string) (string, string, string, string) {
		d := deps[name].Inputs["dependency"].ObjectValue()
		dep := d["dependentServices"].ArrayValue()[0].ObjectValue()
		sup := d["supportingServices"].ArrayValue()[0].ObjectValue()
		return dep["id"].StringValue(), dep["type"].StringValue(), sup["id"].StringValue(), sup["type"].StringValue()
	}
	if a, at, b, bt := pair("dep-ci-on-cluster"); a != "PSVC_ci" || at != "service" || b != "PSVC_cluster" || bt != "service" {
		t.Fatalf("ci on cluster = %s/%s on %s/%s", a, at, b, bt)
	}
	if _, _, b, _ := pair("dep-ci-on-data"); b != "PSVC_data" {
		t.Fatalf("ci on data supporter = %s", b)
	}
	if a, at, b, _ := pair("dep-business-home-on-cluster"); a != "PBIZ_business-home" || at != "business_service" || b != "PSVC_cluster" {
		t.Fatalf("business dependency = %s/%s on %s", a, at, b)
	}
	biz := m.byType("pagerduty:index/businessService:BusinessService")
	if len(biz) != 1 || biz[0].Inputs["name"].StringValue() != "Home" {
		t.Fatalf("want one business service named Home, got %+v", biz)
	}
	if _, hasTeam := biz[0].Inputs["team"]; hasTeam {
		t.Fatal("business service must not set team: Business/Enterprise only")
	}
}
