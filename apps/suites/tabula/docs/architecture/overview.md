# Tabula System Architecture

## Overview

Tabula is designed with a lean, cost-effective cloud architecture that leverages generous free tiers
from modern cloud providers. The system is built to scale from zero to thousands of users while
keeping operational costs minimal through serverless compute, managed databases, and efficient
caching strategies.

## Architecture Principles

1. **Serverless-First**: Use Cloud Run and managed services to eliminate infrastructure management
2. **Scale-to-Zero**: Minimize costs during low-traffic periods
3. **Free Tier Optimization**: Maximize use of provider free tiers (Neon, Upstash, WorkOS)
4. **Performance**: Fast response times through caching and CDN
5. **Security**: End-to-end encryption, SOC 2 compliant providers
6. **Simplicity**: Avoid over-engineering, choose managed services over custom solutions

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TABULA ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐     │
│  │  Chrome/Edge/    │     │   Web Dashboard  │     │   Mobile PWA     │     │
│  │  Firefox Ext     │     │   (React/Next)   │     │   (Optional)     │     │
│  └────────┬─────────┘     └────────┬─────────┘     └────────┬─────────┘     │
│           └────────────────────────┼────────────────────────┘               │
│                          ┌─────────▼─────────┐                              │
│                          │   Cloud Run API   │                              │
│                          │ (Node.js/Fastify) │                              │
│                          └─────────┬─────────┘                              │
│           ┌────────────────────────┼───────────────────────┐                │
│  ┌────────▼────────┐     ┌─────────▼─────────┐    ┌────────▼────────┐       │
│  │   Neon Postgres │     │   Upstash Redis   │    │    WorkOS SSO   │       │
│  │   (Database)    │     │   (Cache/Sync)    │    │ (Authentication)│       │
│  └─────────────────┘     └───────────────────┘    └─────────────────┘       │
│  ┌─────────────────┐     ┌───────────────────┐    ┌─────────────────┐       │
│  │ Cloud Storage   │     │  Cloud Scheduler  │    │   Pub/Sub       │       │
│  │ (Backups/Assets)│     │  (Cron Jobs)      │    │   (Events)      │       │
│  └─────────────────┘     └───────────────────┘    └─────────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### Client Layer

#### Browser Extension (Chrome/Edge/Firefox)

- **Technology**: Manifest V3, React, TypeScript, Zustand, Framer Motion, @dnd-kit/react
- **Responsibilities**:
  - Tab management and suspension
  - Local storage for offline access
  - Sync with backend API
  - UI rendering (popup, sidebar)
- **Key Features**:
  - Lightweight (< 50MB memory footprint)
  - Works offline with local storage fallback
  - Background service worker for tab monitoring
  - Content scripts for tab interaction

#### Web Dashboard (React/Next.js)

- **Technology**: Next.js 16+, React, TypeScript, Tailwind CSS, Zustand
- **Responsibilities**:
  - Account management
  - Workspace visualization
  - Backup browsing and restore
  - Settings and preferences
- **Deployment**: Cloudflare Pages or Vercel (free tier)
- **Features**:
  - Server-side rendering for SEO
  - Static generation where possible
  - Progressive Web App (PWA) capabilities

#### Mobile PWA (Optional - Phase 4+)

- **Technology**: Next.js PWA, responsive design
- **Responsibilities**:
  - View and search workspaces
  - Open tabs on desktop via deep linking
  - Read-only workspace management
- **Installation**: Add to home screen capability

### API Layer

#### Cloud Run API

- **Technology**: Node.js, Fastify, Prisma, Zod, ioredis, WorkOS SDK
- **Deployment**: Google Cloud Run
- **Configuration**:
  - Scale to zero when idle
  - Min instances: 0
  - Max instances: 100 (adjustable)
  - CPU: 1 vCPU
  - Memory: 512MB
  - Request timeout: 60s
  - Concurrency: 80 requests per instance

