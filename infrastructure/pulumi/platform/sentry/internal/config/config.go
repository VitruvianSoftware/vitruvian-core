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
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

type ProjectConfig struct {
	Name       string `json:"name"`
	Slug       string `json:"slug"`
	Platform   string `json:"platform"`
	ResolveAge int    `json:"resolveAge"`
}

type TeamConfig struct {
	Name string `json:"name"`
	Slug string `json:"slug"`
}

type StackConfig struct {
	BaseURL      string          `json:"baseUrl"`
	Organization string          `json:"organization"`
	Team         TeamConfig      `json:"team"`
	Projects     []ProjectConfig `json:"projects"`
}

func Load(ctx *pulumi.Context) (*StackConfig, error) {
	cfg := config.New(ctx, "sentry")

	var sc StackConfig
	sc.BaseURL = cfg.Require("baseUrl")
	sc.Organization = cfg.Get("organization")
	if sc.Organization == "" {
		sc.Organization = "sentry"
	}

	if err := cfg.TryObject("team", &sc.Team); err != nil {
		return nil, fmt.Errorf("loading sentry:team config: %w", err)
	}

	if err := cfg.TryObject("projects", &sc.Projects); err != nil {
		return nil, fmt.Errorf("loading sentry:projects config: %w", err)
	}

	return &sc, nil
}
