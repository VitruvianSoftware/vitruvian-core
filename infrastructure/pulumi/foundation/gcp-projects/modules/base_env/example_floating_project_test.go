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

package base_env

import (
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// recordingMocks captures the logical name of every resource the program
// registers, so a test can assert WHICH projects a toggle combination creates.
type recordingMocks struct {
	mu    *sync.Mutex
	names *[]string
}

func (m recordingMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	*m.names = append(*m.names, args.Name)
	m.mu.Unlock()
	return args.Name + "_id", args.Inputs, nil
}

func (recordingMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// runFloating runs deployFloatingProject under mocks with the two floating
// toggles set as given, returning every resource name it registered.
func runFloating(t *testing.T, floating, ossFloating bool) []string {
	t.Helper()
	var (
		mu    sync.Mutex
		names []string
	)
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := &Args{
			ProjectPrefix:  "prj",
			EnvCode:        "d",
			BusinessCode:   "bu2",
			BillingAccount: "AAAAAA-BBBBBB-CCCCCC",
			RandomSuffix:   true,
			FolderID:       pulumi.String("folders/1234567890").ToStringOutput(),

			FloatingProjectEnabled:    floating,
			OSSFloatingProjectEnabled: ossFloating,

			Labels: func(suffix, vpc string) pulumi.StringMap {
				return pulumi.StringMap{"application_name": pulumi.String(suffix), "vpc": pulumi.String(vpc)}
			},
		}
		return deployFloatingProject(ctx, args, &BUProjects{})
	}, pulumi.WithMocks("project", "stack", recordingMocks{mu: &mu, names: &names}))
	require.NoError(t, err)

	mu.Lock()
	defer mu.Unlock()
	out := make([]string, len(names))
	copy(out, names)
	return out
}

func contains(names []string, want string) bool {
	for _, n := range names {
		if n == want {
			return true
		}
	}
	return false
}

// The sample-floating and OSS-floating projects are documented as SEPARATELY
// toggle-gated, and business units differ in which they want: bu1 has both,
// while bu2 (tabula) wants only the OSS project and no -sample-floating.
// Regression guard for the two gates being genuinely independent — an early
// `if !FloatingProjectEnabled { return nil }` silently made the OSS project
// unreachable, which a preview caught only because bu2 is the first caller to
// separate them.
func TestFloatingToggles_AreIndependent(t *testing.T) {
	t.Run("oss only: creates the OSS project and no sample-floating", func(t *testing.T) {
		names := runFloating(t, false, true)
		assert.True(t, contains(names, "bu-oss-floating-project"),
			"OSS floating project must be created when its own toggle is on, regardless of FloatingProjectEnabled; got %v", names)
		assert.False(t, contains(names, "bu-floating-project"),
			"sample-floating must NOT be created when its toggle is off; got %v", names)
	})

	t.Run("sample only: creates the sample project and no OSS project", func(t *testing.T) {
		names := runFloating(t, true, false)
		assert.True(t, contains(names, "bu-floating-project"), "got %v", names)
		assert.False(t, contains(names, "bu-oss-floating-project"), "got %v", names)
	})

	t.Run("both on: creates both (bu1's live configuration)", func(t *testing.T) {
		names := runFloating(t, true, true)
		assert.True(t, contains(names, "bu-floating-project"), "got %v", names)
		assert.True(t, contains(names, "bu-oss-floating-project"), "got %v", names)
	})

	t.Run("both off: creates neither", func(t *testing.T) {
		names := runFloating(t, false, false)
		assert.False(t, contains(names, "bu-floating-project"), "got %v", names)
		assert.False(t, contains(names, "bu-oss-floating-project"), "got %v", names)
	})
}
