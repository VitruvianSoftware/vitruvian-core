# Operator Guide: WorkOS Authentication Configuration

This guide is for DevOps engineers and system operators who need to configure and manage Tabula's
WorkOS authentication infrastructure.

## Table of Contents

- [Overview](#overview)
- [WorkOS Setup](#workos-setup)
- [Environment Configuration](#environment-configuration)
- [Deployment](#deployment)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)

## Overview

Tabula uses WorkOS AuthKit for SSO authentication with JWT tokens for API access.

## WorkOS Setup

### Account Creation

1. Sign up at [workos.com](https://workos.com)
2. Create application: "Tabula"
3. Verify email

### Authentication Configuration

1. **Enable Methods**:
   - Google OAuth ✅
   - Microsoft OAuth ✅
   - GitHub OAuth ✅
   - Magic Link ✅
   - Password (optional)

2. **Configure Redirect URIs**:

   ```
   Development:  http://localhost:8080/api/v1/auth/callback
   Staging:      https://api-staging.tabula.app/api/v1/auth/callback
   Production:   https://api.tabula.app/api/v1/auth/callback
   ```

3. **Security Settings**:
   - MFA: Enabled (production)
   - Email verification: Enabled
   - Session duration: 7 days
   - Password: 8+ characters, uppercase, lowercase, numbers

### API Credentials

1. **API Key**: Dashboard → API Keys → Create
2. **Client ID**: Dashboard → Configuration

Store securely in environment variables or secret manager.

## Environment Configuration

### Production Environment Variables

```bash
# WorkOS
WORKOS_API_KEY=sk_live_production_api_key
WORKOS_CLIENT_ID=client_production_client_id

# JWT
JWT_SECRET=<64-char-random-string>
JWT_REFRESH_SECRET=<64-char-random-string>
JWT_EXPIRATION=15m
JWT_REFRESH_EXPIRATION=7d

# API
API_URL=https://api.tabula.app

# Generate secrets:
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

### Secret Management

```bash
# Store in Google Secret Manager
tabcli secrets set WORKOS_API_KEY --env production --value "sk_live_..."
tabcli secrets set JWT_SECRET --env production --value "..."

# Retrieve
tabcli secrets get WORKOS_API_KEY --env production
```

## Deployment

1. **Set secrets**:

   ```bash
   tabcli secrets set WORKOS_API_KEY --env production
   tabcli secrets set JWT_SECRET --env production
   ```

2. **Deploy**:

   ```bash
   tabcli infra apply --env production
   ```

3. **Verify**:
   ```bash
   curl https://api.tabula.app/health
   curl -I https://api.tabula.app/api/v1/auth/login
   ```

## Monitoring

### Key Metrics

- Login success rate: > 99%
- Average login time: < 2 seconds
- Failed attempts: < 1%
- Token refresh rate: Normal pattern

### Alerts

- Auth failures: > 10 in 5 min
- WorkOS errors: > 5 in 1 min
- Database timeouts: > 3 consecutive
- High latency: P95 > 3s

## Troubleshooting

### "WORKOS_API_KEY is not defined"

1. Check secret exists: `tabcli secrets list`
2. Add if missing: `tabcli secrets set WORKOS_API_KEY`
3. Redeploy: `tabcli infra apply`

### "Invalid redirect URI"

1. Check WorkOS dashboard redirect URIs
2. Verify API_URL environment variable
3. Update WorkOS configuration

### "JWT verification failed"

1. Check JWT_SECRET consistency
2. Verify token expiration
3. Check clock skew
4. User may need to re-login

## Security Best Practices

### Secret Rotation

- JWT secrets: Every 90 days
- WorkOS keys: Annually or if compromised
- Use rolling rotation

### Access Control

- Enable 2FA for admins
- Use RBAC
- Audit logs monthly

### Incident Response

**If API Key Compromised**:

1. Revoke key in WorkOS
2. Generate new key
3. Update environments
4. Redeploy
5. Review audit logs

**If JWT Secret Compromised**:

1. Generate new secret
2. Rolling update
3. Force token refresh
4. Monitor activity

## Resources

- WorkOS: [workos.com/docs](https://workos.com/docs)
- Architecture: `docs/architecture/authentication.md`
- Development: `docs/getting-started/development.md`

---

_Last updated: December 2024_
