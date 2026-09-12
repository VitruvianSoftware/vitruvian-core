# Insert-above tab-group drop zones — design reference

Salvaged WIP from the (now-deleted) `BlueCentre/tabula` local clone, stash `ux`.
Preserved here as a **design reference**, alongside the companion patch
[`insert-above-tab-group.reference.patch`](./insert-above-tab-group.reference.patch).

## What it contains

Tab-group "insert-above" drop zones + colored group left-borders, touching:

- `extension/src/dashboard/OpenTabsPanel.tsx`
- `extension/src/dashboard/DraggableTabItem.tsx`
- `extension/src/dashboard/hooks/useDragAndDrop.ts`
- `extension/src/services/tabs.ts` — `addTabToGroup` / `removeTabFromGroup` are
  now redundant (already upstream) but harmless.

## Caveat

Written against tabula commit `853abf2`, **before** the concurrency-hardening
rewrite of these files. It will **not** apply cleanly to the migrated code under
`tabula/extension/...`. Treat it as a reference for re-implementing the feature,
not a drop-in patch.

The current code lives at `tabula/extension/src/dashboard/...` in this repo.
