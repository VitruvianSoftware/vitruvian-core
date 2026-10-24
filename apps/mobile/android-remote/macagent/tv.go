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
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"
)

const (
	defaultTVAddress = "192.168.86.31:5555"
	tvCmdTimeout     = 5 * time.Second
)

// tvController drives a Sony Google TV over wireless ADB.
//
// Paths and the command runner are fields so unit tests can exercise every
// state transition and action against a temp config file and a fake runner
// without touching the network or requiring adb on the test runner.
type tvController struct {
	configPath       string
	legacyConfigPath string
	findAdb          func() string
	run              func(ctx context.Context, limit time.Duration, name string, args ...string) (stdout, stderr string, err error)
}

func defaultTVController() *tvController {
	home, _ := os.UserHomeDir()
	return &tvController{
		configPath:       filepath.Join(home, ".config", "vitruvian", "tv.json"),
		legacyConfigPath: filepath.Join(home, "Library", "Application Support", "com.vitruviansoftware.vitruvian", "ToolData", "dev.vitruvian.tv", "storage.json"),
		findAdb:          defaultFindAdb,
		run:              runToolWithin,
	}
}

func defaultFindAdb() string {
	home, _ := os.UserHomeDir()
	candidates := []string{
		"/opt/homebrew/bin/adb",
		"/usr/local/bin/adb",
		filepath.Join(home, "Library", "Android", "sdk", "platform-tools", "adb"),
	}
	for _, p := range candidates {
		if st, err := os.Stat(p); err == nil && !st.IsDir() && st.Mode()&0o111 != 0 {
			return p
		}
	}
	if p, err := exec.LookPath("adb"); err == nil {
		return p
	}
	return ""
}

// tvState is the JSON body of GET /v1/tv and the response to POST /v1/tv.
type tvState struct {
	Available      bool   `json:"available"`
	Reason         string `json:"reason,omitempty"`
	Connected      bool   `json:"connected"`
	Awake          bool   `json:"awake"`
	Dreaming       bool   `json:"dreaming"`
	Foreground     string `json:"foreground"`
	MemAvailableMB int    `json:"mem_available_mb"`
	Address        string `json:"address"`
}

// tvActionRequest is the body of POST /v1/tv.
type tvActionRequest struct {
	Action  string `json:"action"`
	Target  string `json:"target"`
	URL     string `json:"url"`
	Address string `json:"address"`
}

func (srv *server) tvRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/v1/tv", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet, http.MethodHead:
			srv.getTV(w, r)
		case http.MethodPost:
			srv.act(srv.postTV)(w, r)
		default:
			methodNotAllowed(w, "GET, HEAD, POST")
		}
	})
}

func (srv *server) getTV(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, srv.tv.state(r.Context()))
}

func (srv *server) postTV(w http.ResponseWriter, r *http.Request) {
	var req tvActionRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	code, err := srv.tv.act(r.Context(), req)
	if err != nil {
		writeError(w, code, err.Error())
		return
	}
	writeJSON(w, srv.tv.state(r.Context()))
}

// resolveAddress reads the configured TV address from ~/.config/vitruvian/tv.json,
// falling back to the desktop widget's storage.json and finally 192.168.86.31:5555.
func (t *tvController) resolveAddress() string {
	for _, p := range []string{t.configPath, t.legacyConfigPath} {
		if p == "" {
			continue
		}
		raw, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var doc map[string]any
		if err := json.Unmarshal(raw, &doc); err != nil {
			continue
		}
		for _, key := range []string{"address", "tvAddress"} {
			if v, ok := doc[key].(string); ok {
				if trimmed := strings.TrimSpace(v); trimmed != "" {
					return trimmed
				}
			}
		}
	}
	return defaultTVAddress
}

var memAvailableRe = regexp.MustCompile(`MemAvailable:\s+(\d+)\s+kB`)