**API Endpoints:**

```
Auth:
  POST   /api/v1/auth/signup
  POST   /api/v1/auth/login
  POST   /api/v1/auth/logout
  POST   /api/v1/auth/refresh
  GET    /api/v1/auth/me

Workspaces:
  GET    /api/v1/workspaces
  POST   /api/v1/workspaces
  GET    /api/v1/workspaces/:id
  PUT    /api/v1/workspaces/:id
  DELETE /api/v1/workspaces/:id

Tabs:
  GET    /api/v1/workspaces/:id/tabs
  POST   /api/v1/workspaces/:id/tabs
  PUT    /api/v1/tabs/:id
  DELETE /api/v1/tabs/:id
  POST   /api/v1/tabs/:id/move

Sync:
  GET    /api/v1/sync/state
  POST   /api/v1/sync/push
  GET    /api/v1/sync/pull

Backups:
  GET    /api/v1/backups
  GET    /api/v1/backups/:id
  POST   /api/v1/backups/:id/restore

Search:
  GET    /api/v1/search?q=query&workspace=id

Space Groups:
  GET    /api/v1/space-groups
  POST   /api/v1/space-groups
  GET    /api/v1/space-groups/:id
  PUT    /api/v1/space-groups/:id
  DELETE /api/v1/space-groups/:id

Templates:
  GET    /api/v1/templates
  GET    /api/v1/templates/:id
  POST   /api/v1/templates/:id/instantiate

Team (Phase 4):
  GET    /api/v1/teams
  POST   /api/v1/teams/:id/members
  GET    /api/v1/teams/:id/workspaces
```

**Authentication:**

- JWT tokens for API authentication
- WorkOS for SSO (Phase 4)
- Refresh token rotation
- Rate limiting per user

### Data Layer

#### Neon Postgres

- **Provider**: Neon (neon.tech)
- **Free Tier**: 0.5 GB storage, autoscaling to zero
- **Configuration**:
  - Region: us-east-1 (or closest to users)
  - Postgres version: 16
  - Autoscaling: 0.25 - 2 compute units
  - Autosuspend: 5 minutes of inactivity
  - Branching: Dev branch for testing

**Database Schema (v1):**

```sql
-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255),
  name VARCHAR(255),
  tier VARCHAR(20) DEFAULT 'free', -- free, pro, team
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_login_at TIMESTAMP,
  preferences JSONB DEFAULT '{}'
);

-- Workspaces table
CREATE TABLE workspaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  team_id UUID REFERENCES teams(id) ON DELETE CASCADE, -- Phase 4
  name VARCHAR(255) NOT NULL,
  description TEXT,
  color VARCHAR(7), -- hex color
  icon VARCHAR(50),
  position INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  settings JSONB DEFAULT '{}'
);

-- Space Groups table
CREATE TABLE space_groups (
  id VARCHAR(255) PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  title VARCHAR(255) NOT NULL,
  collapsed BOOLEAN DEFAULT false,
  position INTEGER DEFAULT 0,
  color VARCHAR(7),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_space_groups_user ON space_groups(user_id);

-- Tabs table
CREATE TABLE tabs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  title VARCHAR(500),
  favicon_url TEXT,
  position INTEGER DEFAULT 0,
  is_pinned BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  metadata JSONB DEFAULT '{}'
);

-- Backups table
CREATE TABLE backups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
  snapshot JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  size_bytes INTEGER
);

-- Sessions table
CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  refresh_token_hash VARCHAR(255),
  device_info JSONB,
  ip_address INET,
  created_at TIMESTAMP DEFAULT NOW(),
  expires_at TIMESTAMP,
  last_active_at TIMESTAMP DEFAULT NOW()
);

-- Teams table (Phase 4)
CREATE TABLE teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(100) UNIQUE,
  created_at TIMESTAMP DEFAULT NOW(),
  settings JSONB DEFAULT '{}'
);

-- Team members (Phase 4)
CREATE TABLE team_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(20) DEFAULT 'member', -- admin, member, viewer
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(team_id, user_id)
);

-- Indexes
CREATE INDEX idx_workspaces_user ON workspaces(user_id);
CREATE INDEX idx_tabs_workspace ON tabs(workspace_id);
CREATE INDEX idx_backups_user ON backups(user_id);
CREATE INDEX idx_backups_created ON backups(created_at);
CREATE INDEX idx_sessions_user ON sessions(user_id);
```

