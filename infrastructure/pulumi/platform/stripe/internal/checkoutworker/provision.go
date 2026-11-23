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

package checkoutworker

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/pulumi/pulumi-cloudflare/sdk/v5/go/cloudflare"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe/internal/account"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe/internal/donations"
)

const (
	// TokenEnv names the Cloudflare API token environment variable.
	TokenEnv = "CLOUDFLARE_API_TOKEN"
	// AccountIDEnv names the Cloudflare account identifier environment variable.
	AccountIDEnv = "CLOUDFLARE_ACCOUNT_ID"
	// CompatibilityDate pins the Cloudflare Workers runtime behavior.
	CompatibilityDate = "2026-10-01"
)

// ProvisionArgs holds the inputs needed to provision the Turnstile widget,
// checkout Worker script, and Workers custom domain.
type ProvisionArgs struct {
	Mode         account.Mode
	Settings     Settings
	Donations    donations.Settings
	PriceID      pulumi.IDOutput
	StripeAPIKey pulumi.StringOutput
}

// Outputs exposes the public endpoint and Turnstile sitekey exported by the stack.
type Outputs struct {
	CheckoutURL      pulumi.StringOutput
	TurnstileSitekey pulumi.IDOutput
}

// Provision creates the Turnstile widget, checkout Worker, and Workers Custom
// Domain when both Cloudflare environment variables are set, staying dormant
// when both are unset.
func Provision(ctx *pulumi.Context, args ProvisionArgs) (*Outputs, error) {
	token := strings.TrimSpace(os.Getenv(TokenEnv))
	accountID := strings.TrimSpace(os.Getenv(AccountIDEnv))

	if token == "" && accountID == "" {
		_ = ctx.Log.Info("checkoutworker: CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID unset; skipping Cloudflare Worker and Turnstile provisioning", nil)
		return nil, nil
	}
	if token == "" {
		return nil, fmt.Errorf("%s is set but %s is empty", AccountIDEnv, TokenEnv)
	}
	if accountID == "" {
		return nil, fmt.Errorf("%s is set but %s is empty", TokenEnv, AccountIDEnv)
	}

	if err := args.Settings.Validate(args.Mode); err != nil {
		return nil, err
	}

	appKeys := make([]string, 0, len(args.Donations.Apps))
	for _, app := range args.Donations.Apps {
		appKeys = append(appKeys, app.Key)
	}
	allowedAppsBytes, err := json.Marshal(appKeys)
	if err != nil {
		return nil, fmt.Errorf("marshal allowed apps: %w", err)
	}
	turnstileHostnames := strings.Join(args.Settings.TurnstileDomains, ",")

	live := args.Mode == account.ModeLive

	cfProvider, err := cloudflare.NewProvider(ctx, "cloudflare", &cloudflare.ProviderArgs{
		ApiToken: pulumi.ToSecret(pulumi.String(token)).(pulumi.StringOutput),
	})
	if err != nil {
		return nil, fmt.Errorf("cloudflare provider: %w", err)
	}

	widget, err := cloudflare.NewTurnstileWidget(ctx, "donate-turnstile", &cloudflare.TurnstileWidgetArgs{
		AccountId: pulumi.String(accountID),
		Name:      pulumi.String(args.Settings.TurnstileWidgetName),
		Domains:   pulumi.ToStringArray(args.Settings.TurnstileDomains),
		Mode:      pulumi.String("managed"),
		Region:    pulumi.String("world"),
	}, pulumi.Provider(cfProvider), pulumi.Protect(live))
	if err != nil {
		return nil, fmt.Errorf("turnstile widget: %w", err)
	}

	script, err := cloudflare.NewWorkersScript(ctx, "donate-checkout-worker", &cloudflare.WorkersScriptArgs{
		AccountId:         pulumi.String(accountID),
		Name:              pulumi.String(args.Settings.WorkerName),
		Content:           pulumi.String(WorkerScript),
		Module:            pulumi.Bool(true),
		CompatibilityDate: pulumi.String(CompatibilityDate),
		PlainTextBindings: cloudflare.WorkersScriptPlainTextBindingArray{
			&cloudflare.WorkersScriptPlainTextBindingArgs{
				Name: pulumi.String("DONATIONS_PRICE_ID"),
				Text: args.PriceID.ToStringOutput(),
			},
			&cloudflare.WorkersScriptPlainTextBindingArgs{
				Name: pulumi.String("ALLOWED_APPS_JSON"),
				Text: pulumi.String(string(allowedAppsBytes)),
			},
			&cloudflare.WorkersScriptPlainTextBindingArgs{
				Name: pulumi.String("SUBMIT_MESSAGE"),
				Text: pulumi.String(args.Donations.SubmitText()),
			},
			&cloudflare.WorkersScriptPlainTextBindingArgs{
				Name: pulumi.String("ALLOWED_ORIGIN"),
				Text: pulumi.String(args.Settings.AllowedOrigin),
			},
			&cloudflare.WorkersScriptPlainTextBindingArgs{
				Name: pulumi.String("TURNSTILE_HOSTNAMES"),
				Text: pulumi.String(turnstileHostnames),
			},
			&cloudflare.WorkersScriptPlainTextBindingArgs{
				Name: pulumi.String("SITE_BASE_URL"),
				Text: pulumi.String(args.Settings.SiteBaseURL),
			},
		},
		SecretTextBindings: cloudflare.WorkersScriptSecretTextBindingArray{
			&cloudflare.WorkersScriptSecretTextBindingArgs{
				Name: pulumi.String("STRIPE_API_KEY"),
				Text: args.StripeAPIKey,
			},
			&cloudflare.WorkersScriptSecretTextBindingArgs{
				Name: pulumi.String("TURNSTILE_SECRET"),
				Text: widget.Secret,
			},
		},
	}, pulumi.Provider(cfProvider))
	if err != nil {
		return nil, fmt.Errorf("workers script: %w", err)
	}

	_, err = cloudflare.NewWorkersDomain(ctx, "donate-checkout-domain", &cloudflare.WorkersDomainArgs{
		AccountId:   pulumi.String(accountID),
		ZoneId:      pulumi.String(args.Settings.CloudflareZoneID),
		Hostname:    pulumi.String(args.Settings.CustomDomain),
		Service:     script.Name,
		Environment: pulumi.String("production"),
	}, pulumi.Provider(cfProvider), pulumi.Protect(live))
	if err != nil {
		return nil, fmt.Errorf("workers domain: %w", err)
	}

	checkoutURL := pulumi.String(args.Settings.CheckoutURL()).ToStringOutput()
	ctx.Export("donateCheckoutUrl", checkoutURL)
	ctx.Export("donateTurnstileSitekey", widget.ID())

	return &Outputs{
		CheckoutURL:      checkoutURL,
		TurnstileSitekey: widget.ID(),
	}, nil
}
