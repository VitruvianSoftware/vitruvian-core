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

package config

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"gopkg.in/yaml.v3"
)

var (
	// Matches legacy 64-hex Sentry auth tokens; modern Sentry tokens (sntrys_,
	// sntryu_, sntryr_, etc.) are rejected via substring match on "sntry".
	sentryHexTokenPattern = regexp.MustCompile(`^[0-9a-fA-F]{64}$`)

	// Keys permitted under `config:` in Pulumi.production.yaml (everything
	// read by Load plus sentry:enableIssueAlerts which must remain false).
	allowedTopKeys = map[string]bool{
		"sentry:baseUrl":           true,
		"sentry:organization":      true,
		"sentry:enableIssueAlerts": true,
		"sentry:team":              true,
		"sentry:projects":          true,
	}

	// No key in platform/sentry may carry Pulumi `secure:` ciphertext; runtime
	// auth comes exclusively from SENTRY_TOKEN / SENTRY_AUTH_TOKEN.
	allowedSecureKeys = map[string]bool{}
)

func scanNodeForSecrets(node *yaml.Node, path string, topKey string) error {
	if node == nil {
		return nil
	}
	if node.Kind == yaml.DocumentNode {
		for i, child := range node.Content {
			if err := scanNodeForSecrets(child, fmt.Sprintf("%s[%d]", path, i), topKey); err != nil {
				return err
			}
		}
		return nil
	}
	if node.Kind == yaml.ScalarNode {
		val := strings.TrimSpace(node.Value)
		lower := strings.ToLower(val)
		if strings.Contains(lower, "sntry") || sentryHexTokenPattern.MatchString(val) {
			return fmt.Errorf("YAML value at %s resembles a Sentry token", path)
		}
		return nil
	}
	if node.Kind == yaml.MappingNode {
		for i := 0; i+1 < len(node.Content); i += 2 {
			keyNode := node.Content[i]
			valNode := node.Content[i+1]
			key := strings.TrimSpace(keyNode.Value)
			if key == "secure" && !allowedSecureKeys[topKey] {
				return fmt.Errorf("secure: ciphertext is not allowed under non-allowlisted key %q (at %s)", topKey, path)
			}
			if err := scanNodeForSecrets(keyNode, path+"."+key+"(key)", topKey); err != nil {
				return err
			}
			nextTopKey := topKey
			if path == "root.config" {
				nextTopKey = key
			}
			if err := scanNodeForSecrets(valNode, path+"."+key, nextTopKey); err != nil {
				return err
			}
		}
		return nil
	}
	for i, child := range node.Content {
		if err := scanNodeForSecrets(child, fmt.Sprintf("%s[%d]", path, i), topKey); err != nil {
			return err
		}
	}
	return nil
}

func checkStackConfigBytes(raw []byte) (*StackConfig, error) {
	var root yaml.Node
	if err := yaml.Unmarshal(raw, &root); err != nil {
		return nil, fmt.Errorf("parse stack yaml: %w", err)
	}
	if len(root.Content) != 1 || root.Content[0].Kind != yaml.MappingNode {
		return nil, fmt.Errorf("stack yaml must contain a top-level mapping")
	}
	docMap := root.Content[0]
	var configNode *yaml.Node
	for i := 0; i+1 < len(docMap.Content); i += 2 {
		k := docMap.Content[i].Value
		if k != "config" {
			return nil, fmt.Errorf("unexpected top-level document key %q", k)
		}
		configNode = docMap.Content[i+1]
	}
	if configNode == nil || configNode.Kind != yaml.MappingNode {
		return nil, fmt.Errorf("missing config mapping in stack yaml")
	}

	if err := scanNodeForSecrets(&root, "root", ""); err != nil {
		return nil, err
	}

	var doc struct {
		Config map[string]yaml.Node `yaml:"config"`
	}
	if err := yaml.Unmarshal(raw, &doc); err != nil {
		return nil, fmt.Errorf("parse config map: %w", err)
	}
	for k := range doc.Config {
		if !allowedTopKeys[k] {
			return nil, fmt.Errorf("unexpected config key %q", k)
		}
	}

	var sc StackConfig
	decodeViaJSON := func(n *yaml.Node, key string, into any) error {
		var rawVal any
		if err := n.Decode(&rawVal); err != nil {
			return fmt.Errorf("decode %q: %w", key, err)
		}
		b, err := json.Marshal(rawVal)
		if err != nil {
			return fmt.Errorf("marshal %q as json: %w", key, err)
		}
		if err := json.Unmarshal(b, into); err != nil {
			return fmt.Errorf("unmarshal %q from json: %w", key, err)
		}
		return nil
	}
	reqDecode := func(key string, into any) error {
		n, ok := doc.Config[key]
		if !ok {
			return fmt.Errorf("missing required config key %q", key)
		}
		return decodeViaJSON(&n, key, into)
	}
	if err := reqDecode("sentry:baseUrl", &sc.BaseURL); err != nil {
		return nil, err
	}
	if n, ok := doc.Config["sentry:organization"]; ok {
		if err := decodeViaJSON(&n, "sentry:organization", &sc.Organization); err != nil {
			return nil, err
		}
	} else {
		sc.Organization = "sentry"
	}
	if n, ok := doc.Config["sentry:enableIssueAlerts"]; ok {
		if err := decodeViaJSON(&n, "sentry:enableIssueAlerts", &sc.EnableIssueAlerts); err != nil {
			return nil, err
		}
	}
	if err := reqDecode("sentry:team", &sc.Team); err != nil {
		return nil, err
	}
	if err := reqDecode("sentry:projects", &sc.Projects); err != nil {
		return nil, err
	}

	if err := validateStackConfig(&sc); err != nil {
		return nil, err
	}
	return &sc, nil
}