#### Upstash Redis

- **Provider**: Upstash (upstash.com)
- **Free Tier**: 10,000 commands/day
- **Configuration**:
  - Region: Global (edge caching)
  - TLS enabled
  - REST API access

**Usage:**

- Session caching
- Real-time sync state
- Rate limiting counters
- Pub/Sub for real-time updates
- Temporary data (workspace locks, etc.)

**Note:** Upstash has no official Terraform provider. Setup steps:

1. Create account at upstash.com
2. Create Redis database via dashboard
3. Copy REST API URL and token
4. Add to Secret Manager as `UPSTASH_REDIS_URL`

### Storage Layer

#### Google Cloud Storage

- **Free Tier**: 5 GB storage, 5,000 Class A operations/month
- **Buckets**:
  1. **Backup Bucket** (`{project}-backups`)
     - Lifecycle: Transition to NEARLINE after 30 days
     - Lifecycle: Delete after retention period (90 days for Pro, 30 days for Free)
     - Private access only
     - Versioning enabled
  2. **Assets Bucket** (`{project}-assets`)
     - Public read access
     - CORS enabled for web dashboard
     - CDN caching via Cloudflare
     - Store: favicons, screenshots, user uploads

### Authentication & Identity

#### WorkOS

- **Provider**: WorkOS (workos.com)
- **Free Tier**: 1M MAUs free
- **Features Used**:
  - SSO (SAML, OAuth) - Phase 4
  - SCIM for user provisioning - Phase 4
  - Directory sync
  - Admin Portal

**Note:** WorkOS Terraform provider is community-maintained. Recommended approach:

1. Configure via WorkOS dashboard
2. Store API keys in Secret Manager
3. Document configuration in infrastructure README

**Phase 1-3:** Use JWT-based authentication with email/password **Phase 4:** Migrate to WorkOS for
enterprise SSO

### Background Jobs

#### Google Cloud Scheduler

- **Free Tier**: 3 jobs free/month
- **Jobs**:
  1. **Backup Job**: Every 6 hours (4x daily)
     - Trigger: POST to `/api/v1/jobs/backup`
     - Creates incremental backups for all active users
  2. **Cleanup Job**: Daily at 2 AM UTC
     - Trigger: POST to `/api/v1/jobs/cleanup`
     - Remove expired backups
     - Delete soft-deleted workspaces
     - Purge old sessions
  3. **Sync Job**: Every 5 minutes
     - Trigger: POST to `/api/v1/jobs/sync`
     - Process pending sync queue
     - Update search indexes

**Authentication:** OIDC token authentication to Cloud Run

### Event-Driven Architecture

#### Google Pub/Sub

- **Free Tier**: 10 GB/month
- **Topics**:
  - `workspace-updates`: Real-time workspace changes
  - `tab-updates`: Real-time tab changes
  - `user-events`: User activity events
  - `backup-events`: Backup completion notifications

**Usage:**

- Real-time sync notifications
- Cross-device update propagation
- Event sourcing for audit logs
- Webhook delivery (Phase 3+)

### CDN & Edge

#### Cloudflare

- **Free Tier**: Unlimited bandwidth
- **Features**:
  - Global CDN for static assets
  - DDoS protection
  - SSL/TLS encryption
  - Page rules for caching
  - DNS management

**Cached Resources:**