// state queries the TV over ADB in a single shell round-trip after ensuring the
// wireless ADB connection is established.
func (t *tvController) state(ctx context.Context) tvState {
	addr := t.resolveAddress()
	adb := t.findAdb()
	if adb == "" {
		return tvState{
			Available:  false,
			Reason:     "adb is not installed on this Mac",
			Foreground: "Standby",
			Address:    addr,
		}
	}

	connOut, connErrText, _ := t.run(ctx, tvCmdTimeout, adb, "connect", addr)
	connCombined := strings.ToLower(connOut + "\n" + connErrText)

	const statusQuery = "dumpsys power | grep -E 'mWakefulness=' ; " +
		"dumpsys window displays | grep -E 'mCurrentFocus|mFocusedApp' ; " +
		"grep -E 'MemTotal|MemAvailable' /proc/meminfo"
	out, stderr, err := t.run(ctx, tvCmdTimeout, adb, "-s", addr, "shell", statusQuery)
	if err != nil || (!strings.Contains(connCombined, "connected to") && strings.TrimSpace(out) == "") {
		reason := strings.TrimSpace(stderr)
		if reason == "" {
			reason = strings.TrimSpace(connOut)
		}
		if reason == "" {
			reason = "could not connect to " + addr
		}
		if strings.Contains(strings.ToLower(reason), "unauthorized") {
			reason = "TV unauthorized: check 'Always allow from this computer' on the TV screen, or tap Reconnect"
		}
		return tvState{
			Available:  true,
			Reason:     reason,
			Connected:  false,
			Foreground: "Standby",
			Address:    addr,
		}
	}

	awake := strings.Contains(out, "mWakefulness=Awake")
	dreaming := strings.Contains(out, "mWakefulness=Dreaming") ||
		strings.Contains(out, "com.fourchars.lmp") ||
		strings.Contains(out, "Somnambulator")

	foreground := "Standby"
	switch {
	case !awake && !dreaming:
		foreground = "Standby"
	case dreaming || strings.Contains(out, "com.fourchars.lmp"):
		foreground = "AerialViews 4K"
	case strings.Contains(out, "com.liskovsoft.smarttubetv"):
		foreground = "SmartTube 4K"
	case strings.Contains(out, "com.spocky.projengmenu"):
		foreground = "Projectivy Home"
	case strings.Contains(out, "com.disney.disneyplus"):
		foreground = "Disney+"
	case strings.Contains(out, "com.netflix.ninja"):
		foreground = "Netflix"
	default:
		foreground = "Awake"
	}

	memMB := 0
	if m := memAvailableRe.FindStringSubmatch(out); len(m) == 2 {
		if kb, convErr := strconv.Atoi(m[1]); convErr == nil {
			memMB = kb / 1024
		}
	}

	return tvState{
		Available:      true,
		Connected:      true,
		Awake:          awake,
		Dreaming:       dreaming,
		Foreground:     foreground,
		MemAvailableMB: memMB,
		Address:        addr,
	}
}

var (
	tvAppPackages = map[string]string{
		"projectivy": "com.spocky.projengmenu",
		"smarttube":  "com.liskovsoft.smarttubetv.beta",
		"disney":     "com.disney.disneyplus",
		"netflix":    "com.netflix.ninja",
	}

	tvKeyCodes = map[string]string{
		"volume_up":   "24",
		"volume_down": "25",
		"mute":        "164",
		"play_pause":  "85",
		"home":        "3",
		"back":        "4",
		"up":          "19",
		"down":        "20",
		"left":        "21",
		"right":       "22",
		"select":      "23",
	}

	validHostRe = regexp.MustCompile(`^[A-Za-z0-9.-]+$`)
)

