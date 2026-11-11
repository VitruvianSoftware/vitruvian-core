# Catalog

## Overview
Component package providing implementation for `apps/web/backstage/packages/backend/src/catalog`.

## Interface
- `[actionsModule.ts:registerCatalogMcpActions]`
- `[actionsModule.ts:catalogModuleMcpActions]`

## Invariants
- None

## Side Effects
- [actionsModule.test.ts:35]: `return Promise.resolve(`http://${pluginId}.local`);`
- [actionsModule.test.ts:37]: `getExternalBaseUrl: jest.fn().mockResolvedValue("http://catalog.local"),`
- [actionsModule.test.ts:103]: `// 4. query_catalog_entities — advanced query with pagination/sorting`
- [actionsModule.ts:247]: `// Gemini-safe re-implementation of upstream query-catalog-entities.`
- [actionsModule.ts:254]: `title: "Query Catalog Entities",`
- [actionsModule.ts:255]: `description: `Query entities from the Backstage Software Catalog with paginat...`

## Verification
- Run: `bazel test //apps/web/backstage/packages/backend/src/catalog/...`