- Web dashboard static files
- Favicon cache
- Screenshot thumbnails
- Template images

---

## Service Selection Rationale

| Service   | Provider               | Free Tier         | Cost at 10K Users | Purpose                  | Why Chosen                                           |
| --------- | ---------------------- | ----------------- | ----------------- | ------------------------ | ---------------------------------------------------- |
| Compute   | Google Cloud Run       | 2M requests/month | ~$50/month        | API backend              | Scale-to-zero, pay-per-use, no idle costs            |
| Database  | Neon Postgres          | 0.5 GB storage    | ~$20/month        | User data, workspaces    | Serverless Postgres, autoscaling, generous free tier |
| Cache     | Upstash Redis          | 10K commands/day  | ~$10/month        | Session cache, real-time | Serverless Redis, edge caching, REST API             |
| Auth      | WorkOS                 | 1M MAUs free      | $0 (under 1M)     | SSO, SCIM                | Enterprise-ready auth, generous free tier            |
| Storage   | Google Cloud Storage   | 5 GB              | ~$10/month        | Backups, assets          | Standard cloud storage, lifecycle policies           |
| Scheduler | Google Cloud Scheduler | 3 jobs free       | $0.10/job/month   | Cron jobs                | Managed cron, OIDC auth to Cloud Run                 |
| Messaging | Google Pub/Sub         | 10 GB/month       | ~$5/month         | Event-driven sync        | Real-time messaging, reliable delivery               |
| CDN       | Cloudflare             | Unlimited         | $0                | Static delivery          | Free unlimited bandwidth, global CDN                 |

**Total Estimated Cost at 10K Users:** ~$95-100/month (< $0.01 per user)

### Architectural Alternatives (2026 Evaluation)

**Convex vs. Current Stack (Fastify/Neon/Upstash)**

| Feature          | Tabula Stack (Current)                                                                                  | Convex                                                                                                     |
| :--------------- | :------------------------------------------------------------------------------------------------------ | :--------------------------------------------------------------------------------------------------------- |
| **Philosophy**   | **Local-First**. `chrome.storage` is the source of truth; sync is a background replication task.        | **Cloud-First**. The backend is the source of truth; clients are efficient caches.                         |
| **Connectivity** | **Offline-Capable**. Works fully without internet; queues changes for later.                            | **Online-Preferred**. Optimistic updates work, but heavy reliable offline support requires custom bridges. |
| **Data Layer**   | **Standard SQL (Postgres)**. High portability, standard tooling.                                        | **Proprietary Document-Relational**. High velocity, but high vendor lock-in.                               |
| **Complexity**   | **High**. Manual implementation of sync queues, conflict resolution, and transport (SSE).               | **Low**. Sync, caching, and reactivity are handled automatically by the platform.                          |
| **Verdict**      | **Retained**. Simulates "data sovereignty" and maximizes offline reliability for the extension context. | **Rejected**. Would require abandoning the "Local-First" architecture for a "Cloud-Centric" one.           |

---

## Data Flow

### User Registration Flow

```
Browser Extension
  → POST /api/v1/auth/signup
    → Cloud Run API validates input
      → Check Neon DB for existing email
        → Hash password (bcrypt)
          → Insert into users table
            → Generate JWT tokens
              → Cache session in Upstash
                → Return tokens to client
```

### Workspace Sync Flow

> **Detailed Documentation:** See [Sync Strategy](sync-strategy.md) for comprehensive architecture,
> conflict resolution, and retry logic.

```
Browser Extension (Device A)
  → Create/update workspace locally
    → POST /api/v1/sync/push
      → Cloud Run API
        → Update Neon DB
          → Publish to Pub/Sub (workspace-updates topic)
            → Upstash Redis (update sync state)

Browser Extension (Device B)
  → Polling/WebSocket /api/v1/sync/pull
    → Cloud Run API
      → Check Upstash Redis for updates
        → If updates: fetch from Neon DB
          → Return delta to client
            → Client applies changes locally
```

