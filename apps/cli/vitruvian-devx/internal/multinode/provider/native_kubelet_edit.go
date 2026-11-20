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

package provider

import (
	"bytes"
	"fmt"
	"path"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"
)

// This file holds the pure text edits `cluster relocate-kubelet` applies to a
// node's k3s configuration: dropping the `root-dir=...` kubelet argument and
// nothing else. They take and return strings so they are unit-testable without a
// host.

// kubeletArgKeys are the k3s config keys that carry kubelet arguments. A bare key
// replaces, a "+" suffix appends (valid in config.yaml and its drop-ins).
var kubeletArgKeys = map[string]bool{"kubelet-arg": true, "kubelet-arg+": true}

// isRootDirArg reports whether a kubelet-arg entry is the root-dir setting and
// returns its value. k3s accepts the entry with or without the leading "--".
func isRootDirArg(entry string) (string, bool) {
	e := strings.TrimPrefix(strings.TrimSpace(entry), "--")
	if v, ok := strings.CutPrefix(e, "root-dir="); ok {
		return strings.Trim(v, `"'`), true
	}
	return "", false
}

// rootDirValuesInConfig returns every kubelet root-dir value set in a k3s
// config.yaml.
func rootDirValuesInConfig(src string) ([]string, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(src), &doc); err != nil {
		return nil, fmt.Errorf("parsing k3s config.yaml: %w", err)
	}
	var vals []string
	if len(doc.Content) == 0 || doc.Content[0].Kind != yaml.MappingNode {
		return nil, nil
	}
	root := doc.Content[0]
	for i := 0; i+1 < len(root.Content); i += 2 {
		if !kubeletArgKeys[root.Content[i].Value] {
			continue
		}
		v := root.Content[i+1]
		switch v.Kind {
		case yaml.ScalarNode:
			if val, ok := isRootDirArg(v.Value); ok {
				vals = append(vals, val)
			}
		case yaml.SequenceNode:
			for _, item := range v.Content {
				if val, ok := isRootDirArg(item.Value); ok {
					vals = append(vals, val)
				}
			}
		}
	}
	return vals, nil
}

// removeRootDirFromConfig removes the root-dir entry from the kubelet-arg list of a
// k3s config.yaml, leaving every other key and every other kubelet-arg entry
// alone. A kubelet-arg list that becomes empty is removed entirely (an empty list
// is noise, and k3s treats it the same as absent). Reports whether anything
// changed; when nothing did, the input is returned verbatim.
func removeRootDirFromConfig(src string) (string, bool, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(src), &doc); err != nil {
		return "", false, fmt.Errorf("parsing k3s config.yaml: %w", err)
	}
	if len(doc.Content) == 0 || doc.Content[0].Kind != yaml.MappingNode {
		return src, false, nil
	}
	root := doc.Content[0]
	changed := false
	kept := make([]*yaml.Node, 0, len(root.Content))
	for i := 0; i+1 < len(root.Content); i += 2 {
		k, v := root.Content[i], root.Content[i+1]
		if !kubeletArgKeys[k.Value] {
			kept = append(kept, k, v)
			continue
		}
		switch v.Kind {
		case yaml.ScalarNode:
			if _, ok := isRootDirArg(v.Value); ok {
				changed = true
				continue // the whole key held only root-dir
			}
		case yaml.SequenceNode:
			items := make([]*yaml.Node, 0, len(v.Content))
			for _, item := range v.Content {
				if _, ok := isRootDirArg(item.Value); ok {
					changed = true
					continue
				}
				items = append(items, item)
			}
			if len(items) != len(v.Content) {
				if len(items) == 0 {
					continue // emptied: drop the key
				}
				v.Content = items
			}
		}
		kept = append(kept, k, v)
	}
	if !changed {
		return src, false, nil
	}
	root.Content = kept
	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(&doc); err != nil {
		return "", false, fmt.Errorf("rendering k3s config.yaml: %w", err)
	}
	_ = enc.Close()
	out := buf.String()
	if len(kept) == 0 {
		out = "" // nothing left; an empty config.yaml is valid
	}
	return out, true, nil
}

var (
	// `'--kubelet-arg=root-dir=/x'` (optionally quoted) as its own ExecStart line.
	unitRootDirLine = regexp.MustCompile(`^\s*['"]?--kubelet-arg=(?:--)?root-dir=[^'"\s]*['"]?\s*\\?\s*$`)
	// `'--kubelet-arg'` alone on a line, with the value on the next line.
	unitKubeletArgLine = regexp.MustCompile(`^\s*['"]?--kubelet-arg['"]?\s*\\?\s*$`)
	unitRootDirValue   = regexp.MustCompile(`^\s*['"]?(?:--)?root-dir=[^'"\s]*['"]?\s*\\?\s*$`)
	// the same argument inline on a long ExecStart line.
	unitRootDirInline = regexp.MustCompile(`\s+['"]?--kubelet-arg=(?:--)?root-dir=[^'"\s]*['"]?`)
	unitRootDirFind   = regexp.MustCompile(`--kubelet-arg=(?:--)?root-dir=([^'"\s\\]*)`)
	unitRootDirPair   = regexp.MustCompile(`--kubelet-arg['"]?\s*\\?\s*\n\s*['"]?(?:--)?root-dir=([^'"\s\\]*)`)
	trailingBackslash = regexp.MustCompile(`\s*\\\s*$`)
)

// rootDirValuesInUnit returns every kubelet root-dir value on a k3s unit's
// ExecStart.
func rootDirValuesInUnit(unit string) []string {
	var vals []string
	for _, m := range unitRootDirFind.FindAllStringSubmatch(unit, -1) {
		vals = append(vals, m[1])
	}
	for _, m := range unitRootDirPair.FindAllStringSubmatch(unit, -1) {
		vals = append(vals, m[1])
	}
	return vals
}

// removeRootDirFromUnit removes the root-dir kubelet argument from a k3s systemd
// unit's ExecStart, keeping every other line. The k3s installer writes one quoted
// argument per line joined by trailing backslashes; if the removed argument was
// the last line, the previous line's backslash is dropped so the continuation
// does not run into the next directive. Reports whether anything changed.
func removeRootDirFromUnit(unit string) (string, bool) {
	lines := strings.Split(unit, "\n")
	out := make([]string, 0, len(lines))
	changed := false
	for i := 0; i < len(lines); i++ {
		line := lines[i]
		pair := unitKubeletArgLine.MatchString(line) && i+1 < len(lines) && unitRootDirValue.MatchString(lines[i+1])
		if unitRootDirLine.MatchString(line) || pair {
			last := line
			if pair {
				i++
				last = lines[i]
			}
			changed = true
			if !strings.HasSuffix(strings.TrimSpace(last), `\`) && len(out) > 0 {
				// The removed line ended the ExecStart: the line before it must not
				// continue into whatever follows.
				out[len(out)-1] = trailingBackslash.ReplaceAllString(out[len(out)-1], "")
			}
			continue
		}
		if unitRootDirInline.MatchString(line) {
			line = unitRootDirInline.ReplaceAllString(line, "")
			changed = true
		}
		out = append(out, line)
	}
	if !changed {
		return unit, false
	}
	return strings.Join(out, "\n"), true
}

// samePath reports whether two directory paths are the same after cleaning.
func samePath(a, b string) bool {
	return path.Clean(a) == path.Clean(b)
}
