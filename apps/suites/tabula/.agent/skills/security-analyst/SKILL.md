---
name: Security Analyst
description: Expert guidance for security review and hardening of Tabula
---

# Security Analyst

You are an expert security analyst specializing in reviewing and hardening the Tabula application.

## Security Architecture

### Authentication Flow

1. User submits credentials to `/api/v1/auth/login`
2. API validates password against bcrypt hash (cost factor: 12)
3. Returns JWT access token (15min) + refresh token (7 days)
4. Refresh token stored in Redis with hash
5. Access tokens use RS256 signing algorithm

### Token Security

```typescript
// JWT Configuration
const jwtConfig = {
  algorithm: 'RS256',
  accessTokenExpiry: '15m',
  refreshTokenExpiry: '7d',
  issuer: 'tabula-api',
  audience: 'tabula-extension',
};
```

**Security Controls**:

- Short-lived access tokens
- Refresh token rotation on use
- Session invalidation on logout
- Token revocation via Redis blacklist

## Key Security Areas

### Chrome Extension Security

**Content Security Policy**:

```json
{
  "content_security_policy": {
    "extension_pages": "script-src 'self'; object-src 'self'"
  }
}
```

**Permissions Audit**:

- `tabs` - Required for tab management (justified)
- `storage` - Required for local persistence (justified)
- `alarms` - Required for periodic tasks (justified)
- `host_permissions` - Access tab URLs (review carefully)

### API Security

**Rate Limiting**:

```typescript
// 100 requests per minute per user
const rateLimitConfig = {
  max: 100,
  timeWindow: '1 minute',
  keyGenerator: (req) => req.user?.id || req.ip,
};
```

**Input Validation**:

- All inputs validated with Zod schemas
- SQL injection prevented via Prisma parameterized queries
- XSS prevented via CSP and output encoding

**CORS Configuration**:

```typescript
const corsConfig = {
  origin: ['chrome-extension://*', 'https://tabula.dev', 'https://dashboard.tabula.dev'],
  credentials: true,
};
```

### Data Protection

**Encryption**:

- TLS 1.3 for all API communications
- Data encrypted at rest in Neon, Cloud Storage
- Secrets stored in Google Secret Manager

**PII Handling**:

- Minimal data collection principle
- User can export all data (GDPR)
- User can delete account (hard delete)
- No analytics tracking scripts

## Threat Model

### Extension Threats

| Threat              | Mitigation               |
| ------------------- | ------------------------ |
| XSS in popup        | CSP, no `unsafe-inline`  |
| Storage tampering   | Validate data on load    |
| Message spoofing    | Validate sender origin   |
| Supply chain attack | Lock dependencies, audit |

### API Threats

| Threat                  | Mitigation                     |
| ----------------------- | ------------------------------ |
| Brute force login       | Rate limiting, lockout         |
| Token theft             | Short expiry, refresh rotation |
| IDOR (workspace access) | Owner validation on all routes |
| Data injection          | Zod validation, Prisma         |

### Infrastructure Threats

| Threat              | Mitigation              |
| ------------------- | ----------------------- |
| Secret exposure     | Secret Manager, IAM     |
| Unauthorized access | VPC, service accounts   |
| DDoS                | Cloudflare, rate limits |

## Security Checklist

### Pre-Deployment

- [ ] All secrets in Secret Manager (not env vars)
- [ ] JWT keys rotated
- [ ] CORS whitelist reviewed
- [ ] Rate limits configured
- [ ] CSP headers verified
- [ ] Dependencies audited (`npm audit`)

### Code Review

- [ ] No hardcoded secrets
- [ ] All user inputs validated
- [ ] Authorization checks on routes
- [ ] Error messages don't leak info
- [ ] Sensitive data not logged

## Security Commands

```bash
# Check for vulnerabilities
npm audit

# Run security-focused tests
npm test -- --testPathPattern=security

# Review secret usage
tabcli infra secrets list
```

## Key Security Files

- [SECURITY.md](../../../SECURITY.md)
- [Threat Model](../../../docs/architecture/threat-model.md)
- [Authentication Docs](../../../docs/architecture/authentication.md)
- [Extension Manifest](../../../extension/src/manifest.json)
