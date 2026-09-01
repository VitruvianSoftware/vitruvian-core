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
	"strings"
)

// MatrixEntry represents one job in GitHub Actions dynamic matrix fan-out.
type MatrixEntry struct {
	Name             string            `json:"name"`
	Package          string            `json:"package"`
	Targets          string            `json:"targets"`
	TestTargets      string            `json:"test_targets"`
	Runner           string            `json:"runner"`
	Tier             string            `json:"tier"`
	Persona          string            `json:"persona"`
	TimeoutMinutes   int               `json:"timeout_minutes"`
	ConcurrencyGroup string            `json:"concurrency_group"`
	Env              map[string]string `json:"env,omitempty"`
	Needs            []string          `json:"needs,omitempty"`
}

// MatrixPayload represents the GitHub Actions matrix output format.
type MatrixPayload struct {
	Include []MatrixEntry `json:"include"`
}

// CompileMatrix builds the dynamic matrix payload from units with optional tier and persona filters.
func CompileMatrix(units []Unit, tierFilter, personaFilter string) MatrixPayload {
	var entries []MatrixEntry

	for _, u := range units {
		if tierFilter != "" && tierFilter != "all" && u.Tier != tierFilter {
			continue
		}
		if personaFilter != "" && personaFilter != "all" && u.Persona != "all" && u.Persona != personaFilter {
			continue
		}

		targetsStr := strings.Join(u.TestTargets, " ")
		entries = append(entries, MatrixEntry{
			Name:             u.Name,
			Package:          u.Package,
			Targets:          targetsStr,
			TestTargets:      targetsStr,
			Runner:           u.Runner,
			Tier:             u.Tier,
			Persona:          u.Persona,
			TimeoutMinutes:   u.TimeoutMinutes,
			ConcurrencyGroup: u.ConcurrencyGroup,
			Env:              u.Env,
			Needs:            u.DependsOn,
		})
	}

	return MatrixPayload{Include: entries}
}

// RenderMatrixJSON formats the matrix payload into indented JSON.
func RenderMatrixJSON(payload MatrixPayload) (string, error) {
	b, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return "", err
	}
	return string(b) + "\n", nil
}
