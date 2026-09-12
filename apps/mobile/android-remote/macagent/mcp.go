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
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// POST /mcp/phone: the MCP server that Claude Code and Antigravity talk to.
//
// It is deliberately the smallest thing that satisfies MCP Streamable HTTP:
// one JSON response per request, no server-initiated stream, so GET is 405.
// The tools it advertises are not this agent's -- they are whatever the
// phone declared on its link -- and every call is a round trip out over that
// link and back.
//
// Two locks on the door, and they guard different things.
//
//  1. LOOPBACK ONLY. The agent also listens on its Tailscale address, and
//     that address is reachable by every device on the tailnet. This
//     endpoint runs phone tools that can text people, so "on the tailnet" is
//     not good enough: the caller has to be a process on this Mac.
//  2. A BEARER TOKEN of its own, not the pairing token. The pairing token is
//     the phone's, it travels over the network, and a phone that pairs again
//     rotates it -- none of which should break an MCP client configured
//     months ago. This one is a file the client reads at 0600, never logged,
//     and it is what stops any other local process from driving the phone.

// mcpProtocolVersion is the MCP revision this speaks, echoed by initialize.
const mcpProtocolVersion = "2025-06-18"

// mcpServerName is what an MCP client shows in its server list.
const mcpServerName = "vitruvian-remote-phone"

// --- the token ---

// The MCP token lives beside the pairing token in the config directory and
// is created the same way: crypto/rand, 0600, on first start.
func (s *Store) mcpTokenPath() string { return filepath.Join(s.dir, "mcp-token") }

// EnsureMCPToken returns the loopback MCP token, creating it on first start.
// Never logged and never returned by any endpoint: the only way to read it
// is the file, which is the point -- a caller that can read it is already a
// process running as this user on this Mac.
func (s *Store) EnsureMCPToken() (string, error) {
	if err := os.MkdirAll(s.dir, 0o700); err != nil {
		return "", err
	}
	b, err := os.ReadFile(s.mcpTokenPath())
	if err == nil {
		if tok := strings.TrimSpace(string(b)); tok != "" {
			return tok, nil
		}
		// An empty file is a half-finished write from a previous run, not a
		// token. Replacing it beats serving it: an empty token compares
		// equal to an empty header.
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	raw := make([]byte, tokenBytes)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	tok := hex.EncodeToString(raw)
	if err := os.WriteFile(s.mcpTokenPath(), []byte(tok+"\n"), 0o600); err != nil {
		return "", err
	}
	return tok, nil
}

// MCPAuthorized compares a presented bearer to the MCP token in constant
// time, re-reading the file each call so a rotation needs no restart.
func (s *Store) MCPAuthorized(presented string) bool {
	b, err := os.ReadFile(s.mcpTokenPath())
	if err != nil {
		return false
	}
	tok := strings.TrimSpace(string(b))
	if tok == "" || presented == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(tok), []byte(presented)) == 1
}

// --- JSON-RPC ---

// jsonrpcRequest is the subset of JSON-RPC 2.0 this endpoint reads. The id
// is kept as raw JSON because the spec allows a string or a number and the
// only correct thing to do with it is echo it back unchanged.
type jsonrpcRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
}

// The JSON-RPC error codes this endpoint can produce. A tool that FAILED is
// not among them: that is a successful result carrying isError, which is
// MCP's design and the reason -32603 does not appear here.
const (
	rpcParseError     = -32700
	rpcMethodNotFound = -32601
	rpcInvalidParams  = -32602
)

// isLoopback reports whether a request arrived on 127.0.0.0/8 or ::1.
//
// RemoteAddr rather than the Host header or a listener check, because
// RemoteAddr is the one thing a caller cannot forge: it is the peer of the
// TCP connection. A request that reached the Tailscale listener has the
// tailnet peer's address here, which is not loopback, so the same test
// covers "not from the tailnet" without having to know which listener the
// request landed on.
func isLoopback(remoteAddr string) bool {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		// No port at all is not a shape this server produces; refuse rather
		// than guess.
		host = remoteAddr
	}
	ip := net.ParseIP(strings.Trim(host, "[]"))
	return ip != nil && ip.IsLoopback()
}

