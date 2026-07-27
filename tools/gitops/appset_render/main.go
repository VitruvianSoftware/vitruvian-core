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

// appset_render — simulate ArgoCD ApplicationSet goTemplate rendering, offline.
//
// WHY THIS EXISTS. `tools/ci/gitops-validate.sh` kubeconforms the STATIC YAML
// under gitops/argocd. It never expands an ApplicationSet, so the one render
// failure class this repo has actually suffered sails straight through it and
// reconciles live against the single cluster (app-of-platform PRUNES).
//
// The failure is real and documented. Issue #414: a literal backtick inside the
// prometheus values block closed a Go raw-string early and broke goTemplate
// rendering of the whole appset. The guard rail today is a PROSE COMMENT
// (gitops/argocd/platform/prometheus/applicationset.yaml:637-641) plus
// CONTRIBUTING.md:419, which tells contributors to "simulate-render before
// merge" -- while providing nothing to simulate with. This is that thing.
//
// WHY NOT `helm template`. All 26 chart sources in this repo are REMOTE (20
// HTTPS Helm repos + 2 OCI registries); nothing under gitops/ renders offline.
// Pulling and rendering every platform chart is also exactly what OOM-killed the
// argocd repo-server at 256Mi (#422). Chart rendering is a different, expensive,
// network-bound check -- and it is NOT what broke. What broke was goTemplate
// PARSING, which is pure CPU and needs neither network nor cluster.
//
// FIDELITY. ArgoCD's ApplicationSet controller renders with Go text/template
// plus sprig, under the options each appset declares (every one here uses
// `goTemplate: true` + `goTemplateOptions: ["missingkey=zero"]`). Using the same
// engine means the check agrees with the controller by construction rather than
// by approximation -- a regex for "{{" would not have caught #414 (the braces
// were legitimate; the backtick was the bug) and would false-positive on the
// raw-string passthroughs that legitimately contain literal braces.
//
// SCOPE. This validates that each appset PARSES as the controller would parse
// it. It deliberately does not execute the template against synthesised
// generator params: with `missingkey=zero` a wrong key renders empty rather than
// erroring, so execution adds cost without adding signal for this failure class.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"text/template"
)

// sprigNames are the function names ArgoCD's goTemplate makes available (sprig
// + ArgoCD's own toYaml/fromYaml/lookup). Parsing only needs a name to RESOLVE
// -- the body is never called here -- so a no-op stub per name is enough and
// keeps this tool dependency-free. Without them, a live appset using `nindent`
// would fail to parse here while rendering perfectly in the cluster: a false
// positive on a required gate, which is worse than no gate.
//
// Verified against the real tree: with these stubs all 26 appsets (21 live + 5
// disabled) parse clean, so the list covers current usage. A name missing from
// this list surfaces as a distinct "unknown function" diagnostic (see
// classify) rather than as a spurious render failure.
var sprigNames = strings.Fields(`
abbrev abbrevboth add add1 ago all any append atoi b32dec b32enc b64dec b64enc base
bcrypt buildCustomCert camelcase cat ceil clean coalesce compact concat contains date
dateInZone dateModify decryptAES deepCopy deepEqual default derivePassword dict dig dir
div duration durationRound empty encryptAES env expandenv ext fail first float64 floor
fromJson fromYaml genCA genPrivateKey genSelfSignedCert genSignedCert get getHostByName
has hasKey hasPrefix hasSuffix htmlDate htmlDateInZone indent initial initials int int64
isAbs join js kebabcase keys kindIs kindOf last list lookup lower max maxf merge
mergeOverwrite min minf mod mul mustAppend mustCompact mustDateModify mustDeepCopy
mustFirst mustFromJson mustHas mustInitial mustLast mustMerge mustPrepend mustPush
mustRegexFind mustRest mustReverse mustSlice mustToDate mustToJson mustToPrettyJson
mustToRawJson mustUniq mustWithout nindent nospace now omit osBase osClean osDir osExt
pluck plural prepend quote randAlpha randAlphaNum randAscii randBytes randInt randNumeric
regexFind regexMatch regexQuoteMeta regexReplaceAll regexSplit repeat replace rest reverse
round semver semverCompare seq set sha1sum sha256sum sha512sum shuffle slice snakecase
sortAlpha split splitList splitn squote sub substr swapcase ternary title toDate toDecimal
toJson toPrettyJson toRawJson toString toStrings toToml toYaml trim trimAll trimPrefix
trimSuffix trunc tuple typeIs typeIsLike typeOf unixEpoch unset until untilStep upper
uuidv4 values without wrap wrapWith
`)