func (t *tvController) act(ctx context.Context, req tvActionRequest) (int, error) {
	action := strings.TrimSpace(req.Action)
	target := strings.TrimSpace(req.Target)

	if action == "set_address" {
		addr := strings.TrimSpace(req.Address)
		if addr == "" {
			addr = target
		}
		normalized, err := validateTVAddress(addr)
		if err != nil {
			return http.StatusBadRequest, err
		}
		if err := t.saveAddress(normalized); err != nil {
			return http.StatusInternalServerError, err
		}
		if adb := t.findAdb(); adb != "" {
			_, _, _ = t.run(ctx, tvCmdTimeout, adb, "disconnect", normalized)
			_, _, _ = t.run(ctx, tvCmdTimeout, adb, "connect", normalized)
		}
		log.Printf("act tv: set_address %s", normalized)
		return http.StatusOK, nil
	}

	adb := t.findAdb()
	if adb == "" {
		return http.StatusServiceUnavailable, errors.New("adb is not installed on this Mac")
	}
	addr := t.resolveAddress()

	switch action {
	case "reconnect":
		if rawAddr := firstNonEmpty(req.Address, target); rawAddr != "" {
			normalized, err := validateTVAddress(rawAddr)
			if err != nil {
				return http.StatusBadRequest, err
			}
			if err := t.saveAddress(normalized); err != nil {
				return http.StatusInternalServerError, err
			}
			addr = normalized
		}
		log.Printf("act tv: reconnect %s", addr)
		_, _, _ = t.run(ctx, tvCmdTimeout, adb, "disconnect", addr)
		_, _, _ = t.run(ctx, tvCmdTimeout, adb, "connect", addr)
		return http.StatusOK, nil

	case "toggle_power":
		_, _, _ = t.run(ctx, tvCmdTimeout, adb, "connect", addr)
		out, _, _ := t.run(ctx, tvCmdTimeout, adb, "-s", addr, "shell", "dumpsys power | grep mWakefulness=")
		key := "KEYCODE_WAKEUP"
		if strings.Contains(out, "mWakefulness=Awake") || strings.Contains(out, "mWakefulness=Dreaming") {
			key = "KEYCODE_SLEEP"
		}
		log.Printf("act tv: toggle_power (%s) on %s", key, addr)
		if _, stderr, err := t.run(ctx, tvCmdTimeout, adb, "-s", addr, "shell", "input", "keyevent", key); err != nil {
			return http.StatusBadGateway, fmt.Errorf("adb toggle_power failed: %s", firstNonEmpty(stderr, err.Error()))
		}
		return http.StatusOK, nil

	case "start_aerial":
		_, _, _ = t.run(ctx, tvCmdTimeout, adb, "connect", addr)
		log.Printf("act tv: start_aerial on %s", addr)
		cmd := "input keyevent KEYCODE_WAKEUP && am start -n com.android.systemui/.Somnambulator"
		if _, stderr, err := t.run(ctx, tvCmdTimeout, adb, "-s", addr, "shell", cmd); err != nil {
			return http.StatusBadGateway, fmt.Errorf("adb start_aerial failed: %s", firstNonEmpty(stderr, err.Error()))
		}
		return http.StatusOK, nil

	case "launch_app":
		pkg, ok := tvAppPackages[target]
		if !ok {
			return http.StatusBadRequest, fmt.Errorf("unknown app target %q (want projectivy, smarttube, disney, or netflix)", target)
		}
		_, _, _ = t.run(ctx, tvCmdTimeout, adb, "connect", addr)
		log.Printf("act tv: launch_app %s (%s) on %s", target, pkg, addr)
		cmd := fmt.Sprintf("input keyevent KEYCODE_WAKEUP && monkey -p %s -c android.intent.category.LAUNCHER 1", pkg)
		if _, stderr, err := t.run(ctx, tvCmdTimeout, adb, "-s", addr, "shell", cmd); err != nil {
			return http.StatusBadGateway, fmt.Errorf("adb launch_app failed: %s", firstNonEmpty(stderr, err.Error()))
		}
		return http.StatusOK, nil

	case "hdmi":
		switch target {
		case "1", "2", "3", "4":
		default:
			return http.StatusBadRequest, fmt.Errorf("unknown hdmi target %q (want 1, 2, 3, or 4)", target)
		}
		_, _, _ = t.run(ctx, tvCmdTimeout, adb, "connect", addr)
		log.Printf("act tv: hdmi %s on %s", target, addr)
		uri := "content://android.media.tv/passthrough/com.sony.dtv.tvinput.external/.ExternalTvInputService%2FHW" + target
		cmd := "input keyevent KEYCODE_WAKEUP && am start -a android.intent.action.VIEW -d " + uri
		if _, stderr, err := t.run(ctx, tvCmdTimeout, adb, "-s", addr, "shell", cmd); err != nil {
			return http.StatusBadGateway, fmt.Errorf("adb hdmi failed: %s", firstNonEmpty(stderr, err.Error()))
		}
		return http.StatusOK, nil

	case "key":
		code, ok := tvKeyCodes[target]
		if !ok {
			return http.StatusBadRequest, fmt.Errorf("unknown key target %q", target)
		}
		_, _, _ = t.run(ctx, tvCmdTimeout, adb, "connect", addr)
		log.Printf("act tv: key %s (%s) on %s", target, code, addr)
		if _, stderr, err := t.run(ctx, tvCmdTimeout, adb, "-s", addr, "shell", "input", "keyevent", code); err != nil {
			return http.StatusBadGateway, fmt.Errorf("adb key failed: %s", firstNonEmpty(stderr, err.Error()))
		}
		return http.StatusOK, nil

	case "cast_url":
		rawURL := strings.TrimSpace(req.URL)
		if rawURL == "" {
			rawURL = target
		}
		quoted, err := validateAndQuoteCastURL(rawURL)
		if err != nil {
			return http.StatusBadRequest, err
		}
		_, _, _ = t.run(ctx, tvCmdTimeout, adb, "connect", addr)
		log.Printf("act tv: cast_url on %s", addr)
		cmd := fmt.Sprintf("input keyevent KEYCODE_WAKEUP && am start -a android.intent.action.VIEW -d %s com.liskovsoft.smarttubetv.beta", quoted)
		if _, stderr, err := t.run(ctx, tvCmdTimeout, adb, "-s", addr, "shell", cmd); err != nil {
			return http.StatusBadGateway, fmt.Errorf("adb cast_url failed: %s", firstNonEmpty(stderr, err.Error()))
		}
		return http.StatusOK, nil

	case "trim_caches":
		_, _, _ = t.run(ctx, tvCmdTimeout, adb, "connect", addr)
		log.Printf("act tv: trim_caches on %s", addr)
		if _, stderr, err := t.run(ctx, tvCmdTimeout, adb, "-s", addr, "shell", "pm", "trim-caches", "999999999999999999"); err != nil {
			return http.StatusBadGateway, fmt.Errorf("adb trim_caches failed: %s", firstNonEmpty(stderr, err.Error()))
		}
		return http.StatusOK, nil

	default:
		return http.StatusBadRequest, fmt.Errorf("unknown action %q", action)
	}
}

