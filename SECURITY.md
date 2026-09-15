# Security Policy

## Supported Versions

Only the active `main` branch receives ongoing security patches and vulnerability updates.

| Version | Supported          |
| ------- | ------------------ |
| `main`  | :white_check_mark: |

## Reporting a Vulnerability

If you discover a potential security vulnerability within `vitruvian-core` or any associated package, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, report vulnerabilities directly via email to:

**opensource@vitruviansoftware.com**

Please include in your report:

1. **Description**: Clear description of the vulnerability and its potential impact.
2. **Reproduction Steps**: Step-by-step instructions, proof-of-concept script, or command line sequence.
3. **Affected Components**: Specific application, package, infrastructure module, or workflow involved.
4. **Proposed Fix**: Remediation suggestion or patch (if available).

### Response Timeline

- **Acknowledgment**: Within **48 hours** of receiving your report.
- **Triage & Remediation Plan**: Within **7 days**, detailing confirmation of severity and expected remediation schedule.
- **Disclosure**: Coordinated public release once a fix has landed and been verified.

## Monorepo Security Considerations

`vitruvian-core` enforces security invariants designed to protect credentials, infrastructure, and deployed artifacts:

- **Zero Git Secrets**: API keys, service account credentials, private SSH keys, and cloud tokens must never be committed to git. Sensitive values are synchronized via external secret vaults (`tools/sync-env-secrets`) or injected dynamically in CI through GitHub OIDC and Workload Identity Federation (WIF).
- **Hermetic Toolchains**: Builds and tests are executed through Bazel hermetic toolchains to prevent supply chain tampering and environment bleed.
- **Infrastructure Isolation**: Cloud infrastructure defined in `infrastructure/pulumi` requires pinned GCP identities (`infrastructure/gcp-identities.tsv`) and authenticated execution wrappers (`bazel run //infrastructure/pulumi/...`).
- **Bot Identity Attribution**: Automated bot agents authenticate strictly with scoped GitHub App credentials (`tools/agent-app`), keeping automated changes auditable and preventing privilege escalation.
