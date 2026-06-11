# Threat Model

This document outlines the security threat model for Tabula, including potential threats, attack
vectors, and mitigation strategies.

## Overview

Tabula handles sensitive user data including:

- Authentication credentials
- Browsing history (tab URLs and titles)
- Personal workspace organization
- Session tokens

This threat model uses the **STRIDE** framework to categorize threats:

- **S**poofing
- **T**ampering
- **R**epudiation
- **I**nformation Disclosure
- **D**enial of Service
- **E**levation of Privilege

## System Components

1. **Browser Extension** (Client)
2. **Backend API** (Cloud Run)
3. **Database** (Neon PostgreSQL)
4. **Cache** (Upstash Redis)
5. **Storage** (Google Cloud Storage)
6. **Authentication** (JWT + WorkOS future)

## Trust Boundaries

```
┌─────────────────────────────────────────────────┐
│ User's Browser (Trusted - User Domain)         │
│  ┌─────────────────────────────────────────┐   │
│  │ Browser Extension                       │   │
│  │ - Local Storage                         │   │
│  │ - Chrome Extension APIs                 │   │
│  └─────────────────────────────────────────┘   │
└──────────────────┬──────────────────────────────┘
                   │ HTTPS/TLS
                   ▼
┌─────────────────────────────────────────────────┐
│ Cloud Infrastructure (Partially Trusted)        │
│  ┌─────────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Cloud Run   │  │ Neon DB  │  │ Redis     │  │
│  │ API         │  │          │  │ Cache     │  │
│  └─────────────┘  └──────────┘  └───────────┘  │
└─────────────────────────────────────────────────┘
```

## Threat Analysis (STRIDE)

### 1. Spoofing Identity

#### Threat: Attacker Impersonates User

**Attack Vectors:**

- Stolen JWT tokens
- Session hijacking
- Credential phishing
- Token replay attacks

**Impact:** HIGH - Attacker gains full access to user's workspaces and data

**Likelihood:** MEDIUM

**Mitigations:**

- ✅ JWT with short expiration (15 minutes)
- ✅ Refresh token rotation
- ✅ HTTPS-only communication
- ✅ Secure token storage (httpOnly cookies or secure storage)
- ✅ Rate limiting on auth endpoints
- 🔄 Multi-factor authentication (Phase 2+)
- 🔄 Device fingerprinting
- 🔄 Anomaly detection

**Detection:**

- Monitor for impossible travel (login from different locations)
- Track session creation patterns
- Alert on multiple concurrent sessions

#### Threat: Malicious Extension Impersonates Tabula

**Attack Vectors:**

- Extension ID spoofing
- Similar-looking extension in store
- Man-in-the-middle during installation

**Impact:** HIGH - User installs malicious extension

**Likelihood:** LOW

**Mitigations:**

- ✅ Signed extension from Chrome Web Store
- ✅ Extension ID verification in API
- ✅ Clear branding and verification
- 📝 User education about official extension

**Detection:**

- Monitor for reports of fake extensions
- Track download sources

### 2. Tampering with Data

#### Threat: Modification of User Data

**Attack Vectors:**

- SQL injection
- API parameter tampering
- Direct database access
- Man-in-the-middle attacks

**Impact:** HIGH - Data corruption or unauthorized changes

**Likelihood:** LOW (with mitigations)

**Mitigations:**

- ✅ Parameterized queries (Prisma ORM)
- ✅ Input validation (Zod schemas)
- ✅ Authorization checks on all mutations
- ✅ TLS for data in transit
- ✅ Database encryption at rest
- ✅ Database backups for recovery
- ✅ Audit logging

**Detection:**

- Monitor for unusual update patterns
- Log all data modifications
- Integrity checks on critical data

#### Threat: Code Tampering

**Attack Vectors:**

- Compromised npm packages
- Malicious dependencies
- Build pipeline compromise

**Impact:** CRITICAL - Backdoor in application

**Likelihood:** LOW

**Mitigations:**

- ✅ Dependency scanning (npm audit, Snyk)
- ✅ Lock files (package-lock.json)
- ✅ Code review for all changes
- ✅ Signed commits
- ✅ CI/CD pipeline security
- 🔄 Supply chain security scanning
- 🔄 Regular dependency updates

