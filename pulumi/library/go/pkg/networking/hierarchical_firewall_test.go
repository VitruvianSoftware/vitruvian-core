/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package networking

import (
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
)

func TestNewHierarchicalFirewallPolicy(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		fw, err := NewHierarchicalFirewallPolicy(ctx, "test-fw", &HierarchicalFirewallPolicyArgs{
			ParentID:      pulumi.String("organizations/12345"),
			ShortName:     "test-short-name",
			Description:   "Test firewall policy",
			Associations:  []string{"folders/111", "folders/222"},
			EnableLogging: true,
		})

		assert.NoError(t, err)
		assert.NotNil(t, fw)
		assert.NotNil(t, fw.Policy)
		assert.Len(t, fw.Associations, 2)
		assert.Len(t, fw.Rules, 5)

		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	assert.NoError(t, err)
}

func TestNewHierarchicalFirewallPolicy_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewHierarchicalFirewallPolicy(ctx, "test", nil)
		assert.Error(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	assert.NoError(t, err)
}
