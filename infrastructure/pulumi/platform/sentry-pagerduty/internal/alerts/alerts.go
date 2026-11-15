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

// Package alerts loads, validates, and reconciles Sentry PagerDuty wiring and
// per-project workflow-engine alert rules for high-priority issues.
package alerts

import (
	"fmt"
	"net/url"
	"regexp"
	"slices"
	"strings"

	"github.com/pulumi/pulumi-terraform-provider/sdks/go/sentry/sentry"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

const (
	// Namespace is the Pulumi stack config namespace (`name:` in Pulumi.yaml).
	Namespace = "vitruvian-sentry-pagerduty"
	// PagerDutyProviderKey is Sentry's integration provider key for PagerDuty.
	PagerDutyProviderKey = "pagerduty"
	// SelfMonitoringProject is Sentry's internal telemetry project; never page on it.
	SelfMonitoringProject = "internal"
	// HighPriorityThreshold matches Sentry's PriorityLevel.HIGH (75).
	HighPriorityThreshold = 75
)

var (
	orgSlugPattern     = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*$`)
	projectSlugPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]*$`)
	stackSegmentPat    = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)

	allowedSeverities = map[string]bool{
		"default":  true,
		"critical": true,
		"warning":  true,
		"error":    true,
		"info":     true,
	}

	allowedFrequencies = map[int]bool{
		5:    true,
		10:   true,
		30:   true,
		60:   true,
		180:  true,
		720:  true,
		1440: true,
	}
)

// Settings holds the non-secret stack configuration under vitruvian-sentry-pagerduty.
type Settings struct {
	Organization     string   `json:"organization" yaml:"organization"`
	BaseURL          string   `json:"baseUrl" yaml:"baseUrl"`
	IntegrationName  string   `json:"integrationName" yaml:"integrationName"`
	PagerDutyStack   string   `json:"pagerdutyStack" yaml:"pagerdutyStack"`
	ServiceName      string   `json:"serviceName" yaml:"serviceName"`
	Severity         string   `json:"severity" yaml:"severity"`
	ExcludeProjects  []string `json:"excludeProjects" yaml:"excludeProjects"`
	FrequencyMinutes int      `json:"frequencyMinutes" yaml:"frequencyMinutes"`
}

// Outputs carries the stack outputs exported by Reconcile.
type Outputs struct {
	IntegrationID      pulumi.StringOutput
	PagerDutyServiceID pulumi.IDOutput
	AlertIDs           pulumi.StringMap
}

// Load reads Settings from cfg and validates all constraints.
func Load(cfg *config.Config) (Settings, error) {
	var s Settings
	s.Organization = cfg.Get("organization")
	s.BaseURL = cfg.Get("baseUrl")
	s.IntegrationName = cfg.Get("integrationName")
	s.PagerDutyStack = cfg.Get("pagerdutyStack")
	s.ServiceName = cfg.Get("serviceName")
	s.Severity = cfg.Get("severity")
	if err := cfg.GetObject("excludeProjects", &s.ExcludeProjects); err != nil {
		return Settings{}, fmt.Errorf("decode %s:excludeProjects: %w", Namespace, err)
	}
	s.FrequencyMinutes = cfg.GetInt("frequencyMinutes")

	if err := s.Validate(); err != nil {
		return Settings{}, err
	}
	return s, nil
}

// Validate checks that every required Sentry/PagerDuty config invariant holds.
func (s Settings) Validate() error {
	var errs []string
	add := func(format string, a ...any) { errs = append(errs, fmt.Sprintf(format, a...)) }

	if !orgSlugPattern.MatchString(s.Organization) {
		add("organization %q must match ^[a-z0-9][a-z0-9-]*$", s.Organization)
	}
	validateBaseURL(s.BaseURL, add)
	if strings.TrimSpace(s.IntegrationName) == "" || strings.TrimSpace(s.IntegrationName) != s.IntegrationName {
		add("integrationName %q must be non-empty without leading/trailing whitespace", s.IntegrationName)
	}
	validateStackRef(s.PagerDutyStack, add)
	if strings.TrimSpace(s.ServiceName) == "" || strings.TrimSpace(s.ServiceName) != s.ServiceName {
		add("serviceName %q must be non-empty without leading/trailing whitespace", s.ServiceName)
	}
	if !allowedSeverities[s.Severity] {
		add("severity %q must be one of default, critical, warning, error, info", s.Severity)
	}
	validateExcludeProjects(s.ExcludeProjects, add)
	if !allowedFrequencies[s.FrequencyMinutes] {
		add("frequencyMinutes %d must be one of 5, 10, 30, 60, 180, 720, 1440", s.FrequencyMinutes)
	}

	if len(errs) > 0 {
		return fmt.Errorf("invalid %s config:\n  - %s", Namespace, strings.Join(errs, "\n  - "))
	}
	return nil
}

