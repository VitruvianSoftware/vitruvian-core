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

package main

// Writing the record: a GitHub commit status on the head commit.
//
// The status must be set by an identity that only this tool uses, so a later
// PR check can tell "the recorder said so" apart from "the PR's author said
// so". Agent apps open the PRs, so none of them qualifies, and none can write
// statuses anyway. Until a recorder App exists, recording refuses with a
// message that names what is missing, and never falls back to another token.

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	statusContext = "verified-run"
	repoSlug      = "VitruvianSoftware/vitruvian-core"
	recorderFile  = "tools/pipeline/verifiedrun/recorder.tsv"
	recorderKey   = "verified-run-recorder.pem"
)

// record is what a passing run writes.
type record struct {
	Head      string   `json:"head"`
	Tree      string   `json:"tree"`
	Base      string   `json:"base"`
	Lanes     []string `json:"lanes"`
	Plan      string   `json:"plan"`
	TargetURL string   `json:"target_url"`
}

// planDigest names exactly what ran: one line per lane and target, sorted, so
// the same work always gives the same digest whatever order it ran in. A later
// PR check recomputes it from the planner and compares.
func planDigest(invs []invocation) string {
	seen := map[string]bool{}
	for _, inv := range invs {
		for _, t := range inv.Targets {
			seen[inv.Lane+"\t"+t] = true
		}
	}
	lines := make([]string, 0, len(seen))
	for l := range seen {
		lines = append(lines, l)
	}
	sort.Strings(lines)
	sum := sha256.Sum256([]byte(strings.Join(lines, "\n")))
	return hex.EncodeToString(sum[:])
}

func lanesOf(invs []invocation) []string {
	seen := map[string]bool{}
	var lanes []string
	for _, inv := range invs {
		if !seen[inv.Lane] {
			seen[inv.Lane] = true
			lanes = append(lanes, inv.Lane)
		}
	}
	sort.Strings(lanes)
	return lanes
}

// targetURL is the one BuildBuddy run, or the commit's page listing them all.
func targetURL(head string, invs []invocation) string {
	urls := map[string]bool{}
	for _, inv := range invs {
		urls[inv.URL] = true
	}
	if len(urls) == 1 {
		return invs[0].URL
	}
	return "https://app.buildbuddy.io/history/commit/" + head
}

func newRecord(head, tree, base string, invs []invocation) record {
	return record{
		Head:      head,
		Tree:      tree,
		Base:      base,
		Lanes:     lanesOf(invs),
		Plan:      planDigest(invs),
		TargetURL: targetURL(head, invs),
	}
}

// description fits GitHub's 140-character limit and carries what the PR check
// compares: the exact files, the diff base and the work done.
func (r record) description() string {
	return fmt.Sprintf("tree=%s base=%s plan=%s", r.Tree, short(r.Base), short(r.Plan))
}

func short(s string) string {
	if len(s) > 12 {
		return s[:12]
	}
	return s
}

// recorderConfig is the recorder App's public ids, from recorder.tsv.
type recorderConfig struct {
	AppID, InstallationID, BotUserID string
}

// errNoRecorder is the expected refusal today: nobody has made the App yet.
var errNoRecorder = errors.New(`not recorded: there is no recorder identity yet.
  The record has to be a commit status set by a GitHub App that only this tool
  uses, with the "Commit statuses: write" permission. No such App exists, and
  no agent app may be used instead: agent apps open the PRs, so a record they
  set would be set by the PR's author.
  To set it up (James): create the App, install it on this repo, add its ids
  to ` + recorderFile + `,
  and put its private key in the agent key folder as ` + recorderKey + `.`)

var digitsRe = regexp.MustCompile(`^[0-9]+$`)

