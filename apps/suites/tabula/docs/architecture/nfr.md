# Non-Functional Requirements (NFR)

## Overview

This document defines the non-functional requirements for Tabula, establishing measurable targets
for performance, scalability, reliability, security, privacy, accessibility, and code quality. These
requirements ensure the product delivers a high-quality user experience while maintaining
operational efficiency.

---

## Performance Requirements

Performance targets are critical to ensuring a responsive user experience. All measurements are
taken under normal operating conditions.

| Metric                     | Target     | Measurement Method                     |
| -------------------------- | ---------- | -------------------------------------- |
| Extension load time        | < 500ms    | Chrome DevTools Performance tab        |
| Popup render time          | < 200ms    | Performance API (`performance.now()`)  |
| API response time (p95)    | < 200ms    | Cloud Monitoring metrics               |
| API response time (p99)    | < 500ms    | Cloud Monitoring metrics               |
| Database query time (p95)  | < 50ms     | Neon database metrics                  |
| Sync latency               | < 1 second | Custom metric (time from push to pull) |
| Extension memory footprint | < 50MB     | Chrome Task Manager                    |
| Extension CPU usage (idle) | < 1%       | Chrome Task Manager                    |

**Testing Protocol:**

- Performance tests should be run on a representative user device (mid-range laptop, 8GB RAM, Chrome
  120+)
- Load testing should simulate realistic user patterns
- Measurements should be taken over a 24-hour period to account for variability
- All metrics should be monitored in production via Cloud Monitoring dashboards

---

## Scalability Requirements

Scalability requirements are defined per phase to guide infrastructure planning and resource
allocation.

| Metric              | Phase 1 (MVP) | Phase 2 | Phase 3   | Phase 4   |
| ------------------- | ------------- | ------- | --------- | --------- |
| Concurrent users    | 100           | 1,000   | 10,000    | 100,000   |
| Workspaces per user | 10            | 50      | Unlimited | Unlimited |
| Tabs per workspace  | 100           | 500     | 1,000     | 1,000     |
| API requests/sec    | 10            | 100     | 1,000     | 10,000    |

**Scaling Strategy:**

- **Horizontal Scaling**: Cloud Run auto-scales instances based on request volume
- **Database Scaling**: Neon auto-scales compute units (0.25 - 2 CU) based on load
- **Cache Scaling**: Upstash Redis scales automatically with usage
- **Storage Scaling**: Cloud Storage has no upper limit
- **Cost Monitoring**: Set up alerts when approaching free tier limits

**Load Testing:**

- Conduct load tests before each phase rollout
- Use tools like Apache JMeter or k6 for API load testing
- Simulate realistic user behavior patterns
- Test edge cases (bulk operations, concurrent updates)

---

## Reliability Requirements

Reliability targets ensure the service is available and resilient to failures.

### Uptime SLA

- **Target**: 99.9% uptime (8.76 hours downtime/year maximum)
- **Measurement**: Cloud Monitoring uptime checks (1-minute intervals)
- **Exclusions**: Scheduled maintenance windows (announced 7 days in advance)

### Recovery Objectives

- **RPO (Recovery Point Objective)**: 1 hour
  - Maximum acceptable data loss
  - Achieved through automatic backups every 6 hours + database WAL
- **RTO (Recovery Time Objective)**: 4 hours
  - Maximum acceptable downtime for full system recovery
  - Includes disaster recovery scenario

### Backup Requirements

- **Frequency**: Every 6 hours (automatic via Cloud Scheduler)
- **Retention**:
  - Free tier: 30 days
  - Pro tier: 90 days
- **Backup Types**:
  - User workspace snapshots (incremental)
  - Database point-in-time recovery (7 days via Neon)
  - Full database export (weekly to Cloud Storage)
- **Verification**: Monthly backup restoration tests

### Failure Handling

- **Graceful Degradation**: Extension functions offline with local storage when API unavailable
- **Retry Logic**: Exponential backoff for failed API requests (max 3 retries)
- **Circuit Breaker**: Disable sync temporarily if API is consistently failing
- **Error Reporting**: All errors logged to Cloud Logging with severity levels

---

## Security Requirements

Security is paramount to protect user data and maintain trust.

### Authentication

- All API endpoints require authentication except:
  - `POST /api/v1/auth/signup`
  - `POST /api/v1/auth/login`
  - `GET /api/v1/health` (health check)
- Passwords hashed with bcrypt (cost factor: 12)
- JWT access tokens:
  - Expiration: 15 minutes
  - Algorithm: RS256 (asymmetric signing)
  - Payload: user ID, email, tier, issued at, expiration
- JWT refresh tokens:
  - Expiration: 7 days
  - Stored in database with hash
  - Rotated on each use
  - Revoked on logout

### Data Encryption

