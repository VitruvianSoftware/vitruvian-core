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
	"fmt"
	"strconv"
)

// requiredStackKeys must be present in the stack config (Pulumi.<stack>.yaml)
// for this program to run at all.
//
// Every component toggle here reads with GetBool(key, false), so a MISSING
// config file is indistinguishable from "turn everything off" — and the
// program then deletes whatever it still manages. That happened on
// 2026-09-23: `pulumi up` from a git worktree (Pulumi.local.yaml is
// gitignored, so worktrees don't have it) read argocd_enabled as false and
// uninstalled Argo CD, taking the argocd namespace and every Application with
// it.
//
// argocd_enabled is the sentinel because Argo CD is the component this stack
// still owns; everything else moved to GitOps. Requiring it to be written
// down — true OR false — means an absent file stops the run before any
// resource is touched, while turning Argo CD off on purpose still works.
var requiredStackKeys = []string{"argocd_enabled"}

// configLookup is the slice of utils.PulumiConfig the guard needs, so it can
// be tested without a Pulumi engine.
type configLookup interface {
	Lookup(key string) (string, bool)
}

// requireStackConfig fails if any required key is absent or is not a valid
// boolean.
func requireStackConfig(conf configLookup) error {
	for _, key := range requiredStackKeys {
		raw, ok := conf.Lookup(key)
		if !ok {
			return fmt.Errorf("stack config key %q is not set. This usually means Pulumi.<stack>.yaml is "+
				"missing (it is gitignored, so git worktrees do not have it). Without it every component "+
				"reads as disabled and `pulumi up` would DELETE them. Copy Pulumi.local.yaml from the main "+
				"checkout, or set the key explicitly (true or false), then re-run", key)
		}
		if _, err := strconv.ParseBool(raw); err != nil {
			return fmt.Errorf("stack config key %q must be true or false, got %q", key, raw)
		}
	}
	return nil
}
