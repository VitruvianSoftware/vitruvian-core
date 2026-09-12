# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest on `main` | ✅ |
| Older releases | ❌ |

## Reporting a Vulnerability

If you discover a security vulnerability in this library, please report it responsibly:

1. **Do NOT open a public GitHub issue.**
2. Email [security@vitruviansoftware.com](mailto:security@vitruviansoftware.com) with:
   - A description of the vulnerability
   - Steps to reproduce
   - Potential impact assessment
   - Suggested fix (if any)
3. You will receive an acknowledgment within **48 hours**.
4. We will work with you on a fix and coordinate disclosure.

## Scope

This library provisions Google Cloud infrastructure. Security issues of particular concern include:

- IAM misconfigurations that could escalate privileges
- Missing or incorrect security defaults (e.g., public access where private is expected)
- Credential exposure in logs or state
- Dependency vulnerabilities in the Go module supply chain

## Security Best Practices

When using this library:

- **Never commit service account keys** to version control. Use [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) instead.
- **Use `IAMMember` (additive) over `IAMBinding` (authoritative)** unless you need strict control — authoritative bindings can remove access for other principals.
- **Review `pulumi preview` output** before running `pulumi up` to catch unintended permission changes.
- **Enable [Pulumi state encryption](https://www.pulumi.com/docs/concepts/state/#encryption)** if using a self-managed backend.