- **In Transit**:
  - TLS 1.3 for all API communications
  - Enforce HTTPS via HSTS headers
  - Certificate auto-renewal via Let's Encrypt
- **At Rest**:
  - Database encryption (Neon default encryption)
  - Cloud Storage encryption (AES-256)
  - Secrets encrypted in Google Secret Manager

### Access Control

- **Rate Limiting**: 100 requests/minute per user (enforced via Redis)
- **Request Validation**:
  - Input validation on all endpoints (max sizes, allowed characters)
  - Request body size limit: 1MB
  - Content-Type verification
- **SQL Injection Prevention**: Parameterized queries only (no string concatenation)
- **XSS Prevention**:
  - Content Security Policy (CSP) headers
  - Sanitize all user input before storage
  - Escape output in web dashboard
- **CORS**: Whitelist for allowed origins (extension ID, dashboard domain)

### Secret Management

- Secrets stored in Google Secret Manager (never in code or env files)
- Secret rotation policy: Every 90 days
- Access to secrets via IAM service accounts only
- Audit logging enabled for all secret access

### Vulnerability Management

- Dependency scanning: Weekly automated scans with Dependabot
- Security updates: Applied within 7 days of disclosure
- Penetration testing: Annual third-party assessment (Phase 3+)
- Bug bounty program: Launch in Phase 3

---

## Privacy Requirements

Privacy protection is core to building user trust and GDPR compliance.

### Data Minimization

- Collect only data necessary for functionality:
  - User: email, password hash, name, tier
  - Workspace: name, description, settings
  - Tab: URL, title, favicon URL, metadata
- No tracking pixels or third-party analytics scripts in extension
- No behavioral analytics without explicit user consent

### User Data Rights (GDPR Compliance)

- **Right to Access**: User can export all their data (JSON format)
- **Right to Deletion**: User can delete account and all associated data
  - Cascade delete all workspaces, tabs, backups
  - Purge from database and storage within 24 hours
  - Confirmation required before deletion
- **Right to Portability**: Export includes all user data in machine-readable format
- **Right to Rectification**: User can update their account information

### Data Sharing

- **No Sale of User Data**: Explicitly prohibited
- **No Third-Party Sharing**: User data never shared without explicit consent
- **Subprocessors**: Limited to infrastructure providers (GCP, Neon, Upstash)
- **Transparency**: Clear privacy policy listing all data handling practices

### Compliance

- Privacy policy published and linked in extension and dashboard
- Terms of service clearly outline data handling
- Cookie consent for web dashboard (EU users)
- Data residency options for EU users (Phase 3+)

---

## Accessibility Requirements

Accessibility ensures the product is usable by everyone, including users with disabilities.

### WCAG 2.1 AA Compliance (Web Dashboard)

- **Perceivable**:
  - Text alternatives for non-text content
  - Captions for audio/video
  - Content structure using semantic HTML
  - Color contrast ratios meet AA standards (4.5:1 for normal text, 3:1 for large text)
- **Operable**:
  - All functionality available via keyboard
  - No keyboard traps
  - Sufficient time for interactions
  - Clear focus indicators (visible outline, 2px minimum)
- **Understandable**:
  - Readable text (minimum 16px font size)
  - Consistent navigation
  - Error messages with clear guidance
  - Labels for form inputs
- **Robust**:
  - Valid HTML
  - ARIA attributes where needed
  - Compatible with assistive technologies

### Keyboard Navigation Support

- Tab key to navigate between interactive elements
- Enter/Space to activate buttons and links
- Arrow keys for dropdown menus and lists
- Escape key to close modals and menus
- Keyboard shortcuts documented and customizable

### Screen Reader Compatibility

- Tested with NVDA (Windows), JAWS (Windows), VoiceOver (macOS)
- Semantic HTML elements (`<nav>`, `<main>`, `<article>`, etc.)
- ARIA labels for dynamic content
- Live regions for real-time updates

### Testing

- Automated testing with axe DevTools
- Manual testing with keyboard navigation
- Screen reader testing on major platforms
- Color blindness simulation testing

---

## Browser Compatibility

Browser support is defined per phase, starting with Chromium-based browsers.

| Browser | Version | Support Level        | Notes                                          |
| ------- | ------- | -------------------- | ---------------------------------------------- |
| Chrome  | 120+    | Full support         | Primary target browser                         |
| Edge    | 120+    | Full support         | Chromium-based, minimal additional work        |
| Firefox | 115+    | Phase 1 stretch goal | Manifest V3 API differences require adaptation |
| Safari  | -       | Future consideration | Phase 4+ if market demand exists               |

**Testing Protocol:**

- Automated tests run on Chrome stable and Edge stable
- Manual testing on latest Firefox Developer Edition (if Phase 1 stretch goal)
- Test on both Windows and macOS
- Minimum screen resolution: 1280x720

