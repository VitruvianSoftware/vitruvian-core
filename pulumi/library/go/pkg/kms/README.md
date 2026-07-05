# kms

A Pulumi component for creating Cloud KMS keyrings and crypto keys.

**Upstream Reference:** [terraform-google-modules/kms/google](https://registry.terraform.io/modules/terraform-google-modules/kms/google)

## Overview

Creates a Cloud KMS keyring with optional crypto keys, supporting configurable key purpose and rotation periods.

## API Reference

### KmsArgs

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `ProjectID` | `pulumi.StringInput` | ✅ | GCP project ID |
| `Location` | `string` | ✅ | KMS location |
| `KeyringName` | `string` | ✅ | Name of the keyring |
| `Keys` | `[]KeyConfig` | | Crypto keys to create in the keyring |

### KeyConfig

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `Name` | `string` | ✅ | Key name |
| `RotationPeriod` | `string` | | Rotation period (e.g., `7776000s` for 90 days) |
| `Purpose` | `string` | | Key purpose (default: `ENCRYPT_DECRYPT`) |

### Outputs

| Field | Type | Description |
|:--|:--|:--|
| `Keyring` | `*kms.KeyRing` | The created keyring |
| `Keys` | `map[string]*kms.CryptoKey` | Map of key name → crypto key |

## Usage

```go
kmsComponent, err := kms.NewKms(ctx, "app-kms", &kms.KmsArgs{
    ProjectID:   pulumi.String("my-project"),
    Location:    "us-central1",
    KeyringName: "app-keyring",
    Keys: []kms.KeyConfig{
        {Name: "data-encryption", RotationPeriod: "7776000s"},
        {Name: "config-encryption", Purpose: "ENCRYPT_DECRYPT"},
    },
})
```
