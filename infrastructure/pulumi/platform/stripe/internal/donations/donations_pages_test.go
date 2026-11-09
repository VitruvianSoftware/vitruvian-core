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

package donations

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe/internal/account"
)

// Every app's donations are counted on its own Payment Link. That only holds
// while three places agree on the app's key: the stacks' donations.apps (the
// link and its metadata.app), the site's _data/donations.yml (where the link
// is copied once live) and the site's donate/<key>.html (the stable address
// apps and Sponsor buttons open). A page with no link, or a link with no
// page, sends a donation to the wrong app or nowhere. These tests read the
// committed files and fail when any of them drifts.

// repoRoot is the monorepo root, from this package's directory. Under
// `bazel test` the files below are the test's data, at the same relative
// paths (pulumi_go_test, extra_data).
const repoRoot = "../../../../../../"

const (
	siteDir = repoRoot + "apps/web/vitruviansoftware-dev/"
	// generalKey is the "support development" link: the site's /donate/
	// (donate/index.html), not an app.
	generalKey = "development"
	// donateURL is the site's general donate page; each app's is
	// donateURL + "<key>/".
	donateURL = "https://vitruviansoftware.dev/donate/"
	// sponsorRepoList names every repository with a Sponsor button and the
	// FUNDING.yml it gets.
	sponsorRepoList = repoRoot + "infrastructure/pulumi/platform/repo-config/sponsor-button-repos.txt"
)

func stackAppKeys(t *testing.T) []string {
	t.Helper()
	s := checkCommittedConfig(t, "Pulumi.production.yaml", account.ModeLive)
	keys := make([]string, 0, len(s.Apps))
	for _, a := range s.Apps {
		keys = append(keys, a.Key)
	}
	sort.Strings(keys)
	return keys
}

type siteDonation struct {
	Name string `yaml:"name"`
	Repo string `yaml:"repo"`
	URL  string `yaml:"url"`
}

func siteDonations(t *testing.T) map[string]siteDonation {
	t.Helper()
	raw, err := os.ReadFile(siteDir + "_data/donations.yml")
	if err != nil {
		t.Fatalf("read the site's donations: %v", err)
	}
	var m map[string]siteDonation
	if err := yaml.Unmarshal(raw, &m); err != nil {
		t.Fatalf("parse _data/donations.yml: %v", err)
	}
	return m
}

// The site lists exactly the apps the stacks make links for.
func TestSiteListsEveryLink(t *testing.T) {
	keys := stackAppKeys(t)
	site := siteDonations(t)
	var siteKeys []string
	for k := range site {
		siteKeys = append(siteKeys, k)
	}
	sort.Strings(siteKeys)
	if strings.Join(keys, ",") != strings.Join(siteKeys, ",") {
		t.Fatalf("donations.apps in the stack configs and _data/donations.yml list different keys:\n stacks: %v\n site:   %v", keys, siteKeys)
	}
}

// Each entry can be shown, and forwards only to a live-mode link.
func TestSiteEntriesAreUsable(t *testing.T) {
	for key, d := range siteDonations(t) {
		if strings.TrimSpace(d.Name) == "" {
			t.Errorf("_data/donations.yml %s: name is required (the page says it)", key)
		}
		if key != generalKey && !strings.HasPrefix(d.Repo, "https://github.com/VitruvianSoftware/") {
			t.Errorf("_data/donations.yml %s: repo %q must be the app's public repository on github.com/VitruvianSoftware (the page offers a star there until the link is live)", key, d.Repo)
		}
		u := strings.TrimSpace(d.URL)
		if u == "" {
			continue
		}
		live := (strings.HasPrefix(u, "https://donate.stripe.com/") || strings.HasPrefix(u, "https://buy.stripe.com/")) && !strings.Contains(u, "/test_")
		if !live {
			t.Errorf("_data/donations.yml %s: url %q is not a live-mode Payment Link (production stack's donationLinks.%s)", key, u, key)
		}
	}
}

// Each app has its page at /donate/<key>/, rendered for that same key.
func TestEveryLinkHasItsPage(t *testing.T) {
	for _, key := range stackAppKeys(t) {
		file, permalink, uses := "donate/"+key+".html", "/donate/"+key+"/", `include donate-app.html key="`+key+`"`
		if key == generalKey {
			file, permalink, uses = "donate/index.html", "/donate/", "site.data.donations."+generalKey
		}
		raw, err := os.ReadFile(siteDir + file)
		if err != nil {
			t.Errorf("%s has a Payment Link but no page: %v", key, err)
			continue
		}
		page := string(raw)
		if !strings.Contains(page, "\npermalink: "+permalink+"\n") {
			t.Errorf("%s: want front matter `permalink: %s`", file, permalink)
		}
		if !strings.Contains(page, uses) {
			t.Errorf("%s: must render the %s entry (%s)", file, key, uses)
		}
	}
	// And no page for a key without a link.
	pages, err := filepath.Glob(siteDir + "donate/*.html")
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{"index": true}
	for _, k := range stackAppKeys(t) {
		want[k] = true
	}
	for _, p := range pages {
		k := strings.TrimSuffix(filepath.Base(p), ".html")
		if !want[k] {
			t.Errorf("donate/%s.html has no Payment Link: add %q to donations.apps in both stack configs, or remove the page", k, k)
		}
	}
}

var fundingCustom = regexp.MustCompile(`(?m)^custom:\s*\["([^"]+)"\]\s*$`)

// Every Sponsor button opens the general page or one app's page that a link
// backs.
func TestSponsorButtonsOpenAPageWithALink(t *testing.T) {
	keys := map[string]bool{}
	for _, k := range stackAppKeys(t) {
		keys[k] = true
	}
	f, err := os.Open(sponsorRepoList)
	if err != nil {
		t.Fatalf("read the Sponsor button list: %v", err)
	}
	defer f.Close()
	n := 0
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) != 2 {
			t.Fatalf("sponsor-button-repos.txt: want `<repository> <FUNDING.yml path>`, got %q", line)
		}
		repo, path := fields[0], fields[1]
		n++
		raw, err := os.ReadFile(repoRoot + path)
		if err != nil {
			t.Errorf("%s: %v", repo, err)
			continue
		}
		m := fundingCustom.FindStringSubmatch(string(raw))
		if m == nil {
			t.Errorf("%s: %s has no single `custom: [\"...\"]` line", repo, path)
			continue
		}
		u := m[1]
		if u == donateURL {
			continue // the general page
		}
		key := strings.TrimSuffix(strings.TrimPrefix(u, donateURL), "/")
		if !strings.HasPrefix(u, donateURL) || !strings.HasSuffix(u, "/") || !keys[key] || key == generalKey {
			t.Errorf("%s: its Sponsor button opens %q; want %s or %s<key>/ for a key in donations.apps", repo, u, donateURL, donateURL)
		}
	}
	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}
	if n == 0 {
		t.Fatal("sponsor-button-repos.txt lists no repositories")
	}
}
