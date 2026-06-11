# @tabula/shared

Shared types and utilities for Tabula packages.

## Overview

This package provides TypeScript type definitions that are shared between the extension and web
dashboard packages. It serves as the **single source of truth** for core data structures like
`Workspace`, `Tab`, `Resource`, `Note`, and `Task`.

## Installation

This is an internal npm workspace package. It's automatically linked when you run `npm install` from
the repository root.

## Usage

```typescript
import { Workspace, Tab, WorkspaceStats } from '@tabula/shared';

// Types can be used for function signatures, state, etc.
function processWorkspace(workspace: Workspace): void {
  workspace.tabs.forEach((tab: Tab) => {
    console.log(tab.title);
  });
}
```

## Package Contents

### Types

| Type                | Description                                                 |
| ------------------- | ----------------------------------------------------------- |
| `Workspace`         | Core workspace structure with tabs, resources, notes, tasks |
| `Tab`               | Browser tab representation                                  |
| `Resource`          | Saved resource/bookmark                                     |
| `Section`           | Resource grouping container                                 |
| `Note`              | Workspace note                                              |
| `Task`              | Workspace task item                                         |
| `SpaceGroup`        | Sidebar group for organizing workspaces                     |
| `WorkspaceStats`    | Aggregate statistics across workspaces                      |
| `DataSourceInfo`    | Storage context information                                 |
| `UserProfile`       | User account information                                    |
| `ExtensionSettings` | Extension configuration                                     |

## Testing Strategy

This package contains **only TypeScript type definitions** with no runtime code. Therefore:

- **No unit tests are needed** - there's no logic to test
- **TypeScript compiler is the validation** - invalid types fail at compile time
- **Consumer tests validate usage** - extension and web tests implicitly validate types

### When to Add Tests

Add tests to this package if you introduce:

- Utility functions (e.g., `formatWorkspaceName()`)
- Validation logic (e.g., `isValidWorkspace()`)
- Runtime transformations (e.g., `serializeWorkspace()`)
- Computed constants or derived values

### Example

If adding a utility function:

```typescript
// src/utils/stats.ts
export function calculateCompletionRate(stats: WorkspaceStats): number {
  if (stats.totalTasks === 0) return 0;
  return Math.round((stats.completedTasks / stats.totalTasks) * 100);
}
```

Add a corresponding test:

```typescript
// src/utils/stats.test.ts
describe('calculateCompletionRate', () => {
  it('returns 0 when no tasks exist', () => {
    expect(calculateCompletionRate({ totalTasks: 0, completedTasks: 0, ... })).toBe(0);
  });

  it('calculates percentage correctly', () => {
    expect(calculateCompletionRate({ totalTasks: 10, completedTasks: 7, ... })).toBe(70);
  });
});
```

## Development

```bash
# Build the package (required before other packages can use it)
npm run build -w shared

# Type check
npm run typecheck -w shared
```

## Architecture Note

This package is built before lint, typecheck, and test steps in CI to ensure the type declarations
are available to consuming packages. See `.github/workflows/ci.yml` for details.
