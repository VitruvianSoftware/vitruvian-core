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
// The status is set by ONE named identity, the recorder, listed in
// recorder.tsv: today the scout agent's App, the only App granted "Commit
// statuses: write". A later PR check trusts a status only from that bot user,
// and never on a PR the recorder itself opened. The token is minted from the
// recorder's own key; GH_TOKEN and the gh login are never used, so a record
// cannot quietly come from whoever is logged in.

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
	agentsFile    = "tools/agent-app/agents.tsv"
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

// recorderConfig is the recorder's public ids: the agent named in
// recorder.tsv, resolved through //tools/agent-app's registry.
type recorderConfig struct {
	Agent, AppID, InstallationID, BotUserID string
}

// errNoRecorder: recorder.tsv names nobody.
var errNoRecorder = errors.New(`not recorded: ` + recorderFile + ` names no recorder.
  The record is a commit status, and it must be set by the one App named
  there, which needs the "Commit statuses: write" permission.`)

var (
	digitsRe = regexp.MustCompile(`^[0-9]+$`)
	agentRe  = regexp.MustCompile(`^[a-z][a-z0-9-]*$`)
)

// tsvRows returns the non-comment, non-blank lines of a tab-separated file.
func tsvRows(path string) ([][]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var rows [][]string
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		rows = append(rows, strings.Split(line, "\t"))
	}
	return rows, nil
}

// loadRecorder reads recorder.tsv (agent, bot user id) and checks it against
// agents.tsv, which holds the same agent's app id, installation id and bot
// user id. They must agree: the bot user id is what a PR check will trust.
func loadRecorder(recorderPath, agentsPath string) (recorderConfig, error) {
	rows, err := tsvRows(recorderPath)
	if err != nil {
		return recorderConfig{}, fmt.Errorf("not recorded: cannot read %s: %w", recorderFile, err)
	}
	switch {
	case len(rows) == 0:
		return recorderConfig{}, errNoRecorder
	case len(rows) > 1:
		return recorderConfig{}, fmt.Errorf("not recorded: %s must name exactly one recorder, it names %d", recorderFile, len(rows))
	}
	r := rows[0]
	if len(r) != 2 || !agentRe.MatchString(r[0]) || !digitsRe.MatchString(r[1]) {
		return recorderConfig{}, fmt.Errorf("not recorded: %s must be one line: agent name, a tab, its bot user id", recorderFile)
	}
	cfg := recorderConfig{Agent: r[0], BotUserID: r[1]}

	agents, err := tsvRows(agentsPath)
	if err != nil {
		return recorderConfig{}, fmt.Errorf("not recorded: cannot read %s: %w", agentsFile, err)
	}
	for _, a := range agents {
		if len(a) < 4 || a[0] != cfg.Agent {
			continue
		}
		if a[3] != cfg.BotUserID {
			return recorderConfig{}, fmt.Errorf("not recorded: %s says %s's bot user id is %s, %s says %s", recorderFile, cfg.Agent, cfg.BotUserID, agentsFile, a[3])
		}
		if !digitsRe.MatchString(a[1]) || !digitsRe.MatchString(a[2]) {
			return recorderConfig{}, fmt.Errorf("not recorded: %s has no usable app id and installation id for %s", agentsFile, cfg.Agent)
		}
		cfg.AppID, cfg.InstallationID = a[1], a[2]
		return cfg, nil
	}
	return recorderConfig{}, fmt.Errorf("not recorded: the recorder %q is not in %s", cfg.Agent, agentsFile)
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
			return "", fmt.Errorf("could not get a token for %s: %v: %s", cfg.Agent, err, strings.TrimSpace(stderr.String()))
		}
		tok := strings.TrimSpace(out.String())
		if tok == "" {
			return "", fmt.Errorf("could not get a token for %s: empty token", cfg.Agent)
		}
		return tok, nil
	}
}

// withoutGitHubTokens drops ambient GitHub credentials, so nothing on the way
// to the recorder's own token can quietly use someone else's.
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
// from the recorder's key.
type statusRecorder struct {
	configPath string
	agentsPath string
	keyDir     string
	mint       tokenMinter
	apiBase    string
	client     *http.Client
}

func (s statusRecorder) record(ctx context.Context, r record) error {
	cfg, err := loadRecorder(s.configPath, s.agentsPath)
	if err != nil {
		return err
	}
	keyPath := filepath.Join(s.keyDir, cfg.Agent+".pem")
	if _, err := os.Stat(keyPath); err != nil {
		return fmt.Errorf("not recorded: the recorder is %s, but its private key is not at %s (bazel run //tools/sync-env-secrets:agent-keys-pull)", cfg.Agent, keyPath)
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
	msg, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	if resp.StatusCode != http.StatusCreated {
		hint := ""
		if resp.StatusCode == http.StatusUnprocessableEntity {
			hint = " (has this commit been pushed?)"
		}
		return fmt.Errorf("not recorded: GitHub answered %d%s: %s", resp.StatusCode, hint, strings.TrimSpace(short512(msg)))
	}
	// Check GitHub's own account of who set it, rather than assume.
	var created struct {
		Creator struct {
			ID    json.Number `json:"id"`
			Login string      `json:"login"`
		} `json:"creator"`
	}
	if err := json.Unmarshal(msg, &created); err != nil || created.Creator.ID.String() != cfg.BotUserID {
		return fmt.Errorf("the status was written, but GitHub says it was set by %q (id %s), not the recorder %s (id %s). Do not trust it", created.Creator.Login, created.Creator.ID, cfg.Agent, cfg.BotUserID)
	}
	return nil
}

func short512(b []byte) string {
	if len(b) > 512 {
		return string(b[:512]) + "..."
	}
	return string(b)
}
