# Security Policy

## Supported Versions

We release patches for security vulnerabilities for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

We take the security of Tabula seriously. If you believe you have found a security vulnerability,
please report it to us as described below.

### How to Report

Please email security concerns to: **security@tabula.app** (or use GitHub Security Advisories)

Include the following information:

- Type of vulnerability
- Full paths of source file(s) related to the issue
- Location of the affected source code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit it

### What to Expect

- **Acknowledgment:** We will acknowledge receipt of your vulnerability report within 48 hours
- **Updates:** We will keep you informed about progress toward a fix and announcement
- **Timeline:** We aim to resolve critical issues within 7 days
- **Credit:** We will credit you in the security advisory (unless you prefer to remain anonymous)

### Security Response Process

1. **Triage:** Verify and assess severity
2. **Fix Development:** Create patch in private fork
3. **Testing:** Ensure fix works and doesn't break functionality
4. **Release:** Deploy fix to production
5. **Disclosure:** Publish security advisory
6. **Recognition:** Credit reporter (if desired)

## Security Best Practices

### For Users

1. **Keep Extensions Updated:** Always use the latest version from Chrome Web Store
2. **Strong Passwords:** Use unique, strong passwords (min 12 characters)
3. **Two-Factor Authentication:** Enable 2FA when available (Phase 2+)
4. **Review Permissions:** Understand extension permissions before installing
5. **Secure Devices:** Keep your operating system and browser up to date

### For Developers

1. **Dependency Updates:** Regularly update dependencies
2. **Code Review:** All code must be reviewed before merging
3. **Input Validation:** Validate all user inputs
4. **Secrets Management:** Never commit secrets to git
5. **HTTPS Only:** All API communication over HTTPS
6. **SQL Injection Prevention:** Use parameterized queries (Prisma)
7. **XSS Prevention:** Sanitize user content before rendering
8. **CSRF Protection:** Implement CSRF tokens for state-changing operations
9. **Rate Limiting:** Enforce rate limits on all API endpoints
10. **Secure Headers:** Use security headers (CSP, HSTS, etc.)

## Vulnerability Disclosure Policy

- **Private Disclosure Period:** 90 days
- **Coordinated Public Disclosure:** After fix is deployed
- **CVE Assignment:** For high/critical vulnerabilities
- **Hall of Fame:** Security researchers credited on our website

## Security Features

### Authentication & Authorization

- **Password Hashing:** bcrypt with cost factor 12
- **JWT Tokens:** RS256 signing algorithm
- **Token Expiration:** Access tokens expire after 15 minutes
- **Refresh Token Rotation:** Prevents token replay attacks
- **Session Management:** Secure session handling with Redis

### Data Protection

- **Encryption in Transit:** TLS 1.3 for all API communication
- **Encryption at Rest:** Database encryption via Neon
- **Secrets Management:** Google Secret Manager for production
- **API Keys:** Secure storage, rotation policy
- **PII Handling:** Minimal collection, secure storage

### Network Security

- **CORS:** Strict CORS policy with allowlist
- **Rate Limiting:** 100 requests/minute per user
- **Input Validation:** Zod schema validation
- **SQL Injection Prevention:** Prisma parameterized queries
- **XSS Prevention:** Content Security Policy
- **CSRF Protection:** Token-based protection

### Infrastructure Security

- **Cloud Run:** Managed security patches
- **VPC:** Private network for database connections
- **Service Accounts:** Least privilege principle
- **Audit Logging:** All API requests logged
- **Monitoring:** Real-time security monitoring
- **Backup:** Regular automated backups

## Threat Model

See [docs/architecture/threat-model.md](./docs/architecture/threat-model.md) for detailed threat
analysis.

### High-Level Threats

1. **Account Takeover:** Mitigated by strong auth, 2FA, rate limiting
2. **Data Breach:** Mitigated by encryption, access controls, monitoring
3. **XSS Attacks:** Mitigated by CSP, input sanitization
4. **API Abuse:** Mitigated by rate limiting, authentication
5. **Dependency Vulnerabilities:** Mitigated by automated scanning, updates

## Compliance

- **GDPR:** User data rights, data portability, deletion
- **CCPA:** California privacy rights
- **SOC 2:** Using SOC 2 compliant providers (Neon, WorkOS)

## Security Updates

Security updates are released as soon as possible after vulnerability discovery:

- **Critical:** Within 7 days
- **High:** Within 14 days
- **Medium:** Within 30 days
- **Low:** Next regular release

## Bug Bounty Program

We currently do not have a paid bug bounty program, but we:

- Acknowledge security researchers
- Provide public credit (if desired)
- May offer rewards for exceptional findings

## Security Contacts

- **Email:** security@tabula.app
- **GitHub:** [Security Advisories](https://github.com/VitruvianSoftware/vitruvian-core/security/advisories)

## Additional Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Chrome Extension Security](https://developer.chrome.com/docs/extensions/mv3/security/)
- [Node.js Security Best Practices](https://nodejs.org/en/docs/guides/security/)

---

**Last Updated:** 2025-12-07  
**Version:** 1.0