**Browser API Requirements:**

- Manifest V3 support
- Chrome Extensions API: `tabs`, `storage`, `identity`, `alarms`, `scripting`
- Web APIs: `fetch`, `localStorage`, `indexedDB`, `crypto`

---

## Code Quality Requirements

Code quality standards ensure maintainability, readability, and reliability.

### Language Requirements

- **TypeScript**: Strict mode enabled in all projects
  - No `any` types (use `unknown` or specific types)
  - No implicit `any` on parameters
  - Strict null checks enabled
  - All functions have explicit return types
- **Go**: Standard library and idiomatic Go patterns
  - All exported functions have GoDoc comments
  - Error handling with wrapped errors (Go 1.13+ `%w`)

### Linting & Formatting

- **TypeScript/JavaScript**:
  - ESLint with recommended rules + Airbnb config
  - Prettier for code formatting (no semicolons, single quotes)
  - Pre-commit hooks enforce formatting
- **Go**:
  - `gofmt` for formatting
  - `golangci-lint` with default rules
  - Pre-commit hooks enforce formatting

### Testing Requirements

- **Unit Test Coverage**: Minimum 80% overall
  - 90%+ for critical business logic (auth, sync, data operations)
  - 70%+ acceptable for UI components
- **E2E Test Coverage**: All critical user paths
  - User registration and login
  - Workspace creation and deletion
  - Tab save and restore
  - Cross-device sync
- **Test Frameworks**:
  - TypeScript: Jest for unit tests, Playwright for E2E
  - Go: Standard `testing` package, testify for assertions

### Documentation Requirements

- **Code Documentation**:
  - JSDoc comments for all exported TypeScript functions
  - GoDoc comments for all exported Go functions
  - Inline comments for complex logic only
- **API Documentation**:
  - OpenAPI 3.0 specification (see `api/openapi.yaml`)
  - Examples for all endpoints
  - Error responses documented

### Commit Standards

- **Conventional Commits**: All commits follow format:

  ```
  <type>: <short description>

  <optional longer description>

  <optional footer>
  ```

- **Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
- **Examples**:
  - `feat: add workspace search functionality`
  - `fix: resolve sync conflict when offline`
  - `docs: update API documentation for sync endpoints`

### Code Review

- All code changes require PR review
- At least one approval before merge
- Automated checks must pass (linting, tests, build)
- No merging of failing builds

---

## Monitoring & Alerting Requirements

Monitoring ensures early detection of issues and performance degradation.

### Metrics Collection

- **Application Metrics**:
  - Request rate, latency, error rate (by endpoint)
  - User sign-ups, logins, active sessions
  - Workspace and tab creation/deletion rates
  - Sync operations per minute
- **Infrastructure Metrics**:
  - Cloud Run: CPU, memory, instance count
  - Database: Connection count, query latency, storage usage
  - Cache: Hit rate, eviction rate, memory usage
  - Storage: Object count, total size

### Logging

- **Structured Logging**: JSON format with consistent fields
  - Timestamp, severity, message, user ID, request ID, trace ID
- **Log Levels**: DEBUG, INFO, WARN, ERROR, CRITICAL
- **Retention**: 30 days in Cloud Logging
- **PII Protection**: Never log passwords, tokens, or sensitive data

### Alerting

- **Critical Alerts** (Page immediately):
  - API error rate > 1%
  - API p99 latency > 2 seconds
  - Database connection failures
  - Service completely down
- **Warning Alerts** (Email/Slack):
  - API error rate > 0.5%
  - API p95 latency > 500ms
  - Free tier quota > 80%
  - Unusual traffic patterns (potential DDoS)
- **Info Alerts**:
  - New user sign-ups milestone (100, 1000, 10000)
  - Approaching resource limits

### Dashboards

- Real-time metrics dashboard (Cloud Monitoring)
- User analytics dashboard (internal)
- Cost tracking dashboard (GCP billing)

---

## Compliance & Legal Requirements

### Data Protection

- GDPR compliance (EU users)
- CCPA compliance (California users)
- Data Processing Agreement (DPA) available for enterprise customers
- Privacy policy and terms of service published

### Service Level Agreement (SLA)

- Published SLA for Pro and Team tiers
- Uptime guarantee: 99.9%
- Response time targets documented
- Compensation policy for SLA violations (service credits)

### Audit Trail

- All user actions logged (workspace CRUD, tab operations)
- Admin actions logged (user management, settings changes)
- Audit logs retained for 1 year
- Available for export by enterprise customers

---

## Revision History

- **2025-12-07**: Initial NFR document created (v1.0)

---

_This document is reviewed quarterly and updated as requirements evolve. Next review: 2025-03-07_