func validateStackConfig(sc *StackConfig) error {
	u, err := url.Parse(strings.TrimSpace(sc.BaseURL))
	if err != nil || u.Scheme != "https" || u.Host == "" || !strings.HasSuffix(u.Path, "/api/") || u.RawQuery != "" {
		return fmt.Errorf("invalid sentry:baseUrl %q: must be an https://.../api/ URL", sc.BaseURL)
	}
	if strings.TrimSpace(sc.Organization) == "" {
		return fmt.Errorf("sentry:organization must not be empty")
	}
	if sc.EnableIssueAlerts {
		return fmt.Errorf("sentry:enableIssueAlerts must stay false (legacy /rules/ endpoint removed in Sentry 26.10.1; PagerDuty alerts live in platform/sentry-pagerduty)")
	}
	if strings.TrimSpace(sc.Team.Name) == "" || strings.TrimSpace(sc.Team.Slug) == "" {
		return fmt.Errorf("sentry:team must specify non-empty name and slug")
	}
	if len(sc.Projects) == 0 {
		return fmt.Errorf("sentry:projects must declare at least one project")
	}
	seenSlugs := make(map[string]bool, len(sc.Projects))
	for i, p := range sc.Projects {
		if strings.TrimSpace(p.Name) == "" || strings.TrimSpace(p.Slug) == "" || strings.TrimSpace(p.Platform) == "" {
			return fmt.Errorf("sentry:projects[%d] must have non-empty name, slug, and platform", i)
		}
		if p.ResolveAge <= 0 {
			return fmt.Errorf("sentry:projects[%d] (%s) must have positive resolveAge, got %d", i, p.Slug, p.ResolveAge)
		}
		if seenSlugs[p.Slug] {
			return fmt.Errorf("duplicate project slug %q in sentry:projects", p.Slug)
		}
		seenSlugs[p.Slug] = true
	}
	return nil
}

type noopMocks struct{}

func (noopMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "_id", args.Inputs, nil
}