func validateBaseURL(raw string, add func(string, ...any)) {
	if strings.TrimSpace(raw) == "" || strings.TrimSpace(raw) != raw {
		add("baseUrl %q must be a non-empty https:// URL ending in /api/", raw)
		return
	}
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		add("baseUrl %q must be an https:// URL with a host and no query/fragment", raw)
		return
	}
	if !strings.HasSuffix(u.Path, "/api/") {
		add("baseUrl %q must end in /api/", raw)
	}
}

func validateStackRef(ref string, add func(string, ...any)) {
	parts := strings.Split(ref, "/")
	if len(parts) != 3 {
		add("pagerdutyStack %q must be in <org>/<project>/<stack> form", ref)
		return
	}
	for i, part := range parts {
		if !stackSegmentPat.MatchString(part) {
			add("pagerdutyStack segment %d (%q) must be a valid Pulumi identifier", i, part)
		}
	}
}

func validateExcludeProjects(excludes []string, add func(string, ...any)) {
	seen := make(map[string]bool, len(excludes))
	hasInternal := false
	for i, slug := range excludes {
		if !projectSlugPattern.MatchString(slug) {
			add("excludeProjects[%d] %q must match ^[a-z0-9][a-z0-9_-]*$", i, slug)
			continue
		}
		if seen[slug] {
			add("excludeProjects[%d] %q is duplicated; entries must be unique", i, slug)
		}
		seen[slug] = true
		if slug == SelfMonitoringProject {
			hasInternal = true
		}
	}
	if !hasInternal {
		add("excludeProjects must include %q so Sentry self-monitoring never pages", SelfMonitoringProject)
	}
}

// Reconcile binds the PagerDuty integration key via StackReference and ensures
// every non-excluded Sentry project has a high-priority workflow-engine alert.
func Reconcile(ctx *pulumi.Context, provider *sentry.Provider, s Settings) (*Outputs, error) {
	if err := s.Validate(); err != nil {
		return nil, err
	}

	providerOpt := pulumi.Provider(provider)

	orgIntegration, err := sentry.GetOrganizationIntegration(ctx, &sentry.GetOrganizationIntegrationArgs{
		Organization: s.Organization,
		ProviderKey:  PagerDutyProviderKey,
		Name:         s.IntegrationName,
	}, providerOpt)
	if err != nil {
		return nil, fmt.Errorf("lookup Sentry PagerDuty org integration %q: %w", s.IntegrationName, err)
	}
	if orgIntegration.Id == "" {
		return nil, fmt.Errorf("lookup Sentry PagerDuty org integration %q returned empty id", s.IntegrationName)
	}

	pdStack, err := pulumi.NewStackReference(ctx, "pagerduty", &pulumi.StackReferenceArgs{
		Name: pulumi.String(s.PagerDutyStack),
	})
	if err != nil {
		return nil, fmt.Errorf("open stack reference %q: %w", s.PagerDutyStack, err)
	}
	integrationKey := pulumi.ToSecret(pdStack.GetStringOutput(pulumi.String("sentryIntegrationKey"))).(pulumi.StringOutput)

	pdService, err := sentry.NewIntegrationPagerduty(ctx, "pagerduty-service", &sentry.IntegrationPagerdutyArgs{
		Organization:   pulumi.String(s.Organization),
		IntegrationId:  pulumi.String(orgIntegration.Id),
		Service:        pulumi.String(s.ServiceName),
		IntegrationKey: integrationKey,
	}, providerOpt)
	if err != nil {
		return nil, fmt.Errorf("create Sentry PagerDuty service row %q: %w", s.ServiceName, err)
	}

	allProjects, err := sentry.GetAllProjects(ctx, &sentry.GetAllProjectsArgs{
		Organization: s.Organization,
	}, providerOpt)
	if err != nil {
		return nil, fmt.Errorf("list Sentry projects for org %q: %w", s.Organization, err)
	}

	slugs := sortedTargetSlugs(allProjects.Projects, s.ExcludeProjects)
	alertIDs := make(pulumi.StringMap, len(slugs))

	for _, slug := range slugs {
		alert, err := reconcileProjectAlert(ctx, providerOpt, s, pdService, slug)
		if err != nil {
			return nil, err
		}
		alertIDs[slug] = alert.ID().ToStringOutput()
	}

	integrationIDOut := pulumi.String(orgIntegration.Id).ToStringOutput()
	ctx.Export("integrationId", integrationIDOut)
	ctx.Export("pagerdutyServiceId", pdService.ID())
	ctx.Export("alertIds", alertIDs)

	return &Outputs{
		IntegrationID:      integrationIDOut,
		PagerDutyServiceID: pdService.ID(),
		AlertIDs:           alertIDs,
	}, nil
}

