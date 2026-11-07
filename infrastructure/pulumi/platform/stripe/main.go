//go:build ignore

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

// SCAFFOLD: this file is excluded from builds (the go:build line at the top) until the Stripe
// Go SDK is generated into sdks/stripe and committed. It is written against the
// types the Pulumi registry documents for the `stripe` package (Stripe's
// provider 0.3.0): stripe.NewProduct, stripe.NewPrice with CustomUnitAmounts,
// stripe.NewPaymentLink. Generating the SDK is the first step of the follow-up
// (README.md, "Generating the Stripe SDK"); delete the build line in the same
// commit so CI compiles it from then on.
//
// One Stripe account per stack. Each product line is its own function over a
// shared provider; donations is the first:
//
//	Product  "Support Vitruvian Software"
//	  └─ Price  custom_unit_amount (donor picks the amount)
//	       ├─ PaymentLink  donate-vitruvian   (submit_type=donate, metadata.app=vitruvian)
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

		// Explicit provider: the key is checked against the stack's mode
		// before Stripe sees a single request.
		provider, err := stripe.NewProvider(ctx, "stripe", &stripe.ProviderArgs{
			ApiKey: stripekey.Resolve(cfg, acct.Mode),
		})
		if err != nil {
			return err
		}

		links, err := donationLine(ctx, provider, acct, don)
		if err != nil {
			return err
		}
		ctx.Export("donationLinks", links)
		return nil
	})
}

// donationLine creates the donations product, its pay-what-you-want price and
// one Payment Link per app, and returns app key -> link URL.
func donationLine(ctx *pulumi.Context, provider pulumi.ProviderResource, acct account.Settings, s donations.Settings) (pulumi.StringMap, error) {
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
		return nil, err
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
		return nil, err
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
			return nil, fmt.Errorf("payment link for %s: %w", app.Key, err)
		}
		links[app.Key] = link.Url
	}

	ctx.Export("donationsProductId", product.ID())
	ctx.Export("donationsPriceId", price.ID())
	return links, nil
}