func loadRecorder(path string) (recorderConfig, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return recorderConfig{}, fmt.Errorf("not recorded: cannot read %s: %w", recorderFile, err)
	}
	var rows [][]string
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		rows = append(rows, strings.Split(line, "\t"))
	}
	switch {
	case len(rows) == 0:
		return recorderConfig{}, errNoRecorder
	case len(rows) > 1:
		return recorderConfig{}, fmt.Errorf("not recorded: %s must name exactly one App, it names %d", recorderFile, len(rows))
	}
	r := rows[0]
	if len(r) != 3 || !digitsRe.MatchString(r[0]) || !digitsRe.MatchString(r[1]) || !digitsRe.MatchString(r[2]) {
		return recorderConfig{}, fmt.Errorf("not recorded: %s must be one line of three numbers (app id, installation id, bot user id) separated by tabs", recorderFile)
	}
	return recorderConfig{AppID: r[0], InstallationID: r[1], BotUserID: r[2]}, nil
}

// tokenMinter turns the recorder's key into a short-lived installation token.
type tokenMinter func(ctx context.Context, cfg recorderConfig, keyPath string) (string, error)

// agentAppMinter reuses //tools/agent-app's `token` command (openssl-signed
// JWT, one-hour token) instead of a second copy of that code.
func agentAppMinter(agentApp string) tokenMinter {
	return func(ctx context.Context, cfg recorderConfig, keyPath string) (string, error) {
		cmd := exec.CommandContext(ctx, "bash", agentApp, "token", cfg.AppID, keyPath, cfg.InstallationID)
		cmd.Env = withoutGitHubTokens(os.Environ())
		var out, stderr bytes.Buffer
		cmd.Stdout, cmd.Stderr = &out, &stderr
		if err := cmd.Run(); err != nil {
			return "", fmt.Errorf("could not get a token for the recorder App: %v: %s", err, strings.TrimSpace(stderr.String()))
		}
		tok := strings.TrimSpace(out.String())
		if tok == "" {
			return "", errors.New("could not get a token for the recorder App: empty token")
		}
		return tok, nil
	}
}

// withoutGitHubTokens drops ambient GitHub credentials, so nothing on the way
// to the recorder's own token can quietly use the PR author's.
func withoutGitHubTokens(env []string) []string {
	var out []string
	for _, kv := range env {
		k, _, _ := strings.Cut(kv, "=")
		if k == "GH_TOKEN" || k == "GITHUB_TOKEN" || k == "GH_ENTERPRISE_TOKEN" {
			continue
		}
		out = append(out, kv)
	}
	return out
}

// statusRecorder writes the record. Its only credential is the token minted
// from the recorder key; it never reads GH_TOKEN or the gh CLI's login.
type statusRecorder struct {
	configPath string
	keyDir     string
	mint       tokenMinter
	apiBase    string
	client     *http.Client
}

func (s statusRecorder) record(ctx context.Context, r record) error {
	cfg, err := loadRecorder(s.configPath)
	if err != nil {
		return err
	}
	keyPath := filepath.Join(s.keyDir, recorderKey)
	if _, err := os.Stat(keyPath); err != nil {
		return fmt.Errorf("not recorded: the recorder App is listed in %s, but its private key is not at %s", recorderFile, keyPath)
	}
	token, err := s.mint(ctx, cfg, keyPath)
	if err != nil {
		return fmt.Errorf("not recorded: %w", err)
	}
	body, _ := json.Marshal(map[string]string{
		"state":       "success",
		"context":     statusContext,
		"description": r.description(),
		"target_url":  r.TargetURL,
	})
	url := fmt.Sprintf("%s/repos/%s/statuses/%s", strings.TrimRight(s.apiBase, "/"), repoSlug, r.Head)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("not recorded: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	client := s.client
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("not recorded: GitHub could not be reached: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		hint := ""
		if resp.StatusCode == http.StatusUnprocessableEntity {
			hint = " (has this commit been pushed?)"
		}
		return fmt.Errorf("not recorded: GitHub answered %d%s: %s", resp.StatusCode, hint, strings.TrimSpace(string(msg)))
	}
	return nil
}