**Detection:**

- Automated vulnerability scanning
- Monitor for suspicious code changes
- Regular security audits

### 3. Repudiation

#### Threat: User Denies Action

**Attack Vectors:**

- Lack of audit trail
- Shared accounts
- Compromised sessions

**Impact:** MEDIUM - Cannot prove user actions

**Likelihood:** MEDIUM

**Mitigations:**

- ✅ Audit logging for all actions
- ✅ Immutable logs
- ✅ Timestamp all operations
- ✅ Session tracking
- 🔄 IP address logging
- 🔄 Device information capture

**Detection:**

- Review logs for discrepancies
- Correlation of user actions

### 4. Information Disclosure

#### Threat: Unauthorized Access to User Data

**Attack Vectors:**

- API authorization bypass
- Database leak
- Insecure data storage
- XSS attacks
- Server-side request forgery (SSRF)

**Impact:** CRITICAL - Privacy violation, GDPR breach

**Likelihood:** MEDIUM

**Mitigations:**

- ✅ Authorization on all API endpoints
- ✅ Principle of least privilege
- ✅ Encryption at rest and in transit
- ✅ Content Security Policy (CSP)
- ✅ Input sanitization
- ✅ No sensitive data in logs
- ✅ Database access controls
- ✅ Secrets in environment variables
- 🔄 Data loss prevention (DLP)
- 🔄 Regular penetration testing

**Detection:**

- Monitor for unusual data access patterns
- Alert on bulk data exports
- Track API access anomalies

#### Threat: Information Leakage via Errors

**Attack Vectors:**

- Verbose error messages
- Stack traces in production
- Debug endpoints enabled

**Impact:** MEDIUM - Reveals system information

**Likelihood:** MEDIUM

**Mitigations:**

- ✅ Generic error messages in production
- ✅ Detailed errors only in logs
- ✅ No stack traces to client
- ✅ Disable debug mode in production

**Detection:**

- Monitor error rates
- Review error message content

### 5. Denial of Service (DoS)

#### Threat: Service Unavailability

**Attack Vectors:**

- API flooding
- Resource exhaustion
- Database connection exhaustion
- Expensive queries

**Impact:** HIGH - Service downtime

**Likelihood:** MEDIUM

**Mitigations:**

- ✅ Rate limiting (100 req/min per user)
- ✅ Request size limits
- ✅ Query timeout limits
- ✅ Database connection pooling
- ✅ Auto-scaling (Cloud Run)
- ✅ CDN for static assets
- 🔄 DDoS protection (Cloudflare)
- 🔄 Circuit breakers
- 🔄 Graceful degradation

**Detection:**

- Monitor request rates
- Alert on sudden traffic spikes
- Track resource usage

#### Threat: Account Enumeration

**Attack Vectors:**

- Brute force login attempts
- Email enumeration
- Password reset abuse

**Impact:** MEDIUM - User privacy, account takeover prep

**Likelihood:** HIGH

**Mitigations:**

- ✅ Rate limiting on auth endpoints
- ✅ Generic error messages ("Invalid credentials")
- ✅ CAPTCHA on repeated failures
- ✅ Account lockout after failures
- 🔄 Behavioral analysis

**Detection:**

- Monitor failed login attempts
- Track enumeration patterns
- Alert on brute force attempts

### 6. Elevation of Privilege

#### Threat: Unauthorized Access Escalation

**Attack Vectors:**

- Authorization bypass
- Role manipulation
- JWT token forgery
- Insecure direct object references (IDOR)

**Impact:** CRITICAL - Access to other users' data

**Likelihood:** LOW (with mitigations)

**Mitigations:**

- ✅ Role-based access control (RBAC)
- ✅ Authorization checks on all endpoints
- ✅ User ownership validation
- ✅ JWT signature verification
- ✅ No user-controlled role assignment
- ✅ Principle of least privilege

**Detection:**

- Monitor for authorization failures
- Alert on privilege escalation attempts
- Audit role changes

## Attack Surface Analysis

### Browser Extension

**Attack Surface:**

