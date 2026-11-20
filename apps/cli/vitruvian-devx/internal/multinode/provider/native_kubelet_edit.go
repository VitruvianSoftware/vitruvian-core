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
	"errors"
	"fmt"
	"path"
	"reflect"
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

// errUnsafeEdit means the config has a shape the line-based edit will not touch
// (a multi-line flow list, for instance). The caller refuses and the operator edits
// the file by hand.
var errUnsafeEdit = errors.New("cannot edit this k3s config safely")

// removeRootDirFromConfig removes the root-dir entry from the kubelet-arg list of a
// k3s config.yaml, leaving every other byte alone: it deletes only the line(s) that
// hold the entry (and the key line when that empties the list), so comments, the
// header, ordering and quoting all survive. A single-line flow list that keeps
// other entries is rewritten in place. The result is checked: it must decode to
// exactly the original with the root-dir entry removed, or the edit is refused.
// Reports whether anything changed; when nothing did, the input is returned
// verbatim.
func removeRootDirFromConfig(src string) (string, bool, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(src), &doc); err != nil {
		return "", false, fmt.Errorf("parsing k3s config.yaml: %w", err)
	}
	if len(doc.Content) == 0 || doc.Content[0].Kind != yaml.MappingNode {
		return src, false, nil
	}
	lines := strings.Split(src, "\n")
	drop := map[int]bool{}      // 0-based line indexes to delete
	replace := map[int]string{} // 0-based line index -> new text
	root := doc.Content[0]
	for i := 0; i+1 < len(root.Content); i += 2 {
		k, v := root.Content[i], root.Content[i+1]
		if !kubeletArgKeys[k.Value] {
			continue
		}
		switch v.Kind {
		case yaml.ScalarNode:
			if _, ok := isRootDirArg(v.Value); ok {
				if v.Line != k.Line {
					return "", false, fmt.Errorf("%w: %s value is on a different line from its key", errUnsafeEdit, k.Value)
				}
				drop[k.Line-1] = true
			}
		case yaml.SequenceNode:
			var keep []string
			var rootItems []*yaml.Node
			for _, item := range v.Content {
				if _, ok := isRootDirArg(item.Value); ok {
					rootItems = append(rootItems, item)
				} else {
					keep = append(keep, item.Value)
				}
			}
			if len(rootItems) == 0 {
				continue
			}
			if v.Style&yaml.FlowStyle != 0 {
				idx := strings.Index(lines[k.Line-1], "[")
				for _, item := range v.Content {
					if item.Line != k.Line {
						return "", false, fmt.Errorf("%w: %s is a multi-line flow list", errUnsafeEdit, k.Value)
					}
				}
				if idx < 0 {
					return "", false, fmt.Errorf("%w: cannot find the start of the %s list", errUnsafeEdit, k.Value)
				}
				if len(keep) == 0 {
					drop[k.Line-1] = true
				} else {
					quoted := make([]string, len(keep))
					for n, kv := range keep {
						b, _ := yaml.Marshal(kv)
						quoted[n] = strings.TrimSpace(string(b))
					}
					replace[k.Line-1] = lines[k.Line-1][:idx] + "[" + strings.Join(quoted, ", ") + "]"
				}
				continue
			}
			for _, item := range rootItems {
				drop[item.Line-1] = true
			}
			if len(keep) == 0 {
				drop[k.Line-1] = true
			}
		}
	}
	if len(drop) == 0 && len(replace) == 0 {
		return src, false, nil
	}
	out := make([]string, 0, len(lines))
	for n, l := range lines {
		if drop[n] {
			continue
		}
		if r, ok := replace[n]; ok {
			l = r
		}
		out = append(out, l)
	}
	res := strings.Join(out, "\n")
	if err := verifyRootDirRemoval(src, res); err != nil {
		return "", false, err
	}
	return res, true, nil
}

// verifyRootDirRemoval checks that after decodes to exactly before minus its
// root-dir kubelet-arg entries.
func verifyRootDirRemoval(before, after string) error {
	var b, a map[string]any
	if err := yaml.Unmarshal([]byte(before), &b); err != nil {
		return fmt.Errorf("parsing k3s config.yaml: %w", err)
	}
	if err := yaml.Unmarshal([]byte(after), &a); err != nil {
		return fmt.Errorf("%w: the edited file does not parse: %v", errUnsafeEdit, err)
	}
	for key := range kubeletArgKeys {
		switch v := b[key].(type) {
		case string:
			if _, ok := isRootDirArg(v); ok {
				delete(b, key)
			}
		case []any:
			var keep []any
			for _, item := range v {
				if str, ok := item.(string); ok {
					if _, isRoot := isRootDirArg(str); isRoot {
						continue
					}
				}
				keep = append(keep, item)
			}
			if len(keep) == 0 {
				delete(b, key)
			} else {
				b[key] = keep
			}
		}
	}
	if len(b) == 0 && len(a) == 0 {
		return nil
	}
	if !reflect.DeepEqual(b, a) {
		return fmt.Errorf("%w: the edit would change more than the root-dir entry", errUnsafeEdit)
	}
	return nil
}

// lineDiff renders the lines that differ between a and b as "- old" / "+ new"
// lines, in order, found with a longest-common-subsequence match.
func lineDiff(a, b string) string {
	x, y := strings.Split(strings.TrimRight(a, "\n"), "\n"), strings.Split(strings.TrimRight(b, "\n"), "\n")
	lcs := make([][]int, len(x)+1)
	for i := range lcs {
		lcs[i] = make([]int, len(y)+1)
	}
	for i := len(x) - 1; i >= 0; i-- {
		for j := len(y) - 1; j >= 0; j-- {
			if x[i] == y[j] {
				lcs[i][j] = lcs[i+1][j+1] + 1
			} else if lcs[i+1][j] >= lcs[i][j+1] {
				lcs[i][j] = lcs[i+1][j]
			} else {
				lcs[i][j] = lcs[i][j+1]
			}
		}
	}
	var out []string
	i, j := 0, 0
	for i < len(x) && j < len(y) {
		switch {
		case x[i] == y[j]:
			i++
			j++
		case lcs[i+1][j] >= lcs[i][j+1]:
			out = append(out, "- "+x[i])
			i++
		default:
			out = append(out, "+ "+y[j])
			j++
		}
	}
	for ; i < len(x); i++ {
		out = append(out, "- "+x[i])
	}
	for ; j < len(y); j++ {
		out = append(out, "+ "+y[j])
	}
	return strings.Join(out, "\n")
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