func stubFuncs() template.FuncMap {
	m := make(template.FuncMap, len(sprigNames))
	for _, n := range sprigNames {
		m[n] = func(_ ...interface{}) interface{} { return nil }
	}
	return m
}

// checkSource parses src the way the ApplicationSet controller would. It
// returns nil when the appset would render, and a diagnostic error otherwise.
//
// The whole file is parsed rather than only spec.template. That is a strict
// SUPERSET of what the controller templates, needs no YAML dependency, and is
// safe here because the only `{{ }}` in these files live inside spec.template
// -- verified across all 26. If the file parses, spec.template parses.
func checkSource(name, src string) error {
	_, err := template.New(name).Funcs(stubFuncs()).Option("missingkey=zero").Parse(src)
	return err
}

// classify turns a parse error into actionable guidance. The two shapes below
// are the documented hazards; anything else is reported verbatim.
func classify(err error) string {
	s := err.Error()
	switch {
	case strings.Contains(s, "bad character U+0060"):
		return "a literal backtick closed the Go raw-string passthrough early (this is issue #414). " +
			"Remove the backtick from inside the {{` ... `}} block."
	case strings.Contains(s, "undefined variable"):
		return "a literal {{ }} is being evaluated as goTemplate. Wrap the block in a raw-string " +
			"passthrough ({{` ... `}}) so Prometheus/Alertmanager/Gateway templating survives (CONTRIBUTING.md:419)."
	case strings.Contains(s, "not defined"):
		return "unknown template function. If ArgoCD/sprig provides it, add the name to sprigNames in " +
			"tools/gitops/appset_render/main.go; otherwise it is a typo and would fail in the controller too."
	default:
		return "goTemplate parse failure — the ApplicationSet controller would fail to render this."
	}
}

func main() {
	root := flag.String("root", "gitops/argocd", "directory to scan for applicationset manifests")
	includeDisabled := flag.Bool("include-disabled", true, "also check *.disabled appsets (advisory: they do not reconcile)")
	flag.Parse()

	if wd := os.Getenv("BUILD_WORKSPACE_DIRECTORY"); wd != "" {
		if err := os.Chdir(wd); err != nil {
			fmt.Fprintf(os.Stderr, "appset-render: cannot enter workspace: %v\n", err)
			os.Exit(1)
		}
	}

	var files []string
	err := filepath.Walk(*root, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		base := filepath.Base(p)
		if !strings.HasPrefix(base, "applicationset") {
			return nil
		}
		if strings.HasSuffix(base, ".disabled") && !*includeDisabled {
			return nil
		}
		files = append(files, p)
		return nil
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "appset-render: cannot scan %s: %v\n", *root, err)
		os.Exit(1)
	}
	sort.Strings(files)

	// An empty scan is a coverage failure, not a pass. This repo has 21 live
	// appsets; finding zero means the path moved or the glob rotted, and a gate
	// that silently checks nothing is the assurance failure it exists to stop.
	if len(files) == 0 {
		fmt.Fprintf(os.Stderr, "appset-render: found NO applicationset manifests under %s — refusing to report green.\n", *root)
		os.Exit(1)
	}

	fail := 0
	for _, f := range files {
		src, readErr := os.ReadFile(f)
		if readErr != nil {
			fmt.Fprintf(os.Stderr, "✗ %s: %v\n", f, readErr)
			fail++
			continue
		}
		if perr := checkSource(filepath.Base(f), string(src)); perr != nil {
			// A *.disabled appset does not reconcile (ArgoCD's include glob and
			// the validator both skip it), so it is reported but not fatal.
			disabled := strings.HasSuffix(f, ".disabled")
			mark, tag := "✗", ""
			if disabled {
				mark, tag = "!", " (disabled — advisory)"
			}
			fmt.Fprintf(os.Stderr, "%s %s%s\n    %v\n    → %s\n", mark, f, tag, perr, classify(perr))
			if !disabled {
				fail++
			}
			continue
		}
	}

	if fail > 0 {
		fmt.Fprintf(os.Stderr, "\nappset-render: %d of %d ApplicationSet(s) would FAIL to render.\n", fail, len(files))
		os.Exit(1)
	}
	fmt.Printf("appset-render: %d ApplicationSet(s) render-parse clean\n", len(files))
}
