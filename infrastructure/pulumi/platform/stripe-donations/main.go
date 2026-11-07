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
// What it manages, in one Stripe account per stack:
//
//	Product  "Support Vitruvian Software"
//	  └─ Price  custom_unit_amount (donor picks the amount)
//	       ├─ PaymentLink  donate-vitruvian   (submit_type=donate, metadata.app=vitruvian)
//	       └─ PaymentLink  donate-<app> ...   one per entry in stripe-donations:apps
//
// Outputs: donationLinks, a map of app key -> public Payment Link URL, which
// feeds the stable redirect each app opens (README.md, "How apps show it").
package main

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	"github.com/pulumi/pulumi-terraform-provider/sdks/go/stripe/stripe"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe-donations/internal/donations"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe-donations/internal/stripekey"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "stripe-donations")

		var s donations.Settings
		s.Mode = donations.Mode(cfg.Require("mode"))
		s.Currency = cfg.Require("currency")
		s.ProductName = cfg.Require("productName")
		s.ThankYouMessage = cfg.Require("thankYouMessage")
		cfg.RequireObject("amounts", &s.Amounts)
		cfg.RequireObject("apps", &s.Apps)
		if err := s.Validate(); err != nil {
			return err
		}

		// Explicit provider: the key is checked against the stack's mode
		// before Stripe sees a single request.
		provider, err := stripe.NewProvider(ctx, "stripe", &stripe.ProviderArgs{
			ApiKey: stripekey.Resolve(cfg, s.Mode),
		})
		if err != nil {
			return err
		}
		// Payment Links cannot be deleted in Stripe (the provider's delete
		// only deactivates them) and a replacement mints a new URL. In live
		// mode, refuse both unless someone removes the protection on purpose.
		live := s.Mode == donations.ModeLive
		opts := []pulumi.ResourceOption{pulumi.Provider(provider)}

		product, err := stripe.NewProduct(ctx, "support", &stripe.ProductArgs{
			Name:        pulumi.String(s.ProductName),
			Description: pulumi.String("Pay what you want to support free software from Vitruvian Software."),
			Metadata:    pulumi.StringMap{"managed-by": pulumi.String("pulumi"), "stack": pulumi.String(ctx.Stack())},
		}, append(opts, pulumi.Protect(live))...)
		if err != nil {
			return err
		}

		price, err := stripe.NewPrice(ctx, "support-pay-what-you-want", &stripe.PriceArgs{
			Product:  product.ID(),
			Currency: pulumi.String(s.Currency),
			CustomUnitAmounts: stripe.PriceCustomUnitAmountArray{
				stripe.PriceCustomUnitAmountArgs{
					Enabled: pulumi.Bool(true),
					Minimum: pulumi.Float64(float64(s.Amounts.Minimum)),
					Preset:  pulumi.Float64(float64(s.Amounts.Preset)),
					Maximum: pulumi.Float64(float64(s.Amounts.Maximum)),
				},
			},
			Metadata: pulumi.StringMap{"managed-by": pulumi.String("pulumi"), "stack": pulumi.String(ctx.Stack())},
		}, opts...)
		if err != nil {
			return err
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
				return fmt.Errorf("payment link for %s: %w", app.Key, err)
			}
			links[app.Key] = link.Url
		}

		ctx.Export("productId", product.ID())
		ctx.Export("priceId", price.ID())
		ctx.Export("donationLinks", links)
		return nil
	})
}
