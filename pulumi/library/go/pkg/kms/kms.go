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

// Package kms provides a reusable KMS keyring and crypto key component.
// Mirrors: terraform-google-modules/kms/google
package kms

import (
	"fmt"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/kms"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type KmsArgs struct {
	ProjectID      pulumi.StringInput
	Location       string
	KeyringName    string
	Keys           []KeyConfig
	PreventDestroy bool
}

type KeyConfig struct {
	Name            string
	RotationPeriod  string // e.g. "7776000s" (90 days)
	Algorithm       string // e.g. "GOOGLE_SYMMETRIC_ENCRYPTION"
	Purpose         string // e.g. "ENCRYPT_DECRYPT"
	ProtectionLevel string // "SOFTWARE" or "HSM"
}

type Kms struct {
	pulumi.ResourceState
	Keyring *kms.KeyRing
	Keys    map[string]*kms.CryptoKey
}

func NewKms(ctx *pulumi.Context, name string, args *KmsArgs, opts ...pulumi.ResourceOption) (*Kms, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}
	component := &Kms{Keys: make(map[string]*kms.CryptoKey)}
	err := ctx.RegisterComponentResource("pkg:index:Kms", name, component, opts...)
	if err != nil {
		return nil, err
	}

	keyring, err := kms.NewKeyRing(ctx, name+"-keyring", &kms.KeyRingArgs{
		Project:  args.ProjectID,
		Name:     pulumi.String(args.KeyringName),
		Location: pulumi.String(args.Location),
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Keyring = keyring

	for _, kc := range args.Keys {
		purpose := kc.Purpose
		if purpose == "" {
			purpose = "ENCRYPT_DECRYPT"
		}
		rotation := kc.RotationPeriod
		if rotation == "" {
			rotation = "7776000s"
		}

		keyArgs := &kms.CryptoKeyArgs{
			Name:           pulumi.String(kc.Name),
			KeyRing:        keyring.ID(),
			Purpose:        pulumi.String(purpose),
			RotationPeriod: pulumi.String(rotation),
		}

		key, err := kms.NewCryptoKey(ctx, fmt.Sprintf("%s-key-%s", name, kc.Name), keyArgs, pulumi.Parent(keyring))
		if err != nil {
			return nil, err
		}
		component.Keys[kc.Name] = key
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{"keyringId": keyring.ID()})
	return component, nil
}
