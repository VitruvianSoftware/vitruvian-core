# ADR-002: Database and ORM Selection

**Status:** Accepted  
**Date:** 2025-12-07  
**Deciders:** Tabula Core Team

## Context

Tabula needs a database solution that:

- Supports relational data (users, workspaces, tabs, sessions)
- Scales from zero to thousands of users cost-effectively
- Provides strong consistency for user data
- Supports complex queries (search, filtering)
- Integrates well with TypeScript backend
- Offers serverless/autoscaling capabilities

We also need an ORM or query builder that provides:

- Type safety with TypeScript
- Migration management
- Good developer experience
- Performance

## Decision

We will use:

**Database:** Neon PostgreSQL

- Serverless PostgreSQL with autoscaling
- Scales to zero when idle (cost optimization)
- 0.5 GB free tier
- PostgreSQL 16 compatibility

**ORM:** Prisma

- Type-safe database client for TypeScript
- Declarative schema definition
- Automatic migrations
- Excellent TypeScript integration
- Built-in connection pooling

## Consequences

### Positive

1. **Type Safety:**
   - Prisma generates fully typed database client
   - Compile-time checks for queries
   - IntelliSense support in IDE
   - Reduced runtime errors

2. **Developer Experience:**
   - Declarative schema in Prisma Schema Language
   - Simple, intuitive API
   - Great documentation and community
   - Built-in Prisma Studio for database inspection

3. **Migration Management:**
   - Automatic migration generation
   - Migration history tracking
   - Easy rollback capabilities
   - Works well with CI/CD

4. **Cost Efficiency:**
   - Neon scales to zero (no idle costs)
   - Free tier covers initial development
   - Autoscaling matches usage to cost

5. **Performance:**
   - PostgreSQL query optimization
   - Prisma query optimization
   - Connection pooling built-in
   - Efficient for our relational data model

6. **Neon Features:**
   - Branching for dev/test environments
   - Point-in-time recovery
   - Autosuspend after inactivity
   - Instant provisioning

### Negative

1. **Vendor Lock-in:**
   - Neon-specific features (branching)
   - Mitigated: PostgreSQL standard, can migrate to other providers

2. **Prisma Overhead:**
   - Small performance overhead vs raw SQL
   - Acceptable trade-off for type safety

3. **Neon Limitations:**
   - Regional availability (US-centric)
   - Cold start latency after autosuspend
   - Mitigated: Acceptable for our scale, can move to always-on later

### Neutral

1. **Learning Curve:** Prisma is easy to learn
2. **Maturity:** Both Prisma and Neon are production-ready

## Alternatives Considered

### Alternative 1: Supabase (PostgreSQL)

**Pros:**

- PostgreSQL with additional features
- Real-time subscriptions
- Built-in auth and storage
- Generous free tier

**Cons:**

- More opinionated (includes auth, storage)
- We prefer WorkOS for auth (Phase 4)
- Additional features we don't need
- Less focus on serverless autoscaling

**Why not chosen:** Too many features we don't need; prefer specialized solutions.

### Alternative 2: PlanetScale (MySQL)

**Pros:**

- Serverless MySQL
- Branching workflow
- Good free tier
- Non-blocking schema changes

**Cons:**

- MySQL instead of PostgreSQL
- Less feature-rich than PostgreSQL
- JSON support not as robust
- Prisma works better with PostgreSQL

**Why not chosen:** PostgreSQL has better features for our needs (JSONB, full-text search).

### Alternative 3: MongoDB Atlas

**Pros:**

- Document database
- Flexible schema
- Good free tier
- Managed service

**Cons:**

- NoSQL paradigm less suitable for relational data
- Weaker consistency guarantees
- Less suitable for complex queries
- Prisma support for MongoDB is limited

**Why not chosen:** Relational model better fits our data (users, workspaces, tabs).

### Alternative 4: TypeORM

**Pros:**

- Mature ORM for TypeScript
- Active Record and Data Mapper patterns
- Good migration support

**Cons:**

- Less type-safe than Prisma
- More boilerplate code
- Decorators can be verbose
- Active development concerns

**Why not chosen:** Prisma provides better type safety and developer experience.

### Alternative 5: Drizzle ORM

**Pros:**

- Lightweight
- SQL-like syntax
- Good TypeScript support
- Performance-focused

**Cons:**

- Relatively new
- Smaller community
- Less mature ecosystem
- Fewer examples and resources

**Why not chosen:** Prisma has better documentation and larger community.

### Alternative 6: Knex.js

**Pros:**

- Flexible query builder
- No ORM overhead
- Raw SQL access

**Cons:**

- No type safety out of the box
- Manual type definitions needed
- More boilerplate
- No automatic migrations

**Why not chosen:** Lack of type safety reduces developer productivity.

## Implementation Details

### Schema Definition

```prisma
// Example from schema.prisma
model User {
  id           String    @id @default(uuid())
  email        String    @unique
  passwordHash String?
  workspaces   Workspace[]
}
```

### Migration Workflow

1. Update schema in `schema.prisma`
2. Run `npx prisma migrate dev --name <description>`
3. Prisma generates migration files
4. Commit migration files to git
5. Deploy runs `npx prisma migrate deploy`

### Connection Pooling

Prisma Accelerate can be added later if connection pooling becomes an issue:

- Edge caching
- Connection pooling
- Query caching

## References

- [Prisma Documentation](https://www.prisma.io/docs)
- [Neon Documentation](https://neon.tech/docs)
- [Prisma vs TypeORM Comparison](https://www.prisma.io/docs/concepts/more/comparisons/prisma-and-typeorm)
- [PostgreSQL vs MySQL for JSON](https://www.postgresql.org/docs/current/datatype-json.html)
