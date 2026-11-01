// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os/signal"
	"strings"
	"syscall"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/VitruvianSoftware/courier/engine/internal/localapi"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// mcpStdioUsage is the mcp-stdio subcommand's usage.
const mcpStdioUsage = "usage: courier-engine mcp-stdio [--port N]   (the token comes from COURIER_TOKEN)"

// The lines mcp-stdio ends with when it can't serve. Each is one plain line on stderr, before exit status 1.
const (
	stdioNoToken     = "courier-engine mcp-stdio: COURIER_TOKEN isn't set. Create a connection in Courier's Settings → Integrations and pass its token as COURIER_TOKEN."
	stdioNotRunning  = "courier-engine mcp-stdio: Courier isn't accepting connections. Turn on Settings → Integrations → Allow connections."
	stdioBadToken    = "courier-engine mcp-stdio: Courier didn't accept the token in COURIER_TOKEN. It may have been revoked: create a new connection in Settings → Integrations."
	stdioToolsFailed = "courier-engine mcp-stdio: Courier answered, but its tools couldn't be listed."
)

// runMCPStdio is `courier-engine mcp-stdio`: an MCP server on stdin and stdout for clients that only speak stdio,
// forwarding every request to the running Courier's local API at http://127.0.0.1:<port>/v0/mcp with the token in
// COURIER_TOKEN. Its tools are the local API's own, listed from it at start. It ends when stdin does.
//
// It writes nothing but MCP to stdout, and on stderr only the one line that says why it can't serve. It never
// writes the token anywhere.
func runMCPStdio(argv []string, stdin io.ReadCloser, stdout io.WriteCloser, stderr io.Writer, getenv func(string) string) int {
	fs := flag.NewFlagSet("courier-engine mcp-stdio", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	port := fs.Int("port", store.DefaultLocalAPIPort, "the local API's port")
	if err := fs.Parse(argv); err != nil || fs.NArg() > 0 || *port < 1 || *port > 65535 {
		fmt.Fprintln(stderr, mcpStdioUsage)
		return exitUsage
	}
	token := strings.TrimSpace(getenv("COURIER_TOKEN"))
	if token == "" {
		fmt.Fprintln(stderr, stdioNoToken)
		return exitFailed
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	endpoint := fmt.Sprintf("http://127.0.0.1:%d%s", *port, localapi.MCPPath)
	client := mcp.NewClient(&mcp.Implementation{Name: "courier-engine-mcp-stdio", Version: version}, nil)
	remote, err := client.Connect(ctx, &mcp.StreamableClientTransport{
		Endpoint:             endpoint,
		HTTPClient:           &http.Client{Transport: bearerTransport{token: token, base: http.DefaultTransport}},
		DisableStandaloneSSE: true,
		MaxRetries:           -1,
	}, nil)
	if err != nil {
		if isUnauthorized(err) {
			fmt.Fprintln(stderr, stdioBadToken)
		} else {
			fmt.Fprintln(stderr, stdioNotRunning)
		}
		return exitFailed
	}
	defer remote.Close()

	var tools []*mcp.Tool
	for tool, err := range remote.Tools(ctx, nil) {
		if err != nil {
			if isUnauthorized(err) {
				fmt.Fprintln(stderr, stdioBadToken)
			} else {
				fmt.Fprintln(stderr, stdioToolsFailed)
			}
			return exitFailed
		}
		tools = append(tools, tool)
	}

	instructions := ""
	if init := remote.InitializeResult(); init != nil {
		instructions = init.Instructions
	}
	local := mcp.NewServer(&mcp.Implementation{Name: "courier", Title: "Courier", Version: version}, &mcp.ServerOptions{Instructions: instructions})
	for _, tool := range tools {
		local.AddTool(tool, forward(remote, tool.Name))
	}
	if err := local.Run(ctx, &mcp.IOTransport{Reader: stdin, Writer: stdout}); err != nil && ctx.Err() == nil && !errors.Is(err, io.EOF) {
		return exitFailed
	}
	return 0
}

// forward is a tool that calls the same tool on Courier and hands back its answer, a tool error included. Courier
// going away mid-session is a tool error too.
func forward(remote *mcp.ClientSession, name string) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var args any
		if len(req.Params.Arguments) > 0 {
			args = req.Params.Arguments
		}
		res, err := remote.CallTool(ctx, &mcp.CallToolParams{Name: name, Arguments: args})
		if err != nil {
			msg := "Courier stopped answering. Check that it is running and that Allow connections is on."
			if isUnauthorized(err) {
				msg = "Courier no longer accepts this connection's token: it may have been revoked."
			}
			return &mcp.CallToolResult{IsError: true, Content: []mcp.Content{&mcp.TextContent{Text: msg}}}, nil
		}
		return res, nil
	}
}

// isUnauthorized is whether err is the local API refusing the token (HTTP 401).
func isUnauthorized(err error) bool {
	return err != nil && strings.Contains(err.Error(), http.StatusText(http.StatusUnauthorized))
}

// bearerTransport adds the token to every request.
type bearerTransport struct {
	token string
	base  http.RoundTripper
}

func (b bearerTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	r = r.Clone(r.Context())
	r.Header.Set("Authorization", "Bearer "+b.token)
	return b.base.RoundTrip(r)
}