### Workspace CRUD Operations

**Create Workspace:**

```
Extension Popup
  → User clicks "New Workspace"
    → Fill form (name, description, color, icon)
      → POST /api/v1/workspaces
        → Validate free tier limit (10 workspaces)
          → Insert into workspaces table
            → Return workspace with ID
              → Update local storage
                → Refresh workspace list
```

**Update Workspace:**

```
Extension Popup
  → User clicks "Edit" on workspace
    → Modify workspace properties
      → PUT /api/v1/workspaces/{id}
        → Verify ownership
          → Update workspace in DB
            → Return updated workspace
              → Update local storage
```

**Delete Workspace:**

```
Extension Popup
  → User confirms deletion
    → DELETE /api/v1/workspaces/{id}
      → Verify ownership
        → Cascade delete tabs
          → Remove from workspaces table
            → Return 204 No Content
              → Update local storage
                → Refresh workspace list
```

**Switch Workspace:**

```
Extension Popup
  → User clicks "Switch" on workspace
    → Close current tabs (except pinned)
      → GET /api/v1/workspaces/{id}
        → Retrieve workspace with tabs
          → Open each tab in order
            → Set active workspace ID
              → Update visual indicator
```

### Tab Management Operations

**Save Tabs to Workspace:**

```
Extension Popup
  → User clicks "Save Tabs"
    → Query current window tabs
      → Map to tab format
        → POST /api/v1/workspaces/{id}/tabs
          → Delete existing tabs
            → Insert new tabs in transaction
              → Return updated workspace
                → Update local storage
                  → Show success notification
```

**Move Tab Between Workspaces:**

```
Extension UI (Drag & Drop)
  → User drags tab to different workspace
    → POST /api/v1/workspaces/tabs/move
      → Verify both workspaces owned by user
        → Update tab.workspace_id
          → Update tab.position
            → Return updated tab
              → Refresh workspace displays
```

**Reorder Tabs:**

```
Extension UI (Drag & Drop)
  → User reorders tab within workspace
    → POST /api/v1/workspaces/tabs/reorder
      → Verify tab ownership
        → Update tab.position
          → Return updated tab
            → Update local order
```

**Bulk Tab Operations:**

```
Extension UI
  → User selects multiple tabs
    → Chooses operation (close/pin/unpin)
      → POST /api/v1/workspaces/tabs/bulk
        → Verify all tabs owned by user
          → For close: Delete tabs
          → For pin/unpin: Update isPinned
            → Return operation result
              → Update UI state
```

### Backup Creation Flow

```
Cloud Scheduler (every 6 hours)
  → POST /api/v1/jobs/backup (with OIDC token)
    → Cloud Run API
      → Query active users from Neon
        → For each user:
          → Serialize workspace + tabs state
            → Write to Cloud Storage bucket
              → Update backups table in Neon
                → Publish backup-complete event to Pub/Sub
```

### Search Flow

```
Browser Extension
  → GET /api/v1/search?q=query
    → Cloud Run API
      → Check Upstash Redis cache
        → If miss: Query Neon DB with full-text search
          → Cache results in Upstash (5 min TTL)
            → Return results to client
```

---

## Security Architecture

### Data Protection

**Encryption:**

- TLS 1.3 for all API communications
- Data encrypted at rest in Neon, Cloud Storage
- JWT tokens with short expiration (15 min access, 7 day refresh)
- Secrets stored in Google Secret Manager

**Authentication:**

- Bcrypt password hashing (cost factor: 12)
- JWT with RS256 signing
- Refresh token rotation
- Session invalidation on logout
- IP-based rate limiting

**Authorization:**

- Role-based access control (RBAC)
- User owns their workspaces
- Team admins control team workspaces (Phase 4)
- API endpoints validate ownership before operations

