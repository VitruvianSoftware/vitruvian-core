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

import (
	"encoding/json"
	"errors"
)

// supportedKinds are the webhook events the relay forwards (spec §2.1).
var supportedKinds = map[string]bool{
	"check_run":           true,
	"check_suite":         true,
	"workflow_run":        true,
	"pull_request":        true,
	"pull_request_review": true,
	"status":              true,
	"push":                true,
}

var errNoRepository = errors.New("payload has no repository.full_name")

// The input shapes: only the fields the relay keeps. Everything else in a
// GitHub payload (often tens of KiB) is dropped here and never stored.
type ghLogin struct {
	Login string `json:"login"`
}

type ghRun struct {
	Name       string `json:"name"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
	HeadSHA    string `json:"head_sha"`
	HeadBranch string `json:"head_branch"`
	HTMLURL    string `json:"html_url"`
	// check_suite has no name or html_url of its own; its app does.
	App *struct {
		Name string `json:"name"`
	} `json:"app"`
}

type ghPull struct {
	Number int     `json:"number"`
	Title  string  `json:"title"`
	State  string  `json:"state"`
	Draft  bool    `json:"draft"`
	Merged bool    `json:"merged"`
	HTML   string  `json:"html_url"`
	User   ghLogin `json:"user"`
	Head   struct {
		SHA string `json:"sha"`
	} `json:"head"`
	RequestedReviewers []ghLogin `json:"requested_reviewers"`
	RequestedTeams     []struct {
		Slug string `json:"slug"`
	} `json:"requested_teams"`
}

type ghPayload struct {
	Action     string `json:"action"`
	Repository struct {
		FullName      string `json:"full_name"`
		DefaultBranch string `json:"default_branch"`
	} `json:"repository"`
	CheckRun    *ghRun  `json:"check_run"`
	CheckSuite  *ghRun  `json:"check_suite"`
	WorkflowRun *ghRun  `json:"workflow_run"`
	PullRequest *ghPull `json:"pull_request"`
	Review      *struct {
		State string  `json:"state"`
		User  ghLogin `json:"user"`
	} `json:"review"`
	// status
	SHA     string `json:"sha"`
	State   string `json:"state"`
	Context string `json:"context"`
	// push
	Ref   string `json:"ref"`
	After string `json:"after"`
}

// The output shapes: the wire contract documented in README.md. Every field
// is always present (no omitempty) so the Swift decoder can be strict.
type runOut struct {
	Action     string  `json:"action"`
	Name       string  `json:"name"`
	Status     string  `json:"status"`
	Conclusion *string `json:"conclusion"`
	HeadSHA    string  `json:"head_sha"`
	HTMLURL    string  `json:"html_url"`
}

type runBranchOut struct {
	runOut
	HeadBranch string `json:"head_branch"`
}

type pullHeadOut struct {
	SHA string `json:"sha"`
}

type pullUserOut struct {
	Login string `json:"login"`
}

type pullTeamOut struct {
	Slug string `json:"slug"`
}

type pullOut struct {
	Action             string        `json:"action"`
	Number             int           `json:"number"`
	Title              string        `json:"title"`
	State              string        `json:"state"`
	Draft              bool          `json:"draft"`
	Merged             bool          `json:"merged"`
	Head               pullHeadOut   `json:"head"`
	HTMLURL            string        `json:"html_url"`
	User               pullUserOut   `json:"user"`
	RequestedReviewers []pullUserOut `json:"requested_reviewers"`
	RequestedTeams     []pullTeamOut `json:"requested_teams"`
}

type reviewOut struct {
	Action      string `json:"action"`
	PullRequest struct {
		Number int `json:"number"`
	} `json:"pull_request"`
	Review struct {
		State string      `json:"state"`
		User  pullUserOut `json:"user"`
	} `json:"review"`
}

type statusOut struct {
	SHA     string `json:"sha"`
	State   string `json:"state"`
	Context string `json:"context"`
}

type pushOut struct {
	Ref           string `json:"ref"`
	After         string `json:"after"`
	DefaultBranch string `json:"default_branch"`
}

func nullable(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func runSubset(action string, r *ghRun) runOut {
	if r == nil {
		r = &ghRun{}
	}
	name := r.Name
	if name == "" && r.App != nil {
		name = r.App.Name
	}
	return runOut{
		Action: action, Name: name, Status: r.Status,
		Conclusion: nullable(r.Conclusion), HeadSHA: r.HeadSHA, HTMLURL: r.HTMLURL,
	}
}

// Normalize turns a raw webhook body into (repo, payload subset). It errors
// only on a body that is not JSON or names no repository.
func Normalize(kind string, body []byte) (string, json.RawMessage, error) {
	var p ghPayload
	if err := json.Unmarshal(body, &p); err != nil {
		return "", nil, err
	}
	repo := p.Repository.FullName
	if repo == "" {
		return "", nil, errNoRepository
	}
	var out any
	switch kind {
	case "check_run":
		out = runSubset(p.Action, p.CheckRun)
	case "check_suite":
		out = runBranchOut{runSubset(p.Action, p.CheckSuite), branchOf(p.CheckSuite)}
	case "workflow_run":
		out = runBranchOut{runSubset(p.Action, p.WorkflowRun), branchOf(p.WorkflowRun)}
	case "pull_request":
		pr := p.PullRequest
		if pr == nil {
			pr = &ghPull{}
		}
		o := pullOut{
			Action: p.Action, Number: pr.Number, Title: pr.Title, State: pr.State,
			Draft: pr.Draft, Merged: pr.Merged, Head: pullHeadOut{pr.Head.SHA},
			HTMLURL: pr.HTML, User: pullUserOut{pr.User.Login},
			RequestedReviewers: []pullUserOut{}, RequestedTeams: []pullTeamOut{},
		}
		for _, r := range pr.RequestedReviewers {
			o.RequestedReviewers = append(o.RequestedReviewers, pullUserOut{r.Login})
		}
		for _, t := range pr.RequestedTeams {
			o.RequestedTeams = append(o.RequestedTeams, pullTeamOut{t.Slug})
		}
		out = o
	case "pull_request_review":
		var o reviewOut
		o.Action = p.Action
		if p.PullRequest != nil {
			o.PullRequest.Number = p.PullRequest.Number
		}
		if p.Review != nil {
			o.Review.State = p.Review.State
			o.Review.User.Login = p.Review.User.Login
		}
		out = o
	case "status":
		out = statusOut{SHA: p.SHA, State: p.State, Context: p.Context}
	case "push":
		out = pushOut{Ref: p.Ref, After: p.After, DefaultBranch: p.Repository.DefaultBranch}
	default:
		return "", nil, errors.New("unsupported event kind " + kind)
	}
	b, err := json.Marshal(out)
	return repo, b, err
}

func branchOf(r *ghRun) string {
	if r == nil {
		return ""
	}
	return r.HeadBranch
}
