# ADR-001: Technology Stack Selection

**Status:** Accepted  
**Date:** 2025-12-07  
**Deciders:** Tabula Core Team

## Context

Tabula requires a full-stack technology solution that supports:

- Browser extension development (Chrome, Edge, Firefox)
- Backend API for data synchronization and storage
- Web dashboard for browser-based access (Phase 2)
- AI-assisted development with LLMs (Claude Opus 4.5, Gemini 3 Pro)
- Cost-effective serverless deployment
- Developer productivity and maintainability

The browser extension is already specified to use TypeScript/JavaScript with Manifest V3. We need to
decide on the backend technology stack.

## Decision

We will use **TypeScript with Node.js** for the entire stack:

**Backend:**

- **Runtime:** Node.js 18+
- **Framework:** Fastify (high-performance, TypeScript-first)
- **Language:** TypeScript with strict mode
- **ORM:** Prisma (type-safe database access)

**Frontend (Extension):**

- **Language:** TypeScript
- **UI Framework:** React 18
- **State Management:** Zustand
- **Build Tool:** Webpack

**Frontend (Web Dashboard - Phase 2):**

- **Framework:** Next.js 14
- **Language:** TypeScript
- **Styling:** Tailwind CSS

## Consequences

### Positive

1. **Language Consistency:** Single language (TypeScript) across the entire codebase
   - Easier context switching for developers
   - Shared type definitions between frontend and backend
   - Reusable validation logic and utilities

2. **AI Model Compatibility:** Excellent LLM support
   - TypeScript has extensive training data in AI models
   - Clear type definitions improve code understanding
   - Rich ecosystem with well-documented patterns

3. **Developer Experience:**
   - Unified toolchain (npm/yarn, ESLint, Prettier)
   - Strong IDE support (VS Code, WebStorm)
   - Large talent pool familiar with JavaScript/TypeScript

4. **Performance:** Node.js with Fastify provides excellent performance
   - Event-driven architecture suits real-time sync
   - Fastify benchmarks well against alternatives
   - Efficient for I/O-heavy operations

5. **Ecosystem:** Rich package ecosystem
   - Prisma for type-safe database access
   - Jest for testing
   - Extensive libraries for all needs

6. **Deployment:** Great serverless support
   - Cloud Run supports Node.js containers
   - Fast cold starts compared to JVM-based alternatives
   - Efficient memory usage

### Negative

1. **Type Safety:** Not as strict as compiled languages (Go, Rust)
   - Mitigated by TypeScript strict mode
   - Runtime validation with Zod

2. **Performance Ceiling:** Not as fast as Go or Rust for CPU-intensive tasks
   - Acceptable for our I/O-heavy workload
   - Vast majority of time spent on database/network operations

3. **Dependency Management:** npm ecosystem can have security issues
   - Mitigated with automated dependency updates (Dependabot)
   - Regular security audits

### Neutral

1. **Learning Curve:** Most developers know JavaScript
2. **Maturity:** Well-established ecosystem with proven patterns

## Alternatives Considered

### Alternative 1: Go

**Pros:**

- Excellent performance
- Built-in concurrency
- Single binary deployment
- Strong typing

**Cons:**

- Different language from extension (context switching)
- Less AI model training data than TypeScript
- Smaller ecosystem for web development
- Cannot share types with frontend

**Why not chosen:** Language inconsistency with extension outweighs performance benefits for our use
case.

### Alternative 2: Python (FastAPI)

**Pros:**

- Excellent AI tooling
- Fast development
- Great for data processing

**Cons:**

- Different language from extension
- Slower runtime performance
- Less suitable for real-time applications
- GIL limitations for concurrency

**Why not chosen:** Performance concerns and language inconsistency.

### Alternative 3: Rust

**Pros:**

- Maximum performance
- Memory safety
- No garbage collection

**Cons:**

- Steep learning curve
- Slower development velocity
- Different language from extension
- Smaller web framework ecosystem

**Why not chosen:** Complexity and development speed trade-offs not justified for our scale.

## References

- [Fastify Benchmarks](https://www.fastify.io/benchmarks/)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
- [Prisma Documentation](https://www.prisma.io/docs)
- [Node.js on Cloud Run](https://cloud.google.com/run/docs/quickstarts/build-and-deploy/deploy-nodejs-service)