### Network Security

**API Security:**

- CORS with allowlist
- Rate limiting (100 req/min per user)
- Request size limits (1MB max)
- Input validation and sanitization
- SQL injection prevention (parameterized queries)

**Infrastructure:**

- Cloud Run with VPC connector
- Private IPs for database connections
- Service account least-privilege permissions
- Audit logging enabled
- Regular dependency updates

### Privacy

**Data Collection:**

- Minimal: only what's needed for functionality
- No tracking pixels or analytics scripts
- No sale of user data
- User can export all data
- User can delete account (hard delete)

**Compliance:**

- GDPR-ready (EU data residency option)
- SOC 2 Type II providers (Neon, WorkOS)
- Privacy policy and terms of service
- Data retention policies

---

## Scalability & Performance

### Performance Targets

| Metric                          | Target      | Measurement       |
| ------------------------------- | ----------- | ----------------- |
| API Response Time (p95)         | < 200ms     | Cloud Run metrics |
| API Response Time (p99)         | < 500ms     | Cloud Run metrics |
| Database Query Time (p95)       | < 50ms      | Neon metrics      |
| Sync Latency                    | < 1 second  | Custom metric     |
| Extension Memory Usage          | < 50MB      | Chrome DevTools   |
| Time to Interactive (Dashboard) | < 2 seconds | Lighthouse        |
| Uptime                          | 99.9%       | Uptime monitoring |

### Scaling Strategy

**Horizontal Scaling:**

- Cloud Run: Auto-scales instances based on request volume
- Neon: Auto-scales compute units (0.25 - 2 CU)
- Upstash: Scales automatically with usage

**Caching Strategy:**

- Upstash Redis for hot data (user sessions, sync state)
- Cloudflare CDN for static assets
- Browser caching for dashboard resources
- API response caching for search results

**Database Optimization:**

- Indexes on frequently queried columns
- Partitioning for backups table by date
- Read replicas for read-heavy operations (future)
- Connection pooling in Cloud Run

**Cost Optimization:**

- Scale-to-zero Cloud Run instances
- Autosuspend Neon database after 5 min idle
- Lifecycle policies on Cloud Storage
- Cloudflare free tier for CDN
- Monitor free tier usage alerts

---

## Disaster Recovery

### Backup Strategy

**Database Backups:**

- Neon automatic backups (built-in)
- Point-in-time recovery up to 7 days
- Manual snapshots before major migrations
- Export to Cloud Storage weekly

**Application Backups:**

- User workspace backups (automatic, every 6 hours)
- Retention: 30 days (free), 90 days (pro)
- Incremental backups to minimize storage

**Configuration Backups:**

- Terraform state in Cloud Storage backend
- Infrastructure as Code in Git
- Secret backup procedure documented

### Recovery Procedures

**Database Recovery:**

1. Restore from Neon point-in-time recovery
2. If Neon unavailable: restore from weekly Cloud Storage export
3. RPO: 1 hour, RTO: 4 hours

**API Recovery:**

1. Rollback Cloud Run deployment
2. Redeploy from known-good image
3. RPO: 0 (stateless), RTO: 15 minutes

**Complete System Recovery:**

1. Run Terraform apply from clean state
2. Restore database from backup
3. Verify all services healthy
4. Total RTO: 8 hours (worst case)

---

## Monitoring & Observability

### Logging

**Application Logs:**

- Structured JSON logging
- Log levels: DEBUG, INFO, WARN, ERROR
- Sent to Cloud Logging
- Retention: 30 days

**Access Logs:**

- Cloud Run automatic logging
- Includes request/response details
- Used for security auditing

### Metrics

**Key Metrics:**

- Request rate, latency, error rate (Cloud Run)
- Database connections, query time (Neon)
- Cache hit rate (Upstash)
- Storage usage (Cloud Storage)
- User sign-ups, DAU, MAU (custom)

**Dashboards:**

