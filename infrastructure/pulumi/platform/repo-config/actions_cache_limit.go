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
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

const (
	actionsCacheSizeLimitGBConfigKey = "actionsCacheSizeLimitGB"
	defaultActionsCacheSizeLimitGB   = 15
)

// actionsCacheLimitScript sets the repository's GitHub Actions cache storage
// limit via PUT /repos/{owner}/{repo}/actions/cache/storage-limit with
// {"max_cache_size_gb": ...} and polls GET until GitHub reports the configured
// limit. pulumi-github v6.15.1 has no resource for this endpoint. Deleting the
// Pulumi resource leaves the live limit untouched.
const actionsCacheLimitScript = `set -eu
token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
[ -n "$token" ] || { echo "GITHUB_TOKEN or GH_TOKEN must be set" >&2; exit 1; }
printf '%s' "$ACTIONS_CACHE_STORAGE_LIMIT_BODY" | GH_TOKEN="$token" gh api --method PUT \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$ACTIONS_CACHE_STORAGE_LIMIT_PATH" \
  --input -
attempt=0
got=""
while [ "$attempt" -lt 12 ]; do
  got="$(GH_TOKEN="$token" gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$ACTIONS_CACHE_STORAGE_LIMIT_PATH" \
    --jq .max_cache_size_gb || true)"
  if [ "$got" = "$ACTIONS_CACHE_SIZE_LIMIT_GB" ]; then
    echo "GitHub Actions cache size limit confirmed: ${got} GB"
    exit 0
  fi
  attempt=$((attempt + 1))
  if [ "$attempt" -lt 12 ]; then
    sleep 5
  fi
done
echo "GitHub Actions cache size limit is '${got}', want '${ACTIONS_CACHE_SIZE_LIMIT_GB}'" >&2
exit 1
`

type actionsCacheStorageLimitPayload struct {
	MaxCacheSizeGB int `json:"max_cache_size_gb"`
}

func validateActionsCacheSizeLimitGB(limitGB int) error {
	if limitGB < 1 {
		return fmt.Errorf("config %q = %d must be at least 1 GB", actionsCacheSizeLimitGBConfigKey, limitGB)
	}
	return nil
}

func actionsCacheSizeLimitGB(cfg *config.Config) (int, error) {
	limitGB, err := intConfig(cfg, actionsCacheSizeLimitGBConfigKey, defaultActionsCacheSizeLimitGB)
	if err != nil {
		return 0, err
	}
	if err := validateActionsCacheSizeLimitGB(limitGB); err != nil {
		return 0, err
	}
	return limitGB, nil
}

func actionsCacheStorageLimitPath(owner, repo string) string {
	return fmt.Sprintf("repos/%s/%s/actions/cache/storage-limit", owner, repo)
}

func actionsCacheStorageLimitBody(limitGB int) (string, error) {
	if err := validateActionsCacheSizeLimitGB(limitGB); err != nil {
		return "", err
	}
	b, err := json.Marshal(actionsCacheStorageLimitPayload{MaxCacheSizeGB: limitGB})
	if err != nil {
		return "", fmt.Errorf("marshaling actions cache storage limit: %w", err)
	}
	return string(b), nil
}

// manageActionsCacheLimit reconciles the repository's Actions cache size limit
// through a local.Command because pulumi-github v6.15.1 has no resource for it.
func manageActionsCacheLimit(ctx *pulumi.Context, cfg *config.Config, repoOwner, repoName string, repo *github.Repository) (int, error) {
	limitGB, err := actionsCacheSizeLimitGB(cfg)
	if err != nil {
		return 0, err
	}
	path := actionsCacheStorageLimitPath(repoOwner, repoName)
	body, err := actionsCacheStorageLimitBody(limitGB)
	if err != nil {
		return 0, err
	}
	if _, err := local.NewCommand(ctx, repoName+"-actions-cache-limit", &local.CommandArgs{
		Create:      pulumi.String(actionsCacheLimitScript),
		Update:      pulumi.String(actionsCacheLimitScript),
		Interpreter: pulumi.StringArray{pulumi.String("/bin/sh"), pulumi.String("-c")},
		Environment: pulumi.StringMap{
			"ACTIONS_CACHE_STORAGE_LIMIT_PATH": pulumi.String(path),
			"ACTIONS_CACHE_STORAGE_LIMIT_BODY": pulumi.String(body),
			"ACTIONS_CACHE_SIZE_LIMIT_GB":      pulumi.String(strconv.Itoa(limitGB)),
		},
		Triggers: pulumi.Array{pulumi.String(path), pulumi.String(body)},
	}, pulumi.DependsOn([]pulumi.Resource{repo})); err != nil {
		return 0, fmt.Errorf("managing actions cache size limit: %w", err)
	}
	return limitGB, nil
}
