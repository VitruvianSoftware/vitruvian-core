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
	if len(s.Services) != 1 || s.Services[0].Key != "sentry" {
		t.Fatalf("expected initial sentry service, got %+v", s.Services)
	}
}

func TestPlaintextTokenGuardRejectsSecrets(t *testing.T) {
	baseYAML := `config:
  vitruvian-pagerduty:responderEmail: responder@example.com
  vitruvian-pagerduty:escalation:
    name: Vitruvian on-call
    delayMinutes: 30
    loops: 2
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
	case "pagerduty:index/service:Service":
		id = "PSVC_" + args.Name
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

	if len(m.invokes) != 1 || m.invokes[0].Token != "pagerduty:index/getUser:getUser" {
		t.Fatalf("expected 1 getUser invoke, got %+v", m.invokes)
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
	if targetObj["type"].StringValue() != "user_reference" || targetObj["id"].StringValue() != "PUSER01" {
		t.Fatalf("expected target user_reference PUSER01, got %v", targetObj)
	}

	services := m.byType("pagerduty:index/service:Service")
	if len(services) != 1 || services[0].Name != "sentry" {
		t.Fatalf("expected 1 service named sentry, got %+v", services)
	}
	svc := services[0]
	if got := svc.Inputs["escalationPolicy"].StringValue(); got != "PESCPOL01" {
		t.Fatalf("expected sentry service to reference PESCPOL01, got %q", got)
	}
	if got := svc.Inputs["alertCreation"].StringValue(); got != "create_alerts_and_incidents" {
		t.Fatalf("expected alertCreation create_alerts_and_incidents, got %q", got)
	}

	integrations := m.byType("pagerduty:index/serviceIntegration:ServiceIntegration")
	if len(integrations) != 1 || integrations[0].Name != "sentry-events-v2" {
		t.Fatalf("expected 1 integration named sentry-events-v2, got %+v", integrations)
	}
	integ := integrations[0]
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