// mcpPhone is the whole endpoint.
func (srv *server) mcpPhone(w http.ResponseWriter, r *http.Request) {
	// v1.3 has no server-initiated stream, so the SSE half of Streamable
	// HTTP does not exist and GET is honestly 405 rather than an empty
	// stream a client would wait on forever.
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	if !isLoopback(r.RemoteAddr) {
		// 403, not 404: hiding the endpoint from the tailnet would not hide
		// it (the port is the same one), and "you are not local" is the
		// actionable message.
		writeError(w, http.StatusForbidden, "the MCP endpoint is loopback-only; run your agent on this Mac")
		return
	}
	presented, ok := bearer(r)
	if !ok || !srv.store.MCPAuthorized(presented) {
		w.Header().Set("WWW-Authenticate", `Bearer realm="vitruvian-remote-phone"`)
		writeError(w, http.StatusUnauthorized,
			"send the token in ~/.config/vitruvian-remote-agent/mcp-token as a bearer")
		return
	}

	var req jsonrpcRequest
	if err := decodeJSON(r, &req); err != nil {
		// Parse error has no id to echo, by definition: nothing was parsed.
		writeRPCError(w, nil, rpcParseError, "parse error: "+err.Error())
		return
	}
	// A JSON-RPC notification has no id and gets no reply. `initialized` is
	// the one every MCP client sends, and answering it with a JSON body is a
	// protocol error in some clients -- hence the empty 202.
	if strings.HasPrefix(req.Method, "notifications/") {
		w.WriteHeader(http.StatusAccepted)
		return
	}

	switch req.Method {
	case "initialize":
		writeRPCResult(w, req.ID, map[string]any{
			"protocolVersion": mcpProtocolVersion,
			"capabilities": map[string]any{
				// false, and true would be a lie: the phone's tool list does
				// change when it links, but there is no stream to announce
				// it on in v1.3.
				"tools": map[string]any{"listChanged": false},
			},
			"serverInfo": map[string]any{"name": mcpServerName, "version": version},
		})
	case "ping":
		writeRPCResult(w, req.ID, map[string]any{})
	case "tools/list":
		writeRPCResult(w, req.ID, map[string]any{"tools": mcpToolList(srv.phone.Tools())})
	case "tools/call":
		srv.mcpToolsCall(w, r, req)
	default:
		writeRPCError(w, req.ID, rpcMethodNotFound, "unknown method "+req.Method)
	}
}

// mcpToolList strips the tier and fills in an input schema for any tool that
// declared none. An MCP client that gets a tool with no inputSchema at all
// will usually refuse to call it, so an empty object schema is the honest
// "this tool takes nothing".
func mcpToolList(tools []phoneTool) []map[string]any {
	out := make([]map[string]any, 0, len(tools))
	for _, t := range tools {
		schema := t.InputSchema
		if len(schema) == 0 {
			schema = json.RawMessage(`{"type":"object","properties":{}}`)
		}
		out = append(out, map[string]any{
			"name":        t.Name,
			"description": t.Description,
			"inputSchema": schema,
		})
	}
	return out
}

// mcpToolsCall forwards one call to the phone and shapes the answer.
//
// The interesting rule is that a tool failure is a SUCCESSFUL JSON-RPC
// result carrying isError:true. That is MCP's design and not a shortcut: a
// -32603 would make the client abandon the tool, whereas isError puts the
// message in front of the model, which is what "grant Notification access
// first" is for.
func (srv *server) mcpToolsCall(w http.ResponseWriter, r *http.Request, req jsonrpcRequest) {
	var params struct {
		Name      string          `json:"name"`
		Arguments json.RawMessage `json:"arguments"`
	}
	if len(req.Params) > 0 {
		if err := json.Unmarshal(req.Params, &params); err != nil {
			writeRPCError(w, req.ID, rpcInvalidParams, "params must be {name, arguments}")
			return
		}
	}
	if params.Name == "" {
		writeRPCError(w, req.ID, rpcInvalidParams, "a tool name is required")
		return
	}
	// The tool name only -- the arguments are an SMS body, a contact search,
	// a screen coordinate. The Mac keeps a record of WHAT was asked for, and
	// the phone's own audit log keeps the rest.
	logAct("mcp", params.Name)

	res, err := srv.phone.dispatch(r.Context(), params.Name, params.Arguments,
		phoneCallTimeout(srv.phone.tierOf(params.Name)))
	if err != nil {
		if errors.Is(err, errNoPhone) {
			writeRPCResult(w, req.ID, map[string]any{
				"content": textContent(errNoPhone.Error()),
				"isError": true,
			})
			return
		}
		if r.Context().Err() != nil {
			// The client hung up. Nothing to write to.
			return
		}
		// A timeout is also a tool error, for the same reason: the model
		// should see "the phone did not answer" and be able to try again.
		writeRPCResult(w, req.ID, map[string]any{
			"content": textContent(err.Error()),
			"isError": true,
		})
		return
	}
	content := res.Content
	if len(content) == 0 {
		content = textContent("")
	}
	writeRPCResult(w, req.ID, map[string]any{"content": content, "isError": res.IsError})
}

func writeRPCResult(w http.ResponseWriter, id json.RawMessage, result any) {
	writeJSON(w, map[string]any{"jsonrpc": "2.0", "id": rpcID(id), "result": result})
}

func writeRPCError(w http.ResponseWriter, id json.RawMessage, code int, msg string) {
	// 200 with a JSON-RPC error body, not an HTTP error status: the
	// transport worked, and a client that saw a 4xx would report a
	// connection problem rather than the method problem it actually has.
	writeJSON(w, map[string]any{
		"jsonrpc": "2.0",
		"id":      rpcID(id),
		"error":   map[string]any{"code": code, "message": msg},
	})
}

// rpcID echoes the request's id verbatim, or null when there was none.
func rpcID(id json.RawMessage) any {
	if len(id) == 0 {
		return nil
	}
	return id
}