- Content scripts injected into web pages
- Message passing between components
- Local storage access
- Chrome Extension APIs

**Key Risks:**

1. XSS in popup UI
2. Malicious website interactions
3. Local storage theft
4. Extension permissions abuse

**Mitigations:**

- Content Security Policy
- Input sanitization
- Minimal permissions
- Secure message validation

### API Endpoints

**Attack Surface:**

- Public HTTP endpoints
- Authentication endpoints
- Data manipulation endpoints
- File upload endpoints (future)

**Key Risks:**

1. Injection attacks
2. Authentication bypass
3. Authorization bypass
4. API abuse

**Mitigations:**

- Input validation
- Rate limiting
- Authentication required
- Authorization checks
- Request size limits

### Database

**Attack Surface:**

- Database connections from API
- Backup storage
- Migration scripts

**Key Risks:**

1. SQL injection
2. Unauthorized access
3. Data exfiltration
4. Backup theft

**Mitigations:**

- Parameterized queries (Prisma)
- Private network access
- Encrypted backups
- Access logging

## Security Controls Mapping

| Threat Category      | Controls                                   | Priority |
| -------------------- | ------------------------------------------ | -------- |
| Authentication       | JWT, bcrypt, refresh tokens, rate limiting | HIGH     |
| Authorization        | RBAC, ownership checks, least privilege    | HIGH     |
| Data Protection      | TLS, encryption at rest, secure storage    | HIGH     |
| Input Validation     | Zod schemas, sanitization, CSP             | HIGH     |
| Logging & Monitoring | Audit logs, anomaly detection, alerts      | MEDIUM   |
| Network Security     | HTTPS only, CORS, rate limiting            | HIGH     |
| Denial of Service    | Rate limiting, auto-scaling, timeouts      | MEDIUM   |
| Code Security        | Dependency scanning, code review, SAST     | HIGH     |

## Incident Response

### Detection

1. **Automated Monitoring:**
   - Error rate spikes
   - Unusual traffic patterns
   - Failed authentication attempts
   - Authorization failures

2. **Manual Review:**
   - Security audit logs
   - User reports
   - Penetration test results

### Response Procedure

1. **Identify:** Confirm security incident
2. **Contain:** Limit scope and prevent spread
3. **Eradicate:** Remove threat
4. **Recover:** Restore service
5. **Post-Mortem:** Document and improve

### Communication Plan

- **Users:** Email notification within 72 hours (GDPR)
- **Team:** Immediate via Slack/email
- **Authorities:** As required by law

## Compliance Considerations

### GDPR (General Data Protection Regulation)

- ✅ Data minimization
- ✅ User consent
- ✅ Right to access
- ✅ Right to deletion
- ✅ Data portability
- ✅ Breach notification (72 hours)
- ✅ Privacy by design

### CCPA (California Consumer Privacy Act)

- ✅ Data disclosure
- ✅ Opt-out rights
- ✅ Non-discrimination
- ✅ Data sale transparency

## Future Enhancements

### Phase 2: Enhanced Security

- [ ] Two-factor authentication (2FA)
- [ ] Biometric authentication
- [ ] Device management
- [ ] Session management UI

### Phase 3: Advanced Protection

- [ ] Anomaly detection
- [ ] Behavioral analytics
- [ ] Advanced threat protection
- [ ] Security monitoring dashboard

### Phase 4: Enterprise Security

- [ ] SSO (WorkOS)
- [ ] SCIM provisioning
- [ ] Advanced audit logging
- [ ] SOC 2 Type II compliance

## Security Testing

### Regular Activities

- **Daily:** Automated dependency scanning
- **Weekly:** Code security review
- **Monthly:** Penetration testing
- **Quarterly:** Security audit
- **Annually:** Third-party security assessment

### Tools

- npm audit (dependency vulnerabilities)
- Snyk (continuous monitoring)
- ESLint security plugins
- GitHub security scanning
- Manual code review

## References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [STRIDE Threat Model](https://docs.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)
- [Chrome Extension Security](https://developer.chrome.com/docs/extensions/mv3/security/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)

---

**Last Updated:** 2025-12-07  
**Version:** 1.0  
**Next Review:** 2026-03-07
