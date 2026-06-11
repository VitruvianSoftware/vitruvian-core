# Tabula

> A lean, privacy-conscious browser tab management extension with cloud sync

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.3-blue.svg)](https://www.typescriptlang.org/)
[![Node.js](https://img.shields.io/badge/Node.js-18+-green.svg)](https://nodejs.org/)

## What is Tabula?

Tabula is a browser tab management extension designed to help you organize your digital workspace
without breaking the bank or compromising on performance. Inspired by tools like Workona, Tabula
offers workspace-based tab organization, automatic saving, cross-device sync, and smart tab
suspension — all built on a cost-effective, serverless cloud architecture.

**Key Differentiators:**

- 🎯 **Performance-First**: Lightweight extension with minimal memory footprint (< 50MB)
- 🪟 **Multi-Window Native**: Open different workspaces in different windows (like Workona)
- 🔗 **Local-First Sharing**: Share workspaces with public links without compromising privacy
- 💰 **Cost-Effective**: Competitive pricing enabled by modern cloud free tiers
- 🔒 **Privacy-Conscious**: Minimal data collection, transparent handling
- ⚡ **Scale-to-Zero Architecture**: Efficient serverless backend with Neon, Cloud Run, and Upstash

## Features

### Current Features (Planned for Phase 1 - MVP)

- **Workspace Management**
  - Create, rename, and delete workspaces
  - Up to 10 workspaces on free tier (2x competitors)
  - Quick workspace switching
  - Visual workspace indicators

- **Tab Management**
  - Save and restore tabs within workspaces
  - Suspend inactive tabs to save memory
  - Move tabs between workspaces
  - Drag-and-drop tab reordering

- **User Authentication**
  - Email/password sign-up and login
  - Secure session management
  - Account settings and password reset

- **Cross-Device Sync**
  - Local browser storage for offline access
  - Cloud sync for logged-in users
  - Conflict resolution for multi-device usage

### Planned Features

See our [Product Roadmap](./docs/product/roadmap.md) for detailed phase breakdowns:

**Phase 2: Sync & History** (Months 4-6)

- Real-time cross-device synchronization
- Multi-Window Workspaces (URL-based state)
- "Relay" Sharing (Local-First Public Links)
- 30-day backup history (free) / 90-day (pro)
- Universal search across workspaces
- Web dashboard for browser-based access

**Phase 3: Integrations & Pro Features** (Months 7-10)

- Cloud document links (Google Drive, Notion, GitHub, Figma)
- Workspace templates and marketplace
- Advanced productivity features (focus mode, time tracking)
- Import/export from other tools

**Phase 4: Team Features & Enterprise** (Months 11-15)

- Shared workspaces for teams
- SSO and SCIM for enterprise
- Admin controls and user management
- API access for custom integrations

## Tech Stack

### Frontend

- **Browser Extension**: TypeScript, Manifest V3, React 18, Zustand
- **Web Dashboard**: Next.js 14, React 18, Tailwind CSS (Phase 2)

### Backend

- **API**: Node.js 18+ with Fastify
- **Language**: TypeScript with strict mode
- **Database**: Neon Postgres (serverless, autoscaling)
- **ORM**: Prisma (type-safe database access)
- **Cache**: Upstash Redis (serverless, edge-optimized)
- **Auth**: JWT with bcrypt (Phase 1-3), WorkOS SSO (Phase 4)

### Infrastructure

- **Compute**: Google Cloud Run (scale-to-zero)
- **Storage**: Google Cloud Storage (backups, assets)
- **Scheduler**: Google Cloud Scheduler (background jobs)
- **Messaging**: Google Pub/Sub (real-time sync)
- **CDN**: Cloudflare (static assets)
- **IaC**: Terraform

See [Architecture Documentation](./docs/architecture/overview.md) for detailed system design.

## Quick Start

### For Users

**Installation** (Coming Soon):

1. Visit Chrome Web Store (link TBD)
2. Click "Add to Chrome"
3. Sign up or log in
4. Start organizing your tabs!

### For Developers

Tabula lives in the vitruvian-core Bazel monorepo; all builds and tests are
Bazel targets.

**Build everything:**

```bash
bazel build //tabula/...
```

**Run the test suites:**

```bash
# Unit + hermetic integration tests (Postgres/Redis/migrations are
# Bazel-managed test services; nothing to install or start)
bazel test //tabula/...

# Extension E2E (Playwright + headless Chromium against the full stack)
bazel test --config=e2e //tabula/...

# Coverage with threshold enforcement
bazel coverage //tabula/...
```

**Run the API locally:**

```bash
bazel run //tabula/api:api_bin
```

**Build the extension and load it in Chrome:**

```bash
bazel build //tabula/extension:dist
```

1. Navigate to `chrome://extensions/`
2. Enable "Developer mode"
3. Click "Load unpacked"
4. Select `bazel-bin/tabula/extension/dist`

**Operations CLI (auth, WorkOS, db, config):**

```bash
bazel run //tabula/cli:tabcli -- --help
```

**Deploy to staging** happens automatically on merge to `main`
(`.github/workflows/tabula-deploy-staging.yaml`: Bazel image -> Artifact
Registry -> prisma migrate -> Pulumi). Manual rollout:

```bash
bazel run //infrastructure/pulumi/tabula:up
```

See [docs/tabula](../docs/tabula) for the full documentation set.

## Project Structure

```bash
tabula/
 ├── docs/ # Documentation
 │    ├── README.md # Documentation overview
 │    ├── PRODUCT_ANALYSIS.md # Competitive analysis
 │    ├── ROADMAP.md # Product roadmap
 │    └── ARCHITECTURE.md # System architecture
 ├── infrastructure/ # Terraform IaC
 │    ├── modules/ # Reusable Terraform modules
 │    ├── environments/ # Environment-specific configs
 │    └── README.md # Infrastructure setup guide
 ├── extension/ # Browser extension (coming soon)
 ├── api/ # Backend API (coming soon)
 ├── web/ # Web dashboard (coming soon)
 ├── README.md # This file
 ├── CONTRIBUTING.md # Contribution guidelines
 ├── LICENSE # MIT License
 └── .gitignore # Git ignore rules
```

## Documentation

- **[Product Analysis](./docs/product/analysis.md)**: Competitive analysis of Workona and market
  positioning
- **[Roadmap](./docs/product/roadmap.md)**: Product development phases and features
- **[Architecture](./docs/architecture/overview.md)**: System design, service selection, and data
  flow
- **[Infrastructure](./docs/reference/infrastructure.md)**: Terraform setup and deployment guide
- **[Contributing](./CONTRIBUTING.md)**: How to contribute to Tabula

## Pricing (Planned)

| Tier     | Price            | Features                                                        |
| -------- | ---------------- | --------------------------------------------------------------- |
| **Free** | $0/forever       | 10 workspaces, 30-day backups, basic sync, cross-device access  |
| **Pro**  | $4.99/month      | Unlimited workspaces, 90-day backups, integrations, templates   |
| **Team** | $6.99/user/month | All Pro features + shared workspaces, SSO, SCIM, admin controls |

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](./CONTRIBUTING.md) for details
on:

- Code of conduct
- Development setup
- Pull request process
- Coding standards

## License

Tabula is open source software licensed under the [MIT License](./LICENSE).

## Support

- **Documentation**: [/docs](./docs)
- **Issues**: [GitHub Issues](https://github.com/BlueCentre/tabula/issues)
- **Discussions**: [GitHub Discussions](https://github.com/BlueCentre/tabula/discussions)

## Roadmap Status

- [x] Project initialization and documentation
- [x] Infrastructure as Code (Terraform)
- [ ] Phase 1: MVP (Months 1-3)
  - [ ] Chrome extension development
  - [ ] Backend API
  - [ ] User authentication
  - [ ] Basic workspace and tab management
- [ ] Phase 2: Sync & History (Months 4-6)
- [ ] Phase 3: Integrations (Months 7-10)
- [ ] Phase 4: Team Features (Months 11-15)

See [Roadmap](./docs/product/roadmap.md) for detailed timelines and features.

## Acknowledgments

Tabula is built with modern, open-source technologies and leverages generous free tiers from:

- [Neon](https://neon.tech) - Serverless Postgres
- [Upstash](https://upstash.com) - Serverless Redis
- [Google Cloud](https://cloud.google.com) - Cloud Run, Storage, Scheduler
- [WorkOS](https://workos.com) - Enterprise authentication
- [Cloudflare](https://cloudflare.com) - CDN and edge services

---

**Built with ❤️ by the Tabula team**