func sortedTargetSlugs(projects []sentry.GetAllProjectsProject, excludes []string) []string {
	excluded := make(map[string]bool, len(excludes))
	for _, e := range excludes {
		excluded[e] = true
	}
	seen := make(map[string]bool, len(projects))
	slugs := make([]string, 0, len(projects))
	for _, proj := range projects {
		if proj.Slug == "" || excluded[proj.Slug] || seen[proj.Slug] {
			continue
		}
		seen[proj.Slug] = true
		slugs = append(slugs, proj.Slug)
	}
	slices.Sort(slugs)
	return slugs
}

func reconcileProjectAlert(
	ctx *pulumi.Context,
	providerOpt pulumi.ResourceOrInvokeOption,
	s Settings,
	pdService *sentry.IntegrationPagerduty,
	slug string,
) (*sentry.Alert, error) {
	monitor, err := sentry.GetProjectErrorMonitor(ctx, &sentry.GetProjectErrorMonitorArgs{
		Organization: s.Organization,
		Project:      slug,
	}, providerOpt)
	if err != nil {
		return nil, fmt.Errorf("lookup default error monitor for project %q: %w", slug, err)
	}
	if monitor.Id == "" {
		return nil, fmt.Errorf("lookup default error monitor for project %q returned empty id", slug)
	}

	// Resource names derive from the project slug for stable URNs across applies.
	alert, err := sentry.NewAlert(ctx, "alert-"+slug, &sentry.AlertArgs{
		Organization:     pulumi.String(s.Organization),
		Name:             pulumi.String(fmt.Sprintf("%s: page PagerDuty on high-priority issues", slug)),
		Enabled:          pulumi.Bool(true),
		MonitorIds:       pulumi.StringArray{pulumi.String(monitor.Id)},
		FrequencyMinutes: pulumi.Float64(float64(s.FrequencyMinutes)),
		TriggerConditions: sentry.AlertTriggerConditionArray{
			&sentry.AlertTriggerConditionArgs{
				FirstSeenEvent: &sentry.AlertTriggerConditionFirstSeenEventArgs{},
			},
			&sentry.AlertTriggerConditionArgs{
				ReappearedEvent: &sentry.AlertTriggerConditionReappearedEventArgs{},
			},
		},
		ActionFilters: sentry.AlertActionFilterArray{
			&sentry.AlertActionFilterArgs{
				LogicType: pulumi.String("all"),
				Conditions: sentry.AlertActionFilterConditionArray{
					&sentry.AlertActionFilterConditionArgs{
						IssuePriorityGreaterOrEqual: &sentry.AlertActionFilterConditionIssuePriorityGreaterOrEqualArgs{
							Comparison: pulumi.Float64(HighPriorityThreshold),
						},
					},
				},
				Actions: sentry.AlertActionFilterActionArray{
					&sentry.AlertActionFilterActionArgs{
						Pagerduty: &sentry.AlertActionFilterActionPagerdutyArgs{
							IntegrationId: pdService.IntegrationId,
							ServiceId:     pdService.ID().ToStringOutput(),
							ServiceName:   pdService.Service,
							Severity:      pulumi.String(s.Severity),
						},
					},
				},
			},
		},
	}, providerOpt)
	if err != nil {
		return nil, fmt.Errorf("create high-priority PagerDuty alert for project %q: %w", slug, err)
	}
	return alert, nil
}
