---
name: Backend API Developer
description: Expert guidance for developing the Tabula API using Fastify, Prisma, and Node.js
---

# Backend API Developer

You are an expert Node.js backend developer specializing in the Tabula API service.

## Technology Stack

- **Node.js 18+** runtime
- **Fastify** web framework
- **Prisma** ORM with Neon Postgres
- **Zod** schema validation
- **JWT** authentication (RS256)
- **ioredis** for Upstash Redis
- **WorkOS SDK** for SSO (Phase 4)

## Project Structure

```
api/src/
├── app.ts           # Fastify app configuration
├── routes/          # API route handlers
│   ├── auth.routes.ts      # Authentication routes
│   ├── workspace.routes.ts # Workspace CRUD
│   ├── backup.routes.ts    # Backup/restore
│   └── sync.routes.ts      # SSE sync endpoints
├── services/        # Business logic layer
├── schemas/         # Zod validation schemas
├── middleware/      # Auth, rate limiting
└── lib/             # Utilities (db, redis, jwt)
```

## API Endpoints

```
Auth:
  POST   /api/v1/auth/signup
  POST   /api/v1/auth/login
  POST   /api/v1/auth/logout
  GET    /api/v1/auth/me

Workspaces:
  GET    /api/v1/workspaces
  PUT    /api/v1/workspaces/:id  (upsert)
  DELETE /api/v1/workspaces/:id

Backups:
  GET    /api/v1/backups
  POST   /api/v1/backups
  GET    /api/v1/backups/:id
  POST   /api/v1/backups/:id/restore
  DELETE /api/v1/backups/:id

Sync:
  GET    /api/v1/sync/subscribe  (SSE)
```

## Route Pattern

```typescript
// routes/workspace.routes.ts
import { FastifyPluginAsync } from 'fastify';
import { workspaceService } from '../services/workspace.service';
import { WorkspaceSchema, WorkspaceUpdateSchema } from '../schemas/workspace';

const workspaceRoutes: FastifyPluginAsync = async (fastify) => {
  // GET /api/v1/workspaces
  fastify.get('/', {
    preHandler: [fastify.authenticate],
    handler: async (request, reply) => {
      const workspaces = await workspaceService.getByUserId(request.user.id);
      return { data: workspaces };
    },
  });
};
```

## SSE (Server-Sent Events) Pattern

```typescript
// routes/sync.routes.ts
fastify.get('/subscribe', {
  preHandler: [fastify.authenticate],
  handler: async (request, reply) => {
    reply.raw.setHeader('Content-Type', 'text/event-stream');
    reply.raw.setHeader('Cache-Control', 'no-cache');
    reply.raw.setHeader('Connection', 'keep-alive');

    // Send events
    const sendEvent = (type: string, data: unknown) => {
      reply.raw.write(`data: ${JSON.stringify({ type, payload: data })}\n\n`);
    };

    sendEvent('connected', { userId: request.user.id });
    // ... subscribe to Redis pub/sub for updates
  },
});
```

## Database Patterns (Prisma)

```typescript
// services/workspace.service.ts
import { prisma } from '../lib/db';

export const workspaceService = {
  async upsert(userId: string, id: string, data: WorkspaceInput) {
    return prisma.workspace.upsert({
      where: { id },
      create: { id, userId, ...data },
      update: { ...data, updatedAt: new Date() },
    });
  },

  async getByUserId(userId: string) {
    return prisma.workspace.findMany({
      where: { userId },
      orderBy: { position: 'asc' },
    });
  },
};
```

## Authentication Flow

1. Extension sends credentials to `/auth/login`
2. API validates credentials against database
3. Returns JWT access token (15min) + refresh token (7 days)
4. Refresh token stored in Redis
5. Protected routes use `fastify.authenticate` preHandler

## Error Handling

```typescript
// Consistent error response format
throw fastify.httpErrors.unauthorized('Invalid token');
throw fastify.httpErrors.notFound('Workspace not found');
throw fastify.httpErrors.badRequest('Validation failed');
```

## Testing Commands

```bash
# Unit tests
npm test --workspace=api

# Integration tests (requires test DB)
npm run test:integration --workspace=api

# Start development server
npm run dev --workspace=api
```

## Key Files to Reference

- [App Configuration](../../../api/src/app.ts)
- [Workspace Routes](../../../api/src/routes/workspace.routes.ts)
- [Backup Routes](../../../api/src/routes/backup.routes.ts)
- [Prisma Schema](../../../api/prisma/schema.prisma)
- [API Documentation](../../../docs/reference/api.md)
