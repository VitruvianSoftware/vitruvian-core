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

package teams

import (
	"fmt"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/sentry/internal/config"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	sentry "github.com/pulumiverse/pulumi-sentry/sdk/go/sentry"
)

func Reconcile(ctx *pulumi.Context, org string, teamCfg *config.TeamConfig, opts ...pulumi.ResourceOption) (*sentry.SentryTeam, error) {
	name := fmt.Sprintf("team-%s", teamCfg.Slug)
	team, err := sentry.NewSentryTeam(ctx, name, &sentry.SentryTeamArgs{
		Organization: pulumi.String(org),
		Name:         pulumi.String(teamCfg.Name),
		Slug:         pulumi.String(teamCfg.Slug),
	}, opts...)
	if err != nil {
		return nil, fmt.Errorf("creating sentry team %s: %w", teamCfg.Slug, err)
	}

	return team, nil
}
