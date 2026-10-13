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

package toolkit

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// The protocol's files, from this folder: the same path in this repository,
// under Bazel and in the published mirror.
var protocolFolder = filepath.Join("..", "..", "protocol")

func readJSON(t *testing.T, name string, into any) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(protocolFolder, name))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, into); err != nil {
		t.Fatal(err)
	}
}

// exported is the Go name the generator gives a definition of the schema.
func exported(definition string) string {
	if definition == "" {
		return ""
	}
	if strings.HasPrefix(definition, "ui") && len(definition) > 2 && strings.ToUpper(definition[2:3]) == definition[2:3] {
		return "UI" + definition[2:]
	}
	return strings.ToUpper(definition[:1]) + definition[1:]
}

func TestMethodsAreMethodsJSON(t *testing.T) {
	var table struct {
		Protocol string `json:"protocol"`
		Methods  []struct {
			Method, Sender, Kind string
			Uses, Params, Result *string
		} `json:"methods"`
	}
	readJSON(t, "methods.json", &table)
	if table.Protocol != ProtocolVersion {
		t.Errorf("protocol %q, the types are %q", table.Protocol, ProtocolVersion)
	}
	var want []Method
	text := func(value *string) string {
		if value == nil {
			return ""
		}
		return *value
	}
	for _, row := range table.Methods {
		want = append(want, Method{
			Name: row.Method, Sender: row.Sender, Kind: row.Kind, Uses: text(row.Uses),
			Params: exported(text(row.Params)), Result: exported(text(row.Result)),
		})
	}
	if !reflect.DeepEqual(Methods, want) {
		t.Errorf("Methods is not methods.json:\n%v\n%v", Methods, want)
	}
}

// contains says whether every field of small is in big with the same
// value: what a type wrote back is what it read, less what it does not know.
func contains(big, small any) bool {
	switch small := small.(type) {
	case map[string]any:
		outer, ok := big.(map[string]any)
		if !ok {
			return false
		}
		for key, value := range small {
			if !contains(outer[key], value) {
				return false
			}
		}
		return true
	case []any:
		outer, ok := big.([]any)
		if !ok || len(outer) != len(small) {
			return false
		}
		for index := range small {
			if !contains(outer[index], small[index]) {
				return false
			}
		}
		return true
	default:
		return reflect.DeepEqual(big, small)
	}
}

// again reads part as the type named and writes it back, and says whether
// the two agree: equal, or for a part with fields the protocol does not
// have, the same less those.
func again(t *testing.T, where, name string, part any, exact bool) {
	t.Helper()
	raw, _ := json.Marshal(part)
	out, known, err := roundTrip(name, raw)
	if !known || err != nil {
		t.Errorf("%s: %s cannot be read (known %v): %v", where, name, known, err)
		return
	}
	var back any
	_ = json.Unmarshal(out, &back)
	if !contains(part, back) || (exact && !reflect.DeepEqual(part, back)) {
		t.Errorf("%s: %s wrote back\n%s\nfor\n%s", where, name, out, raw)
	}
}

func TestEveryMessageExampleReadsAndWritesBack(t *testing.T) {
	var examples struct {
		Examples []struct {
			About, Answers string
			Valid          bool
			UnknownFields  bool `json:"unknownFields"`
			Message        map[string]any
		}
	}
	readJSON(t, "examples/messages.json", &examples)
	rows := map[string]Method{}
	for _, row := range Methods {
		rows[row.Name] = row
	}
	checked := 0
	for _, example := range examples.Examples {
		if !example.Valid {
			continue
		}
		message, exact := example.Message, !example.UnknownFields
		switch {
		case message["method"] != nil && rows[message["method"].(string)].Params != "" && message["params"] != nil:
			again(t, example.About, rows[message["method"].(string)].Params, message["params"], exact)
		case message["error"] != nil:
			again(t, example.About, "Error", message["error"], exact)
		case message["result"] != nil && rows[example.Answers].Result != "":
			again(t, example.About, rows[example.Answers].Result, message["result"], exact)
		default:
			continue
		}
		checked++
	}
	if checked < 30 {
		t.Errorf("only %d examples were read", checked)
	}
}

func TestEveryManifestExampleReadsAndWritesBack(t *testing.T) {
	var examples struct {
		Base     map[string]any
		Examples []struct {
			About  string
			Valid  bool
			Change map[string]any
		}
	}
	readJSON(t, "examples/manifests.json", &examples)
	checked := 0
	for _, example := range examples.Examples {
		if !example.Valid {
			continue
		}
		manifest := map[string]any{}
		for key, value := range examples.Base {
			manifest[key] = value
		}
		for key, value := range example.Change {
			if value == nil {
				delete(manifest, key)
			} else {
				manifest[key] = value
			}
		}
		again(t, example.About, "Manifest", manifest, false)
		checked++
	}
	if checked < 5 {
		t.Errorf("only %d manifests were read", checked)
	}
}

func TestANilListIsWrittenEmpty(t *testing.T) {
	written, _ := json.Marshal(KeystrokesPressMenuItemParams{Equivalents: []KeyEquivalent{{Character: "c"}}})
	if string(written) != `{"equivalents":[{"character":"c","modifiers":[]}]}` {
		t.Errorf("wrote %s", written)
	}
}