func (noopMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func TestCommittedProductionConfig(t *testing.T) {
	raw, err := os.ReadFile("../../Pulumi.production.yaml")
	if err != nil {
		t.Fatalf("read Pulumi.production.yaml: %v", err)
	}
	sc, err := checkStackConfigBytes(raw)
	if err != nil {
		t.Fatalf("Pulumi.production.yaml validation failed: %v", err)
	}
	if sc.BaseURL != "https://sentry.lab.ipv1337.dev/api/" {
		t.Fatalf("unexpected baseUrl: %q", sc.BaseURL)
	}
	if sc.Organization != "sentry" {
		t.Fatalf("unexpected organization: %q", sc.Organization)
	}
	if sc.EnableIssueAlerts {
		t.Fatal("expected EnableIssueAlerts=false")
	}
	if sc.Team.Slug != "vitruvian" || sc.Team.Name != "Vitruvian" {
		t.Fatalf("unexpected team: %+v", sc.Team)
	}
	if len(sc.Projects) == 0 {
		t.Fatal("expected non-empty projects list")
	}

	teamJSON, err := json.Marshal(sc.Team)
	if err != nil {
		t.Fatalf("marshal team: %v", err)
	}
	projsJSON, err := json.Marshal(sc.Projects)
	if err != nil {
		t.Fatalf("marshal projects: %v", err)
	}

	var loaded *StackConfig
	err = pulumi.RunErr(func(ctx *pulumi.Context) error {
		var loadErr error
		loaded, loadErr = Load(ctx)
		return loadErr
	}, pulumi.WithMocks("sentry", "production", noopMocks{}), func(info *pulumi.RunInfo) {
		info.Config = map[string]string{
			"sentry:baseUrl":           sc.BaseURL,
			"sentry:organization":      sc.Organization,
			"sentry:enableIssueAlerts": strconv.FormatBool(sc.EnableIssueAlerts),
			"sentry:team":              string(teamJSON),
			"sentry:projects":          string(projsJSON),
		}
	})
	if err != nil {
		t.Fatalf("config.Load under Pulumi mocks failed: %v", err)
	}
	if loaded.BaseURL != sc.BaseURL || loaded.Organization != sc.Organization || loaded.EnableIssueAlerts != sc.EnableIssueAlerts {
		t.Fatalf("loaded mismatch: got %+v, want %+v", loaded, sc)
	}
	if loaded.Team != sc.Team || len(loaded.Projects) != len(sc.Projects) {
		t.Fatalf("loaded team/projects mismatch: got %+v", loaded)
	}
}

func TestStackConfigGuardRejectsSecretsAndBadKeys(t *testing.T) {
	baseYAML := `config:
  sentry:baseUrl: https://sentry.lab.ipv1337.dev/api/
  sentry:organization: sentry
  sentry:team:
    name: Vitruvian
    slug: vitruvian
  sentry:projects:
    - name: Backstage
      slug: backstage
      platform: node-express
      resolveAge: 720
`
	if _, err := checkStackConfigBytes([]byte(baseYAML)); err != nil {
		t.Fatalf("baseline YAML unexpectedly rejected: %v", err)
	}

	// Construct token fixtures dynamically so secret scanners never flag test lines.
	fakeModern := "sntrys_" + strings.Repeat("A", 24)
	fakeUser := "sntryu_" + strings.Repeat("B", 24)
	fakeHex := strings.Repeat("ab", 32)

	cases := map[string]struct {
		yaml string
		want string
	}{
		"secure under non-allowlisted sentry:token": {
			yaml: baseYAML + "  sentry:token:\n    secure: v1:fake\n",
			want: "secure:",
		},
		"secure under allowlisted sentry:baseUrl": {
			yaml: strings.Replace(baseYAML, "sentry:baseUrl: https://sentry.lab.ipv1337.dev/api/", "sentry:baseUrl:\n    secure: v1:fake", 1),
			want: "secure:",
		},
		"nested secure inside sentry:team": {
			yaml: strings.Replace(baseYAML, "slug: vitruvian", "slug:\n      secure: v1:fake", 1),
			want: "secure:",
		},
		"sntrys_ token pattern": {
			yaml: strings.Replace(baseYAML, "name: Backstage", "name: "+fakeModern, 1),
			want: "Sentry token",
		},
		"sntryu_ token pattern": {
			yaml: strings.Replace(baseYAML, "name: Vitruvian", "name: "+fakeUser, 1),
			want: "Sentry token",
		},
		"generic sntry substring": {
			yaml: strings.Replace(baseYAML, "name: Vitruvian", "name: my-sntry-val", 1),
			want: "Sentry token",
		},
		"64-hex legacy token": {
			yaml: strings.Replace(baseYAML, "name: Vitruvian", "name: "+fakeHex, 1),
			want: "Sentry token",
		},
		"unknown top-level config key": {
			yaml: baseYAML + "  sentry:authToken: abc\n",
			want: "unexpected config key",
		},
		"unknown namespace key": {
			yaml: baseYAML + "  other:key: abc\n",
			want: "unexpected config key",
		},
		"unknown document root key": {
			yaml: baseYAML + "secretsprovider: default\n",
			want: "unexpected top-level document key",
		},
		"enableIssueAlerts true forbidden": {
			yaml: baseYAML + "  sentry:enableIssueAlerts: true\n",
			want: "enableIssueAlerts must stay false",
		},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := checkStackConfigBytes([]byte(tc.yaml))
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("want error containing %q, got %v", tc.want, err)
			}
		})
	}
}
