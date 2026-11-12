# Dashboard

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/extension/src/dashboard`.

## Interface
- `[CommandPalette.tsx:SearchResult]`
- `[CommandPalette.tsx:CommandPalette]`
- `[ConfirmModal.tsx:ConfirmModalProps]`
- `[ConfirmModal.tsx:ConfirmModal]`
- `[Dashboard.tsx:Dashboard]`
- `[DraggableTabItem.tsx:DraggableTabItemProps]`
- `[DraggableTabItem.tsx:DraggableTabItem]`
- `[DroppableContainer.tsx:DroppableContainerProps]`
- `[DroppableContainer.tsx:DroppableContainer]`
- `[GhostOverlay.tsx:GhostOverlay]`
- `[MenuOverlay.tsx:MenuOverlay]`
- `[NotesPanel.tsx:NotesPanelProps]`
- `[NotesPanel.tsx:NotesPanel]`
- `[OpenTabsPanel.tsx:OpenTabsPanelProps]`
- `[OpenTabsPanel.tsx:OpenTabsPanel]`
- `[ResourceSection.tsx:ResourceSectionProps]`
- `[ResourceSection.tsx:ResourceSection]`
- `[SidebarGroupHeader.tsx:SidebarGroupHeaderProps]`
- `[SidebarGroupHeader.tsx:SidebarGroupHeader]`
- `[SidebarHeader.tsx:SidebarHeaderProps]`
- Subdirectory: [hooks](./hooks/README.md)

## Invariants
- [index.test.tsx:27]: `declare let require: any;`
- [index.test.tsx:63]: `// Require the index file to trigger execution`
- [index.test.tsx:64]: `require("./index");`

## Side Effects
- [CommandPalette.test.tsx:140]: `it("should filter results based on search query", async () => {`
- [CommandPalette.tsx:209]: `// Filter and rank results based on search query`
- [CommandPalette.tsx:219]: `return results.slice(0, 50); // Show first 50 results when no query`
- [CommandPalette.tsx:222]: `const query = searchQuery.toLowerCase();`
- [DraggableTabItem.test.tsx:97]: `// Note: Google favicon fallback test skipped - DOM query with empty alt is u...`
- [MoveToSection.test.tsx:74]: `query: jest.fn().mockResolvedValue([]),`
- [MoveToSection.test.tsx:81]: `query: jest.fn().mockResolvedValue([]),`
- [SidebarGroupHeader.test.tsx:85]: `// Since it's an inline style div, we can't easily query by role, so we check...`
- [SortableResourceItem.test.tsx:98]: `// Note: Google favicon fallback test skipped - DOM query with empty alt is u...`

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/extension/src/dashboard/...`
