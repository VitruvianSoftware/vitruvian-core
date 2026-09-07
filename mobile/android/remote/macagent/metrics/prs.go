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

package metrics

import (
	"encoding/json"
	"fmt"
	"time"
)

// The v1.2 pull-request reader. gh speaks JSON, so these are decoders rather
// than text parsers -- but they stay here with the rest for the same reason:
// pure, fixture-pinned, and runnable on a Linux CI runner that has no gh.

// Checks is the check rollup of one PR, counted rather than listed. A phone
// has room for "24 green, 1 red", not for twenty-five rows.
type Checks struct {
	Success int `json:"success"`
	Failure int `json:"failure"`
	Pending int `json:"pending"`
	Skipped int `json:"skipped"`
}

// PR is one row of GET /v1/prs.
type PR struct {
	Repo           string    `json:"repo"`
	Number         int       `json:"number"`
	Title          string    `json:"title"`
	URL            string    `json:"url"`
	Author         string    `json:"author"`
	IsDraft        bool      `json:"is_draft"`
	HeadRef        string    `json:"head_ref"`
	BaseRef        string    `json:"base_ref"`
	MergeState     string    `json:"merge_state"`
	ReviewDecision string    `json:"review_decision"`
	Checks         Checks    `json:"checks"`
	AutoMerge      bool      `json:"auto_merge"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// PRs is the body of GET /v1/prs.
type PRs struct {
	Available bool      `json:"available"`
	Reason    string    `json:"reason"`
	SampledAt time.Time `json:"sampled_at"`
	PRs       []PR      `json:"prs"`
}

// PRRef is one row of `gh search prs`: enough to know which PRs exist, before
// the per-PR view fills in the detail.
type PRRef struct {
	Repo      string
	Number    int
	Title     string
	URL       string
	UpdatedAt time.Time
}

// ParseGhSearchPrs reads `gh search prs --json number,repository,title,url,updatedAt`.
func ParseGhSearchPrs(out string) ([]PRRef, error) {
	var rows []struct {
		Number     int    `json:"number"`
		Title      string `json:"title"`
		URL        string `json:"url"`
		UpdatedAt  string `json:"updatedAt"`
		Repository struct {
			NameWithOwner string `json:"nameWithOwner"`
		} `json:"repository"`
	}
	if err := json.Unmarshal([]byte(out), &rows); err != nil {
		return nil, fmt.Errorf("gh search prs: %w", err)
	}
	refs := make([]PRRef, 0, len(rows))
	for _, r := range rows {
		ref := PRRef{Repo: r.Repository.NameWithOwner, Number: r.Number, Title: r.Title, URL: r.URL}
		if t, err := time.Parse(time.RFC3339, r.UpdatedAt); err == nil {
			ref.UpdatedAt = t
		}
		refs = append(refs, ref)
	}
	return refs, nil
}

// ParseGhPrView reads `gh pr view <n> --json isDraft,headRefName,baseRefName,
// mergeStateStatus,reviewDecision,statusCheckRollup,autoMergeRequest,author`
// and fills in everything about a PR that the search result does not carry.
//
// The repo, number, title and URL are NOT in this payload -- they come from
// the search row -- so the returned PR carries only the fields this view
// answers, and the caller merges the two.
func ParseGhPrView(out string) (PR, error) {
	var v struct {
		IsDraft          bool   `json:"isDraft"`
		HeadRefName      string `json:"headRefName"`
		BaseRefName      string `json:"baseRefName"`
		MergeStateStatus string `json:"mergeStateStatus"`
		ReviewDecision   string `json:"reviewDecision"`
		Author           struct {
			Login string `json:"login"`
		} `json:"author"`
		// A PR with auto-merge off has this as JSON null, which is the whole
		// signal: a pointer distinguishes it from a zero-valued object.
		AutoMergeRequest  *struct{} `json:"autoMergeRequest"`
		StatusCheckRollup []struct {
			Conclusion string `json:"conclusion"`
			Status     string `json:"status"`
			State      string `json:"state"`
		} `json:"statusCheckRollup"`
	}
	if err := json.Unmarshal([]byte(out), &v); err != nil {
		return PR{}, fmt.Errorf("gh pr view: %w", err)
	}
	pr := PR{
		IsDraft:        v.IsDraft,
		HeadRef:        v.HeadRefName,
		BaseRef:        v.BaseRefName,
		MergeState:     v.MergeStateStatus,
		ReviewDecision: v.ReviewDecision,
		Author:         v.Author.Login,
		AutoMerge:      v.AutoMergeRequest != nil,
	}
	for _, c := range v.StatusCheckRollup {
		// A CheckRun reports conclusion+status; a StatusContext (the older
		// commit-status API, which several bots still use) reports only
		// state. Taking whichever is present is why both are decoded.
		signal := c.Conclusion
		if signal == "" {
			signal = c.State
		}
		if signal == "" {
			signal = c.Status
		}
		switch signal {
		case "SUCCESS":
			pr.Checks.Success++
		case "SKIPPED", "NEUTRAL":
			pr.Checks.Skipped++
		case "PENDING", "IN_PROGRESS", "QUEUED", "WAITING", "REQUESTED", "EXPECTED":
			pr.Checks.Pending++
		default:
			// FAILURE, TIMED_OUT, CANCELLED, ACTION_REQUIRED, STARTUP_FAILURE,
			// ERROR -- and anything GitHub adds later. Defaulting an unknown
			// conclusion to red is the safe direction: a check nobody can
			// classify is not one to call green.
			pr.Checks.Failure++
		}
	}
	return pr, nil
}

// PRChecksVerdict collapses a rollup into the one word a notification needs,
// or "" when the PR is neither yet. Pending beats failure beats green: a run
// still going is not a result.
func PRChecksVerdict(c Checks) string {
	switch {
	case c.Pending > 0:
		return ""
	case c.Failure > 0:
		return "red"
	case c.Success > 0:
		return "green"
	default:
		return ""
	}
}
