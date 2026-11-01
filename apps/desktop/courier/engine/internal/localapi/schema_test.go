// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localapi_test

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/stretchr/testify/require"
)

// referenceTools is protocol/mcp-tools.json: in the test's runfiles under Bazel, by its place in the source tree
// under plain go test.
func referenceTools(t *testing.T) map[string]map[string]any {
	t.Helper()
	const rel = "apps/desktop/courier/protocol/mcp-tools.json"
	var tried []string
	if srcdir := os.Getenv("TEST_SRCDIR"); srcdir != "" {
		ws := os.Getenv("TEST_WORKSPACE")
		if ws == "" {
			ws = "_main"
		}
		tried = append(tried, filepath.Join(srcdir, ws, rel), filepath.Join(srcdir, rel))
	}
	tried = append(tried, filepath.Join("..", "..", "..", "protocol", "mcp-tools.json"))
	for _, p := range tried {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var f struct {
			Tools []struct {
				Name        string         `json:"name"`
				InputSchema map[string]any `json:"inputSchema"`
			} `json:"tools"`
		}
		require.NoError(t, json.Unmarshal(b, &f))
		out := map[string]map[string]any{}
		for _, tool := range f.Tools {
			out[tool.Name] = tool.InputSchema
		}
		require.NotEmpty(t, out)
		return out
	}
	t.Fatalf("mcp-tools.json not found; tried %v", tried)
	return nil
}

// listTools is tools/list from an in-memory client.
func listTools(t *testing.T) []*mcp.Tool {
	t.Helper()
	w := storeOnly(t)
	ctx := context.Background()
	ct, st := mcp.NewInMemoryTransports()
	ss, err := w.api.MCP().Connect(ctx, st, nil)
	require.NoError(t, err)
	t.Cleanup(func() { ss.Close() })
	cs, err := mcp.NewClient(&mcp.Implementation{Name: "schema-test", Version: "1"}, nil).Connect(ctx, ct, nil)
	require.NoError(t, err)
	t.Cleanup(func() { cs.Close() })
	res, err := cs.ListTools(ctx, nil)
	require.NoError(t, err)
	return res.Tools
}

// withoutDescriptions is a schema with every description left out: those are Courier's own.
func withoutDescriptions(v any) any {
	switch v := v.(type) {
	case map[string]any:
		out := map[string]any{}
		for k, x := range v {
			if k != "description" {
				out[k] = withoutDescriptions(x)
			}
		}
		return out
	case []any:
		out := make([]any, len(v))
		for i, x := range v {
			out[i] = withoutDescriptions(x)
		}
		return out
	}
	return v
}

// Every tool's name and input schema match the reference app's exactly: the same names (no extras), and the same
// properties, types, enums, formats, nested objects, anyOf and required.
func TestToolsMatchReferenceSchemas(t *testing.T) {
	want := referenceTools(t)
	got := map[string]any{}
	for _, tool := range listTools(t) {
		b, err := json.Marshal(tool.InputSchema)
		require.NoError(t, err)
		var schema any
		require.NoError(t, json.Unmarshal(b, &schema))
		got[tool.Name] = withoutDescriptions(schema)
	}
	var wantNames, gotNames []string
	for n := range want {
		wantNames = append(wantNames, n)
	}
	for n := range got {
		gotNames = append(gotNames, n)
	}
	sort.Strings(wantNames)
	sort.Strings(gotNames)
	require.Equal(t, wantNames, gotNames, "the same tools, no extras")
	for name, schema := range want {
		wantJSON, err := json.Marshal(withoutDescriptions(schema))
		require.NoError(t, err)
		gotJSON, err := json.Marshal(got[name])
		require.NoError(t, err)
		require.JSONEq(t, string(wantJSON), string(gotJSON), "tool %s's input schema", name)
	}
}

// Descriptions are Courier's own and never name the reference app.
func TestNoDescriptionMentionsReferenceApp(t *testing.T) {
	var check func(path string, v any)
	check = func(path string, v any) {
		switch v := v.(type) {
		case map[string]any:
			for k, x := range v {
				if k == "description" {
					s, _ := x.(string)
					require.NotContains(t, strings.ToLower(s), "beeper", path)
					require.NotEmpty(t, s, path)
				}
				check(path+"."+k, x)
			}
		case []any:
			for _, x := range v {
				check(path, x)
			}
		}
	}
	for _, tool := range listTools(t) {
		require.NotContains(t, strings.ToLower(tool.Description), "beeper", tool.Name)
		require.NotEmpty(t, tool.Description, tool.Name)
		b, err := json.Marshal(tool.InputSchema)
		require.NoError(t, err)
		var schema any
		require.NoError(t, json.Unmarshal(b, &schema))
		check(tool.Name, schema)
	}
}
