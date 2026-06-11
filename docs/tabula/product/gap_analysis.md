# Gap Analysis: Workona vs. Tabula

## Executive Summary

Tabula has successfully implemented the core structural features of Workona: Spaces, Resources (with
sections), Notes, Tasks, and basic Sidebar organization. The primary gaps lie in **User Experience
(UX) Polish**, **Advanced Organization (Space Grouping Strategy)**, **Global Search**, and the
**"Premium" feel** (animations, empty states, micro-interactions).

| Feature Area         | Workona Status                     | Tabula Status                                                 | Priority |
| :------------------- | :--------------------------------- | :------------------------------------------------------------ | :------- |
| **Workspace Basics** | Mature (Colors, Rename, Archive)   | Functional (Rename implemented, Colors verified)              | Low      |
| **Sidebar Org**      | Drag & Drop, Sections              | **Parity Achieved** (Drag & Drop + Move to Group implemented) | Done     |
| **Resources**        | Sections, Drag & Drop              | **Parity Achieved** (Sections + Drag & Drop implemented)      | Done     |
| **Search**           | Global Command Bar (Cmd+K)         | **Implemented** (Command Palette with Cmd+K)                  | Done     |
| **Aesthetics**       | Smooth transitions, refined modals | Functional, standard UI components                            | **High** |
| **Sharing**          | Full Sharing/Collab                | UI Placeholder only                                           | Medium   |

---

## 1. High Priority Gaps

### A. Global Search (Command Bar)

**Gap**: Workona allows users to instantly find any workspace or resource via a global command
palette. Tabula currently requires manual navigation. **Impact**: High friction as the number of
spaces grows.

#### Implementation Plan

1.  **Component**: Create `CommandPalette.tsx` using `cmdk` or a custom lightweight implementation.
2.  **Indexing**: Hook into `WorkspaceStore` to flatten all workspaces, resources, and tabs into a
    searchable index.
3.  **Trigger**: Global keyboard shortcut (Cmd+K).
4.  **Actions**: Navigate to workspace, Open resource, Switch tab.

### B. "Premium" UX & Micro-interactions

**Gap**: Workona feels "alive" with hover states, smooth modal animations, and instant feedback.
Tabula relies on standard browser alerts/prompts for some actions (e.g. renaming) or simple toggles.
**Impact**: Perceived quality and user delight.

#### Implementation Plan

1.  **Replace Prompts**: Replace `window.prompt` for renaming with a custom, inline editable
    component or a sleek Modal.
2.  **Animations**: Add `framer-motion` (or CSS transitions) for:
    - Sidebar expand/collapse.
    - List item insertion/deletion (Drag & Drop already adds some, but deletion is instant/jarring).
    - Modal entry/exit.
3.  **Empty States**: Add illustrated empty states for Spaces/Resources/Tasks (using
    `generate_image` assets).

---

## 2. Medium Priority Gaps

### A. Advanced Sidebar Organization (Group Management)

**Status**: ✅ **Implemented and Documented**

**Implementation**: Workspaces can be moved between groups using:

1. **Drag and Drop**: Drag workspace from sidebar onto group header or onto another workspace in the
   target group
2. **Context Menu**: Use "Move to section" option in workspace context menu

**Details**:

- Full drag and drop support for moving workspaces to/from groups
- Can drag ungrouped workspaces into groups
- Can drag workspaces between different groups
- Can drag workspaces from groups back to ungrouped area
- Can reorder workspaces within the same group
- E2E tests added to verify all scenarios
- User documentation updated with detailed walkthrough

#### Implementation Complete

1.  ✅ **Context Menu**: "Move to Group" added to the Workspace context menu.
2.  ✅ **Drag and Drop**: Full support for dragging workspaces between groups.
3.  ✅ **Logic**: `WorkspaceStore` handles group ID reassignment.
4.  ✅ **E2E Tests**: Comprehensive tests for all drag and drop scenarios.
5.  ✅ **Documentation**: User journey walkthrough added with detailed steps.

---

## 3. Implementation Plan: Global Search (Cmd+K)

### Phase 1: Search Interface

- **File**: `src/dashboard/Search/CommandPalette.tsx`
- **Tech**: Custom overlay or `cmdk`.
- **State**: `isOpen` (global state).

### Phase 2: Search Indexing

- **Logic**: derived search results from `useWorkspaceStore`.
- **Types**: `Workspace`, `Resource`, `Tab`, `Note`.

### Phase 3: Integration

- **Dashboard**: Mount `CommandPalette` at root.
- **Shortcut**: `useHotkeys` hook to toggle visibility.

## 4. Implementation Plan: Premium UX Polish

### Phase 1: Custom Modals

- **Refactor**: Replace `prompt()` in `Dashboard.tsx` with `<Modal>` component for Renaming.
- **Design**: Glassmorphism background, ease-in animation.

### Phase 2: Empty States

- **Assets**: Generate premium SVG/PNG placeholders for empty views.
- **Component**: `<EmptyState icon="..." message="..." action="..." />`.