func validateTVAddress(addr string) (string, error) {
	if addr == "" {
		return "", errors.New("address is required (expected host:port)")
	}
	host, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		return "", errors.New("address must be host:port (e.g. 192.168.86.31:5555)")
	}
	if host == "" || !validHostRe.MatchString(host) {
		return "", errors.New("invalid host in address")
	}
	port, err := strconv.Atoi(portStr)
	if err != nil || port < 1 || port > 65535 {
		return "", errors.New("port must be between 1 and 65535")
	}
	return net.JoinHostPort(host, strconv.Itoa(port)), nil
}

func validateAndQuoteCastURL(raw string) (string, error) {
	if raw == "" {
		return "", errors.New("url is required")
	}
	for _, r := range raw {
		if unicode.IsSpace(r) || unicode.IsControl(r) {
			return "", errors.New("url must not contain whitespace or control characters")
		}
	}
	parsed, err := url.Parse(raw)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return "", errors.New("url must be a valid http or https URL")
	}
	return "'" + strings.ReplaceAll(raw, "'", `'\''`) + "'", nil
}

func (t *tvController) saveAddress(addr string) error {
	if t.configPath == "" {
		return errors.New("no config path configured")
	}
	if err := os.MkdirAll(filepath.Dir(t.configPath), 0o700); err != nil {
		return err
	}
	doc := map[string]any{}
	if existing, err := os.ReadFile(t.configPath); err == nil {
		_ = json.Unmarshal(existing, &doc)
	}
	doc["address"] = addr
	data, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(t.configPath, data, 0o600)
}

func firstNonEmpty(a, b string) string {
	if s := strings.TrimSpace(a); s != "" {
		return s
	}
	return strings.TrimSpace(b)
}
