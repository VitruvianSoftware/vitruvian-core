# apple-signing

Sets up the Apple **Developer ID** certificate and the **notary API key** that
the Vitruvian release (`.github/workflows/delivery-vitruvian.yaml`) uses to sign
the app and have Apple approve it. With them, macOS opens the app without the
"unverified developer" warning, and the permissions a person granted survive an
update. Without them the release still works, signed ad hoc.

Everything is kept in `~/.vitruvian-signing` (only your user can open it), never
in the repository.

## Steps

1. `bazel run //tools/apple-signing -- csr` makes the private key and a
   certificate request. The key never leaves the Mac.
2. **By hand, signed in as the account holder:** developer.apple.com >
   Certificates > + > *Developer ID Application* > *G2 Sub-CA*, upload
   `~/.vitruvian-signing/developer-id.csr`, and save the certificate Apple
   gives back as `~/.vitruvian-signing/developer-id.cer`.
3. **By hand:** App Store Connect > Users and Access > Integrations > *Team
   Keys* > generate a key with the *Developer* role. Note its Key ID and the
   Issuer ID, and download the `.p8` (Apple allows that once).
4. `bazel run //tools/apple-signing -- secrets <KEY_ID> <ISSUER_ID> <path to AuthKey_*.p8>`
   - builds the `.p12` with a random password nobody sees;
   - asks Apple whether the API key works, and stops if not;
   - saves the five `VITRUVIAN_SIGNING_*` / `VITRUVIAN_NOTARY_*` repository
     secrets with your `gh` login;
   - saves three Bitwarden items (the `.p12` and its password, the API key
     and its IDs, the private key and certificate as PEM), skipping any that
     exist;
   - installs the identity in your login keychain, so this Mac can sign too.
5. `bazel run //tools/apple-signing -- check` counts the identities and the
   secrets.

## Renewing

The certificate lasts until the date Apple prints on it. To renew, move the old
`developer-id.*` files aside and run the steps again; the API key does not
expire. Override the folder, repository or secret prefix with
`APPLE_SIGNING_DIR`, `APPLE_SIGNING_REPO` and `APPLE_SIGNING_SECRET_PREFIX`.
