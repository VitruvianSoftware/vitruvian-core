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

package alerts

import (
	"fmt"
	"os"
	"regexp"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi-terraform-provider/sdks/go/sentry/sentry"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"gopkg.in/yaml.v3"
)

func validSettings() Settings {
	return Settings{
		Organization:     "sentry",
		BaseURL:          "https://sentry.lab.ipv1337.dev/api/",
		IntegrationName:  "Vitruvian Software",
		PagerDutyStack:   "ipv1337/vitruvian-pagerduty/production",
		ServiceName:      "Sentry",
		Severity:         "default",
		ExcludeProjects:  []string{"internal"},
		FrequencyMinutes: 30,
	}
}

func TestValidateAcceptsGoodConfig(t *testing.T) {
	for _, sev := range []string{"default", "critical", "warning", "error", "info"} {
		s := validSettings()
		s.Severity = sev
		if err := s.Validate(); err != nil {
			t.Fatalf("expected severity %q to be valid, got %v", sev, err)
		}
	}
}

func TestValidateRejectsBadConfig(t *testing.T) {
	cases := map[string]struct {
		mutate func(*Settings)
		want   string
	}{
		"empty organization": {
			mutate: func(s *Settings) { s.Organization = "" },
			want:   "organization",
		},
		"uppercase organization": {
			mutate: func(s *Settings) { s.Organization = "Sentry" },
			want:   "organization",
		},
		"empty baseUrl": {
			mutate: func(s *Settings) { s.BaseURL = "" },
			want:   "baseUrl",
		},
		"http baseUrl": {
			mutate: func(s *Settings) { s.BaseURL = "http://sentry.lab.ipv1337.dev/api/" },
			want:   "baseUrl",
		},
		"baseUrl missing /api/": {
			mutate: func(s *Settings) { s.BaseURL = "https://sentry.lab.ipv1337.dev" },
			want:   "/api/",
		},
		"baseUrl with query": {
			mutate: func(s *Settings) { s.BaseURL = "https://sentry.lab.ipv1337.dev/api/?x=1" },
			want:   "baseUrl",
		},
		"blank integrationName": {
			mutate: func(s *Settings) { s.IntegrationName = "   " },
			want:   "integrationName",
		},
		"bad pagerdutyStack": {
			mutate: func(s *Settings) { s.PagerDutyStack = "vitruvian-pagerduty/production" },
			want:   "pagerdutyStack",
		},
		"empty pagerdutyStack segment": {
			mutate: func(s *Settings) { s.PagerDutyStack = "ipv1337//production" },
			want:   "pagerdutyStack segment",
		},
		"blank serviceName": {
			mutate: func(s *Settings) { s.ServiceName = " Sentry " },
			want:   "serviceName",
		},
		"invalid severity": {
			mutate: func(s *Settings) { s.Severity = "urgent" },
			want:   "severity",
		},
		"missing internal exclusion": {
			mutate: func(s *Settings) { s.ExcludeProjects = []string{"sandbox"} },
			want:   `excludeProjects must include "internal"`,
		},
		"empty excludeProjects element": {
			mutate: func(s *Settings) { s.ExcludeProjects = []string{"internal", ""} },
			want:   "excludeProjects[1]",
		},
		"duplicate excludeProjects": {
			mutate: func(s *Settings) { s.ExcludeProjects = []string{"internal", "internal"} },
			want:   "duplicated",
		},
		"zero frequencyMinutes": {
			mutate: func(s *Settings) { s.FrequencyMinutes = 0 },
			want:   "frequencyMinutes",
		},
		"negative frequencyMinutes": {
			mutate: func(s *Settings) { s.FrequencyMinutes = -10 },
			want:   "frequencyMinutes",
		},
		"unsupported frequencyMinutes": {
			mutate: func(s *Settings) { s.FrequencyMinutes = 7 },
			want:   "frequencyMinutes",
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

var (
	// Matches modern Sentry user/org/app tokens (sntrys_, sntryu_, sntryr_)
	// and legacy 64-hex auth tokens.
	sentryTokenPattern    = regexp.MustCompile(`^sntry[sur]_[A-Za-z0-9_=-]{16,}$`)
	sentryHexTokenPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

func scanForPlaintextTokens(node *yaml.Node, path string) error {
	if node == nil {
		return nil
	}
	if node.Kind == yaml.ScalarNode && node.Tag == "!!str" {
		val := strings.TrimSpace(node.Value)
		if sentryTokenPattern.MatchString(val) || sentryHexTokenPattern.MatchString(val) {
			return fmt.Errorf("YAML value at %s resembles a plaintext Sentry API token", path)
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

	// If sentry:token appears at all, it must be Pulumi ciphertext (`secure:`),
	// never a plaintext scalar string.
	if n, ok := doc.Config["sentry:token"]; ok {
		var secure struct {
			Secure string `yaml:"secure"`
		}
		if n.Kind != yaml.MappingNode || n.Decode(&secure) != nil || strings.TrimSpace(secure.Secure) == "" {
			return Settings{}, fmt.Errorf("sentry:token must be encrypted Pulumi ciphertext, never plaintext")
		}
	}

	// Allowlist: reject any key not named here so a pasted secret fails even if unrecognized.
	allowed := map[string]bool{
		Namespace + ":organization":     true,
		Namespace + ":baseUrl":          true,
		Namespace + ":integrationName":  true,
		Namespace + ":pagerdutyStack":   true,
		Namespace + ":serviceName":      true,
		Namespace + ":severity":         true,
		Namespace + ":excludeProjects":  true,
		Namespace + ":frequencyMinutes": true,
		"sentry:token":                  true, // only as ciphertext, checked above
	}
	for k := range doc.Config {
		if !allowed[k] {
			return Settings{}, fmt.Errorf("unexpected config key %q", k)
		}
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
	if err := decode("organization", &s.Organization); err != nil {
		return Settings{}, err
	}
	if err := decode("baseUrl", &s.BaseURL); err != nil {
		return Settings{}, err
	}
	if err := decode("integrationName", &s.IntegrationName); err != nil {
		return Settings{}, err
	}
	if err := decode("pagerdutyStack", &s.PagerDutyStack); err != nil {
		return Settings{}, err
	}
	if err := decode("serviceName", &s.ServiceName); err != nil {
		return Settings{}, err
	}
	if err := decode("severity", &s.Severity); err != nil {
		return Settings{}, err
	}
	if err := decode("excludeProjects", &s.ExcludeProjects); err != nil {
		return Settings{}, err
	}
	if err := decode("frequencyMinutes", &s.FrequencyMinutes); err != nil {
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
	if s.Organization != "sentry" {
		t.Fatalf("unexpected organization: %q", s.Organization)
	}
	if s.BaseURL != "https://sentry.lab.ipv1337.dev/api/" {
		t.Fatalf("unexpected baseUrl: %q", s.BaseURL)
	}
	if s.IntegrationName != "Vitruvian Software" {
		t.Fatalf("unexpected integrationName: %q", s.IntegrationName)
	}
	if s.PagerDutyStack != "ipv1337/vitruvian-pagerduty/production" {
		t.Fatalf("unexpected pagerdutyStack: %q", s.PagerDutyStack)
	}
	if s.ServiceName != "Sentry" {
		t.Fatalf("unexpected serviceName: %q", s.ServiceName)
	}
	if s.Severity != "default" {
		t.Fatalf("unexpected severity: %q", s.Severity)
	}
	if len(s.ExcludeProjects) != 1 || s.ExcludeProjects[0] != "internal" {
		t.Fatalf("expected excludeProjects=[internal], got %+v", s.ExcludeProjects)
	}
	if s.FrequencyMinutes != 30 {
		t.Fatalf("expected frequencyMinutes=30, got %d", s.FrequencyMinutes)
	}
}

func TestPlaintextTokenGuardRejectsSecrets(t *testing.T) {
	baseYAML := `config:
  vitruvian-sentry-pagerduty:organization: sentry
  vitruvian-sentry-pagerduty:baseUrl: https://sentry.lab.ipv1337.dev/api/
  vitruvian-sentry-pagerduty:integrationName: Vitruvian Software
  vitruvian-sentry-pagerduty:pagerdutyStack: ipv1337/vitruvian-pagerduty/production
  vitruvian-sentry-pagerduty:serviceName: Sentry
  vitruvian-sentry-pagerduty:severity: default
  vitruvian-sentry-pagerduty:excludeProjects: [internal]
  vitruvian-sentry-pagerduty:frequencyMinutes: 30
`
	if _, err := checkStackConfigBytes([]byte(baseYAML + "  sentry:token: plaintext-value\n")); err == nil {
		t.Fatal("expected guard to reject plaintext sentry:token")
	}
	if _, err := checkStackConfigBytes([]byte(baseYAML + "  vitruvian-sentry-pagerduty:token:\n    secure: v1:fake\n")); err == nil {
		t.Fatal("expected guard to reject vitruvian-sentry-pagerduty:token")
	}
	// Construct fake token fixtures dynamically so secret scanners never flag test lines.
	fakeModernToken := "sntrys_" + strings.Repeat("A", 24)
	if _, err := checkStackConfigBytes([]byte(baseYAML + "  vitruvian-sentry-pagerduty:extra: " + fakeModernToken + "\n")); err == nil {
		t.Fatal("expected guard to reject value matching Sentry sntrys_ token pattern")
	}
	fakeHexToken := strings.Repeat("ab", 32)
	if _, err := checkStackConfigBytes([]byte(baseYAML + "  vitruvian-sentry-pagerduty:extra: " + fakeHexToken + "\n")); err == nil {
		t.Fatal("expected guard to reject value matching 64-hex legacy Sentry token pattern")
	}
	if _, err := checkStackConfigBytes([]byte(baseYAML + "  sentry:token:\n    secure: v1:encrypted-blob\n")); err != nil {
		t.Fatalf("expected encrypted sentry:token to pass, got %v", err)
	}
}

func TestStackConfigRejectsUnknownKeys(t *testing.T) {
	for name, extra := range map[string]string{
		"token under a new key":         "  vitruvian-sentry-pagerduty:authToken: abc\n",
		"provider key other than token": "  sentry:baseUrl: https://example.com/api/\n",
	} {
		t.Run(name, func(t *testing.T) {
			raw := []byte("config:\n" + extra +
				"  vitruvian-sentry-pagerduty:organization: sentry\n" +
				"  vitruvian-sentry-pagerduty:baseUrl: https://sentry.lab.ipv1337.dev/api/\n" +
				"  vitruvian-sentry-pagerduty:integrationName: Vitruvian Software\n" +
				"  vitruvian-sentry-pagerduty:pagerdutyStack: ipv1337/vitruvian-pagerduty/production\n" +
				"  vitruvian-sentry-pagerduty:serviceName: Sentry\n" +
				"  vitruvian-sentry-pagerduty:severity: default\n" +
				"  vitruvian-sentry-pagerduty:excludeProjects: [internal]\n" +
				"  vitruvian-sentry-pagerduty:frequencyMinutes: 30\n")
			if _, err := checkStackConfigBytes(raw); err == nil || !strings.Contains(err.Error(), "unexpected config key") {
				t.Fatalf("want unexpected-config-key error, got %v", err)
			}
		})
	}
}

type recordedResource struct {
	Type   string
	Name   string
	ID     string
	Inputs resource.PropertyMap
}

type recordedInvoke struct {
	Token string
	Args  resource.PropertyMap
}

type sentryMocks struct {
	mu          sync.Mutex
	invokes     []recordedInvoke
	resources   []recordedResource
	projectList []string
}

func (m *sentryMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	m.mu.Lock()
	m.invokes = append(m.invokes, recordedInvoke{Token: args.Token, Args: args.Args})
	m.mu.Unlock()

	switch args.Token {
	case "sentry:index/getOrganizationIntegration:getOrganizationIntegration":
		return resource.PropertyMap{
			"id":           resource.NewStringProperty("42"),
			"internalId":   resource.NewStringProperty("42"),
			"name":         args.Args["name"],
			"organization": args.Args["organization"],
			"providerKey":  args.Args["providerKey"],
			"rawJson":      resource.NewStringProperty("{}"),
		}, nil
	case "sentry:index/getAllProjects:getAllProjects":
		projects := make([]resource.PropertyValue, 0, len(m.projectList))
		for i, slug := range m.projectList {
			projects = append(projects, resource.NewObjectProperty(resource.PropertyMap{
				"color":       resource.NewStringProperty("#000000"),
				"dateCreated": resource.NewStringProperty("2026-01-01T00:00:00Z"),
				"features":    resource.NewArrayProperty([]resource.PropertyValue{}),
				"internalId":  resource.NewStringProperty(fmt.Sprintf("%d", i+1)),
				"name":        resource.NewStringProperty(slug),
				"platform":    resource.NewStringProperty("go"),
				"slug":        resource.NewStringProperty(slug),
				"teams":       resource.NewArrayProperty([]resource.PropertyValue{}),
			}))
		}
		return resource.PropertyMap{
			"organization": args.Args["organization"],
			"projects":     resource.NewArrayProperty(projects),
		}, nil
	case "sentry:index/getProjectErrorMonitor:getProjectErrorMonitor":
		proj := args.Args["project"].StringValue()
		return resource.PropertyMap{
			"description":  resource.NewStringProperty("Default Error Monitor"),
			"enabled":      resource.NewBoolProperty(true),
			"id":           resource.NewStringProperty("mon-" + proj),
			"name":         resource.NewStringProperty("New Errors"),
			"organization": args.Args["organization"],
			"project":      resource.NewStringProperty(proj),
			"owner":        resource.NewObjectProperty(resource.PropertyMap{}),
		}, nil
	default:
		return args.Args, nil
	}
}

func (m *sentryMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	outputs := resource.PropertyMap{}
	for k, v := range args.Inputs {
		outputs[k] = v
	}

	var id string
	switch args.TypeToken {
	case "pulumi:pulumi:StackReference":
		id = args.Inputs["name"].StringValue()
		outputs["outputs"] = resource.NewObjectProperty(resource.PropertyMap{
			"sentryIntegrationKey": resource.MakeSecret(resource.NewStringProperty("mock-pd-routing-key-secret")),
		})
	case "sentry:index/integrationPagerduty:IntegrationPagerduty":
		id = "pd-svc-row-99"
	case "sentry:index/alert:Alert":
		id = "wf-" + strings.TrimPrefix(args.Name, "alert-")
	default:
		id = args.Name + "_id"
	}

	m.mu.Lock()
	m.resources = append(m.resources, recordedResource{
		Type:   args.TypeToken,
		Name:   args.Name,
		ID:     id,
		Inputs: args.Inputs,
	})
	m.mu.Unlock()

	return id, outputs, nil
}

func (m *sentryMocks) byType(typ string) []recordedResource {
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
	m := &sentryMocks{
		// Deliberately unsorted and includes `internal`, which must be skipped.
		projectList: []string{"vitruvian-wand", "internal", "backstage"},
	}

	var (
		outIntegrationID     string
		outIntegrationSec    bool
		outPagerDutySvcID    string
		outPagerDutySvcSec   bool
		outAlertIDs          map[string]string
		outAlertIDsHasSecret bool
	)

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		provider, err := sentry.NewProvider(ctx, "sentry", &sentry.ProviderArgs{
			BaseUrl: pulumi.String(s.BaseURL),
			Token:   pulumi.ToSecret(pulumi.String("mock-sentry-token")).(pulumi.StringOutput),
		})
		if err != nil {
			return err
		}
		out, err := Reconcile(ctx, provider, s)
		if err != nil {
			return err
		}

		outIntegrationSec = pulumi.IsSecret(out.IntegrationID)
		outPagerDutySvcSec = pulumi.IsSecret(out.PagerDutyServiceID)

		chStr := make(chan string, 1)
		out.IntegrationID.ApplyT(func(v string) string {
			chStr <- v
			return v
		})
		outIntegrationID = <-chStr

		chSvc := make(chan string, 1)
		out.PagerDutyServiceID.ApplyT(func(v string) string {
			chSvc <- v
			return v
		})
		outPagerDutySvcID = <-chSvc

		outAlertIDs = make(map[string]string, len(out.AlertIDs))
		for slug, idOut := range out.AlertIDs {
			idStrOut := idOut.ToStringOutput()
			if pulumi.IsSecret(idStrOut) {
				outAlertIDsHasSecret = true
			}
			ch := make(chan string, 1)
			idStrOut.ApplyT(func(v string) string {
				ch <- v
				return v
			})
			outAlertIDs[slug] = <-ch
		}
		return nil
	}, pulumi.WithMocks("vitruvian-sentry-pagerduty", "production", m))
	if err != nil {
		t.Fatalf("mocked run failed: %v", err)
	}

	// Verify StackReference lookup.
	stackRefs := m.byType("pulumi:pulumi:StackReference")
	if len(stackRefs) != 1 || stackRefs[0].Inputs["name"].StringValue() != "ipv1337/vitruvian-pagerduty/production" {
		t.Fatalf("expected 1 StackReference to ipv1337/vitruvian-pagerduty/production, got %+v", stackRefs)
	}

	// Verify exactly one sentry_integration_pagerduty with secret routing key.
	pdServices := m.byType("sentry:index/integrationPagerduty:IntegrationPagerduty")
	if len(pdServices) != 1 {
		t.Fatalf("expected 1 IntegrationPagerduty resource, got %d", len(pdServices))
	}
	pdSvc := pdServices[0]
	if got := pdSvc.Inputs["organization"].StringValue(); got != "sentry" {
		t.Fatalf("expected integration organization=sentry, got %q", got)
	}
	if got := pdSvc.Inputs["integrationId"].StringValue(); got != "42" {
		t.Fatalf("expected integrationId=42, got %q", got)
	}
	if got := pdSvc.Inputs["service"].StringValue(); got != "Sentry" {
		t.Fatalf("expected service=Sentry, got %q", got)
	}
	keyProp := pdSvc.Inputs["integrationKey"]
	if !keyProp.IsSecret() {
		t.Fatal("expected IntegrationPagerduty.integrationKey to remain a Pulumi secret")
	}
	if got := keyProp.SecretValue().Element.StringValue(); got != "mock-pd-routing-key-secret" {
		t.Fatalf("unexpected mocked routing key value %q", got)
	}

	// Verify monitor lookups happen in sorted slug order and skip internal.
	var monitorSlugs []string
	m.mu.Lock()
	for _, inv := range m.invokes {
		if inv.Token == "sentry:index/getProjectErrorMonitor:getProjectErrorMonitor" {
			monitorSlugs = append(monitorSlugs, inv.Args["project"].StringValue())
		}
	}
	m.mu.Unlock()
	wantSlugs := []string{"backstage", "vitruvian-wand"}
	if len(monitorSlugs) != len(wantSlugs) || monitorSlugs[0] != wantSlugs[0] || monitorSlugs[1] != wantSlugs[1] {
		t.Fatalf("expected sorted monitor lookups %v, got %v", wantSlugs, monitorSlugs)
	}

	// Verify one alert per non-excluded project keyed by alert-<slug>, and none for internal.
	// ResourceMonitor runs RegisterResource goroutines concurrently while resolving outputs,
	// so index recorded alerts by resource name rather than arrival order.
	alerts := m.byType("sentry:index/alert:Alert")
	if len(alerts) != len(wantSlugs) {
		t.Fatalf("expected %d alerts (%v), got %d", len(wantSlugs), wantSlugs, len(alerts))
	}
	alertsByName := make(map[string]recordedResource, len(alerts))
	for _, a := range alerts {
		alertsByName[a.Name] = a
	}
	for _, slug := range wantSlugs {
		a, ok := alertsByName["alert-"+slug]
		if !ok {
			t.Fatalf("missing expected alert resource alert-%s (got %v)", slug, alertsByName)
		}
		if got := a.Inputs["organization"].StringValue(); got != "sentry" {
			t.Fatalf("alert %q: want organization=sentry, got %q", slug, got)
		}
		wantDisplay := fmt.Sprintf("%s: page PagerDuty on high-priority issues", slug)
		if got := a.Inputs["name"].StringValue(); got != wantDisplay {
			t.Fatalf("alert %q: want name %q, got %q", slug, wantDisplay, got)
		}
		if !a.Inputs["enabled"].BoolValue() {
			t.Fatalf("alert %q: expected enabled=true", slug)
		}
		if got := a.Inputs["frequencyMinutes"].NumberValue(); got != 30 {
			t.Fatalf("alert %q: want frequencyMinutes=30, got %v", slug, got)
		}
		monitors := a.Inputs["monitorIds"].ArrayValue()
		if len(monitors) != 1 || monitors[0].StringValue() != "mon-"+slug {
			t.Fatalf("alert %q: want monitorIds=[mon-%s], got %+v", slug, slug, monitors)
		}

		triggers := a.Inputs["triggerConditions"].ArrayValue()
		if len(triggers) != 2 {
			t.Fatalf("alert %q: want 2 triggerConditions, got %d", slug, len(triggers))
		}
		if _, ok := triggers[0].ObjectValue()["firstSeenEvent"]; !ok {
			t.Fatalf("alert %q: expected triggerConditions[0] firstSeenEvent, got %v", slug, triggers[0].ObjectValue())
		}
		if _, ok := triggers[1].ObjectValue()["reappearedEvent"]; !ok {
			t.Fatalf("alert %q: expected triggerConditions[1] reappearedEvent, got %v", slug, triggers[1].ObjectValue())
		}

		filters := a.Inputs["actionFilters"].ArrayValue()
		if len(filters) != 1 {
			t.Fatalf("alert %q: want 1 actionFilter, got %d", slug, len(filters))
		}
		f := filters[0].ObjectValue()
		if f["logicType"].StringValue() != "all" {
			t.Fatalf("alert %q: want logicType=all, got %q", slug, f["logicType"].StringValue())
		}
		conds := f["conditions"].ArrayValue()
		if len(conds) != 1 {
			t.Fatalf("alert %q: want 1 filter condition, got %d", slug, len(conds))
		}
		prio := conds[0].ObjectValue()["issuePriorityGreaterOrEqual"].ObjectValue()
		if prio["comparison"].NumberValue() != 75 {
			t.Fatalf("alert %q: want priority comparison=75, got %v", slug, prio["comparison"].NumberValue())
		}

		actions := f["actions"].ArrayValue()
		if len(actions) != 1 {
			t.Fatalf("alert %q: want 1 action, got %d", slug, len(actions))
		}
		pdAction := actions[0].ObjectValue()["pagerduty"].ObjectValue()
		if pdAction["integrationId"].StringValue() != "42" {
			t.Fatalf("alert %q: want action integrationId=42, got %q", slug, pdAction["integrationId"].StringValue())
		}
		if pdAction["serviceId"].StringValue() != "pd-svc-row-99" {
			t.Fatalf("alert %q: want action serviceId=pd-svc-row-99, got %q", slug, pdAction["serviceId"].StringValue())
		}
		if pdAction["serviceName"].StringValue() != "Sentry" {
			t.Fatalf("alert %q: want action serviceName=Sentry, got %q", slug, pdAction["serviceName"].StringValue())
		}
		if pdAction["severity"].StringValue() != "default" {
			t.Fatalf("alert %q: want action severity=default, got %q", slug, pdAction["severity"].StringValue())
		}
	}

	if outIntegrationSec || outIntegrationID != "42" {
		t.Fatalf("unexpected integrationId output: secret=%v val=%q", outIntegrationSec, outIntegrationID)
	}
	if outPagerDutySvcSec || outPagerDutySvcID != "pd-svc-row-99" {
		t.Fatalf("unexpected pagerdutyServiceId output: secret=%v val=%q", outPagerDutySvcSec, outPagerDutySvcID)
	}
	if outAlertIDsHasSecret || outAlertIDs["backstage"] != "wf-backstage" || outAlertIDs["vitruvian-wand"] != "wf-vitruvian-wand" || len(outAlertIDs) != 2 {
		t.Fatalf("unexpected alertIds output: secret=%v map=%+v", outAlertIDsHasSecret, outAlertIDs)
	}
}

func TestResourceNamesDeriveFromProjectSlug(t *testing.T) {
	s := validSettings()
	s.ServiceName = "Renamed Sentry Service"
	s.ExcludeProjects = []string{"internal", "sandbox"}
	m := &sentryMocks{
		projectList: []string{"internal", "sandbox", "vitruvian-code"},
	}

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		provider, err := sentry.NewProvider(ctx, "sentry", &sentry.ProviderArgs{
			BaseUrl: pulumi.String(s.BaseURL),
			Token:   pulumi.ToSecret(pulumi.String("mock-token")).(pulumi.StringOutput),
		})
		if err != nil {
			return err
		}
		_, err = Reconcile(ctx, provider, s)
		return err
	}, pulumi.WithMocks("vitruvian-sentry-pagerduty", "production", m))
	if err != nil {
		t.Fatalf("mocked run failed: %v", err)
	}

	alerts := m.byType("sentry:index/alert:Alert")
	if len(alerts) != 1 || alerts[0].Name != "alert-vitruvian-code" {
		t.Fatalf("expected 1 alert named alert-vitruvian-code, got %+v", alerts)
	}
	if alerts[0].Inputs["monitorIds"].ArrayValue()[0].StringValue() != "mon-vitruvian-code" {
		t.Fatalf("unexpected monitorIds: %+v", alerts[0].Inputs["monitorIds"])
	}
}
