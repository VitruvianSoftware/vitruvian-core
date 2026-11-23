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

// Built against the Stripe Go SDK generated into sdks/stripe (Stripe's
// provider 0.3.0 through Pulumi's terraform-provider 1.5.0; see README.md,
// "Regenerating the Stripe SDK"): stripe.NewProduct, stripe.NewPrice with
// CustomUnitAmounts, stripe.NewPaymentLink.
//
// One Stripe account per stack. Each product line is its own function over a
// shared provider; donations is the first:
//
//	Product  "Support Vitruvian Software"
//	  └─ Price  custom_unit_amount (donor picks the amount)
//	       ├─ PaymentLink  donate-vitruvian   (submit_type=donate, metadata.app=vitruvian)
//	       ├─ PaymentLink  donate-development (the site-wide link on vitruviansoftware.dev/donate/)
//	       └─ PaymentLink  donate-<app> ...   one per entry in donations.apps
//
// Outputs: donationLinks, a map of app key -> public Payment Link URL, which
// feeds the stable redirect each app opens (README.md, "How apps show the button").
package main

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	"github.com/pulumi/pulumi-terraform-provider/sdks/go/stripe/stripe"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe/internal/account"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe/internal/checkoutworker"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe/internal/donations"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe/internal/stripekey"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "vitruvian-stripe")

		acct := account.Settings{
			Mode:     account.Mode(cfg.Require("mode")),
			Currency: cfg.Require("currency"),
		}
		if err := acct.Validate(); err != nil {
			return err
		}
		var don donations.Settings
		cfg.RequireObject("donations", &don)
		if err := don.Validate(); err != nil {
			return err
		}
		var cw checkoutworker.Settings
		cfg.RequireObject("checkoutWorker", &cw)
		if err := cw.Validate(acct.Mode); err != nil {
			return err
		}

		stripeKey := stripekey.Resolve(cfg, acct.Mode)

		// Explicit provider: the key is checked against the stack's mode
		// before Stripe sees a single request.
		provider, err := stripe.NewProvider(ctx, "stripe", &stripe.ProviderArgs{
			ApiKey: stripeKey,
		})
		if err != nil {
			return err
		}

		links, priceID, err := donationLine(ctx, provider, acct, don)
		if err != nil {
			return err
		}
		ctx.Export("donationLinks", links)

		if _, err := checkoutworker.Provision(ctx, checkoutworker.ProvisionArgs{
			Mode:         acct.Mode,
			Settings:     cw,
			Donations:    don,
			PriceID:      priceID,
			StripeAPIKey: stripeKey,
		}); err != nil {
			return err
		}
		return nil
	})
}

// donationLine creates the donations product, its pay-what-you-want price and
// one Payment Link per app, and returns app key -> link URL and the shared price ID.
func donationLine(ctx *pulumi.Context, provider pulumi.ProviderResource, acct account.Settings, s donations.Settings) (pulumi.StringMap, pulumi.IDOutput, error) {
	// Payment Links cannot be deleted in Stripe (the provider's delete only
	// deactivates them) and a replacement mints a new URL. In live mode,
	// refuse both unless someone removes the protection on purpose.
	live := acct.Mode == account.ModeLive
	opts := []pulumi.ResourceOption{pulumi.Provider(provider)}
	common := pulumi.StringMap{
		"product-line": pulumi.String("donations"),
		"managed-by":   pulumi.String("pulumi"),
		"stack":        pulumi.String(ctx.Stack()),
	}

	product, err := stripe.NewProduct(ctx, "donations", &stripe.ProductArgs{
		Name:        pulumi.String(s.ProductName),
		Description: pulumi.String("Pay what you want to support free software from Vitruvian Software."),
		Metadata:    common,
	}, append(opts, pulumi.Protect(live))...)
	if err != nil {
		return nil, pulumi.IDOutput{}, err
	}

	price, err := stripe.NewPrice(ctx, "donations-pay-what-you-want", &stripe.PriceArgs{
		Product:  product.ID(),
		Currency: pulumi.String(acct.Currency),
		CustomUnitAmounts: stripe.PriceCustomUnitAmountArray{
			stripe.PriceCustomUnitAmountArgs{
				Enabled: pulumi.Bool(true),
				Minimum: pulumi.Float64(float64(s.Amounts.Minimum)),
				Preset:  pulumi.Float64(float64(s.Amounts.Preset)),
				Maximum: pulumi.Float64(float64(s.Amounts.Maximum)),
			},
		},
		Metadata: common,
	}, opts...)
	if err != nil {
		return nil, pulumi.IDOutput{}, err
	}

	links := pulumi.StringMap{}
	for _, app := range s.Apps {
		md := pulumi.StringMap{}
		for k, v := range donations.LinkMetadata(app, ctx.Stack()) {
			md[k] = pulumi.String(v)
		}
		link, err := stripe.NewPaymentLink(ctx, "donate-"+app.Key, &stripe.PaymentLinkArgs{
			LineItems: stripe.PaymentLinkLineItemArray{
				stripe.PaymentLinkLineItemArgs{
					Price:    price.ID(),
					Quantity: pulumi.Float64(1),
				},
			},
			// Labels the button "Donate" on Stripe's hosted page.
			// Note: CustomText is intentionally omitted because the bridged
			// stripe/stripe Terraform provider omits line_items[0][id] on
			// PaymentLink updates, causing Stripe API 400 parameter_missing.
			SubmitType: pulumi.String("donate"),
			AfterCompletion: &stripe.PaymentLinkAfterCompletionArgs{
				Type: pulumi.String("hosted_confirmation"),
				HostedConfirmation: &stripe.PaymentLinkAfterCompletionHostedConfirmationArgs{
					CustomMessage: pulumi.String(s.ThankYouMessage),
				},
			},
			Metadata: md,
		}, append(opts, pulumi.Protect(live))...)
		if err != nil {
			return nil, pulumi.IDOutput{}, fmt.Errorf("payment link for %s: %w", app.Key, err)
		}
		links[app.Key] = link.Url
	}

	ctx.Export("donationsProductId", product.ID())
	ctx.Export("donationsPriceId", price.ID())
	return links, price.ID(), nil
}