- Cloud Monitoring dashboard
- Custom Grafana dashboard (optional)
- Real-time alerts via email/Slack

### Alerts

**Critical Alerts:**

- API error rate > 1%
- API latency p95 > 1 second
- Database connection failures
- Storage quota > 80%
- Free tier limits approaching

**Warning Alerts:**

- API latency p95 > 500ms
- Database query time > 100ms
- Cache miss rate > 50%
- Unusual traffic patterns

---

## Development & Deployment

### Environments

**Development:**

- Neon dev branch (separate compute, same data)
- Cloud Run dev service
- Separate GCP project or namespaced resources
- Local Docker development

**Staging:**

- Hosted in the **Development GCP Project** (`tabula-dev-xxx`)
- Deployed as a separate Cloud Run service (`tabula-api-stg`)
- Shares the `development` Neon database branch and secrets
- Deployed imperatively via CI/CD (not Terraform)
- Used for pre-production testing and integration verification

**Production:**

- Main Neon branch
- Cloud Run production service
- Protected branch deployments

### CI/CD Pipeline

**Build:**

1. Run linters (ESLint, Go fmt)
2. Run tests (unit, integration)
3. Build Docker image
4. Push to Artifact Registry

**Deploy:**

1. Terraform plan review
2. Deploy infrastructure changes
3. Deploy Cloud Run service
4. Run smoke tests
5. Monitor metrics

**Rollback:**

- Cloud Run supports traffic splitting
- Instant rollback to previous revision
- Database migrations require manual review

---

## Technology Stack Summary

### Frontend

- **Browser Extension**: JavaScript/TypeScript, Manifest V3
- **Web Dashboard**: Next.js 14, React 18, TypeScript, Tailwind CSS
- **State Management**: React Context / Zustand
- **HTTP Client**: Fetch API / Axios

### Backend

- **API**: Go (Gin framework) or Node.js (Fastify)
- **Database ORM**: GORM (Go) or Prisma (Node.js)
- **Authentication**: JWT (golang-jwt or jsonwebtoken)
- **Validation**: Go validator or Zod (TS)

### Infrastructure

- **IaC**: Terraform 1.6+
- **Container**: Docker
- **CI/CD**: GitHub Actions
- **Secrets**: Google Secret Manager
- **Monitoring**: Google Cloud Monitoring

### Third-Party Services

- **Database**: Neon Postgres 16
- **Cache**: Upstash Redis
- **Auth**: WorkOS (Phase 4)
- **CDN**: Cloudflare
- **Email**: SendGrid or AWS SES

---

## Future Architecture Considerations

### Phase 4+ Enhancements

**Performance:**

- Add read replicas for Neon (if needed)
- Implement GraphQL for flexible querying
- Server-side rendered pages for SEO
- Service worker for offline PWA

**Features:**

- WebSocket connections for real-time sync (replace polling)
- ElasticSearch for advanced search (if needed)
- Queue system (Cloud Tasks) for heavy operations
- Webhook delivery system

**Scale:**

- Multi-region deployment
- Database sharding by user ID
- Separate read/write API services
- Microservices architecture (if complexity warrants)

**Observability:**

- Distributed tracing (Cloud Trace)
- Application Performance Monitoring (APM)
- Custom analytics dashboard
- User session replay (optional)

---

## Conclusion

This architecture is designed to:

1. Minimize operational costs through free tiers and scale-to-zero
2. Provide excellent performance through caching and CDN
3. Scale seamlessly from 0 to 100K+ users
4. Maintain security and privacy standards
5. Enable rapid development and deployment

The lean architecture ensures Tabula can compete with Workona on features while maintaining
significantly lower operational costs, enabling competitive pricing and sustainable growth.

---

_Architecture Version: 1.0_  
_Last Updated: 2025-12-07_  
_Next Review: 2025-03-07 (or when hitting 1,000 users)_
