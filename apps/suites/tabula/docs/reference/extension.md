# Browser Extension Documentation

## Overview

The Tabula browser extension provides a lightweight, privacy-conscious solution for managing browser
tabs and workspaces. Built using Manifest V3, it supports Chrome (primary), Edge (Chromium-based),
and Firefox.

## Architecture

### Technology Stack

- **Framework**: React 18 with TypeScript
- **State Management**: Zustand
- **Build System**: Webpack 5
- **Testing**: Jest + Playwright
- **Manifest**: V3 (service worker-based)

### Project Structure

```
extension/
├── src/
│   ├── background/       # Background service worker
│   ├── popup/           # Extension popup UI
│   ├── components/      # React components
│   ├── services/        # Core services (tabs, workspace, storage)
│   ├── stores/          # Zustand state stores
│   ├── types/           # TypeScript type definitions
│   ├── icons/           # Extension icons
│   └── manifest.json    # Extension manifest
├── tests/              # E2E tests
└── dist/              # Build output
```

## Features

### Workspace Management

**Create Workspaces**

- Create up to 10 workspaces (free tier)
- Customize with name, description, icon, and color
- Auto-generated unique IDs

**Manage Workspaces**

- Edit workspace properties
- Delete workspaces with confirmation
- Track active workspace

**Switch Between Workspaces**

- One-click switching
- Optionally close current tabs
- Restore workspace tabs

**Color Customization**

- Set custom colors on workspaces via context menu
- Set group colors (inherited by all workspaces in the group)
- Visual accent bar shows the effective color on the active workspace
- Color priority: Workspace color → Group color → Default blue
- Select "None" to clear a color and use inheritance or default

### Tab Management

**Save Tabs**

- Save all current tabs to a workspace
- Preserves URLs, titles, favicons
- Maintains pinned state and order

**Restore Tabs**

- Restore all tabs from a workspace
- Open in current or new window
- Selective restoration

**Suspend Tabs**

- Manually suspend individual tabs
- Suspend all inactive tabs
- Reduces memory usage

### Storage

**Local Storage**

- Chrome storage API for persistence
- Works offline
- Fast access

**Settings**

- Auto-suspend configuration
- Suspend timeout (minutes)
- Sync preferences
- Theme settings (light/dark/auto)

## Development

### Prerequisites

- Node.js >= 18.0.0
- npm >= 9.0.0

### Setup

```bash
# Install dependencies from root
npm install

# Build extension
npm run build --workspace=extension

# Development mode (watch)
npm run dev --workspace=extension

# Run tests
npm test --workspace=extension

# Run E2E tests
npm run test:e2e --workspace=extension
```

### Building

```bash
# Production build
npm run build --workspace=extension

# Output in extension/dist/
```

The built extension will be in the `dist/` directory, ready to load into your browser.

### Testing

**Unit Tests**

```bash
npm test --workspace=extension
```

Tests cover:

- Storage service operations
- Workspace CRUD operations
- Tab management functions
- State management stores

**E2E Tests**

```bash
npm run test:e2e --workspace=extension
```

Tests cover:

- Workspace creation flow
- Tab save/restore flow
- Workspace switching
- Settings management

### Type Checking

```bash
npm run typecheck --workspace=extension
```

### Linting

```bash
# Check linting
npm run lint --workspace=extension

# Auto-fix issues
npm run lint:fix --workspace=extension
```

## Browser Installation

### Chrome

1. Open `chrome://extensions/`
2. Enable "Developer mode"
3. Click "Load unpacked"
4. Select the `extension/dist` directory
5. Extension appears in toolbar

### Edge

1. Open `edge://extensions/`
2. Enable "Developer mode"
3. Click "Load unpacked"
4. Select the `extension/dist` directory
5. Extension appears in toolbar

### Firefox

1. Open `about:debugging#/runtime/this-firefox`
2. Click "Load Temporary Add-on"
3. Select `manifest.json` from `extension/dist`
4. Extension appears in toolbar

**Note**: Firefox requires temporary loading in development. For production, submit to Firefox
Add-ons.

## API Reference

### Services

#### StorageService

```typescript
// Get all workspaces
const workspaces = await StorageService.getWorkspaces();

// Save workspaces
await StorageService.saveWorkspaces(workspaces);

// Get workspace by ID
const workspace = await StorageService.getWorkspaceById(id);

// Get/set active workspace
const activeId = await StorageService.getActiveWorkspaceId();
await StorageService.setActiveWorkspaceId(id);

// Get/save settings
const settings = await StorageService.getSettings();
await StorageService.saveSettings(settings);
```

#### WorkspaceService

```typescript
// Create workspace
const workspace = await WorkspaceService.createWorkspace({
  name: 'My Workspace',
  description: 'Optional description',
  icon: '📁',
  color: '#4F46E5',
});

// Update workspace
await WorkspaceService.updateWorkspace(id, { name: 'New Name' });

// Delete workspace
await WorkspaceService.deleteWorkspace(id);

// Save current tabs
await WorkspaceService.saveCurrentTabsToWorkspace(id);

// Restore tabs
await WorkspaceService.restoreWorkspaceTabs(id, {
  inNewWindow: true,
  closeCurrentTabs: false,
});

// Switch workspace
await WorkspaceService.switchToWorkspace(id);
```

#### TabService

```typescript
// Get current tabs
const tabs = await TabService.getCurrentTabs();

// Open tabs
await TabService.openTabs(tabs, { inNewWindow: true });

// Close all tabs
await TabService.closeAllTabs(includePinned);

// Suspend tab
await TabService.suspendTab(tabId);

// Suspend inactive tabs
await TabService.suspendInactiveTabs();

// Get memory stats
const stats = await TabService.getMemoryStats();
```

### Stores

#### useWorkspaceStore

```typescript
const {
  workspaces, // Workspace[]
  activeWorkspaceId, // string | null
  loading, // boolean
  error, // string | null
  loadWorkspaces, // () => Promise<void>
  createWorkspace, // (input) => Promise<Workspace>
  updateWorkspace, // (id, input) => Promise<Workspace>
  deleteWorkspace, // (id) => Promise<void>
  saveCurrentTabs, // (id) => Promise<void>
  restoreTabs, // (id, options) => Promise<void>
  switchWorkspace, // (id) => Promise<void>
} = useWorkspaceStore();
```

#### useSettingsStore

```typescript
const {
  settings, // ExtensionSettings
  loading, // boolean
  error, // string | null
  loadSettings, // () => Promise<void>
  updateSettings, // (updates) => Promise<void>
} = useSettingsStore();
```

## Performance

### Size

- **Total**: ~304KB
- **popup.js**: ~154KB (React + Zustand)
- **background.js**: ~288 bytes
- **Icons**: ~2KB

Well under the 50MB requirement for browser extensions.

### Memory

- Minimal footprint in background
- UI loaded only when popup is open
- Tab suspension reduces browser memory usage

## Security

### Permissions

```json
{
  "permissions": ["tabs", "storage", "alarms"],
  "host_permissions": ["http://*/*", "https://*/*"]
}
```

- **tabs**: Required for tab management
- **storage**: Required for local data persistence
- **alarms**: Required for periodic tasks
- **host_permissions**: Required to access tab URLs

### Data Storage

- All data stored locally using Chrome Storage API
- No external services in MVP
- No analytics or tracking
- Privacy-first design

### Content Security Policy

```json
{
  "extension_pages": "script-src 'self'; object-src 'self'"
}
```

Strict CSP prevents XSS and injection attacks.

## Browser Compatibility

### Chrome

✅ **Fully Supported** (Primary Target)

- Version 88+ (Manifest V3 support)
- All features available

### Edge

✅ **Fully Supported** (Chromium-based)

- Version 88+ (Manifest V3 support)
- Same codebase as Chrome
- No additional changes needed

### Firefox

⚠️ **Partial Support** (Stretch Goal)

- Manifest V3 support varies
- May require adjustments:
  - Service worker → background scripts
  - API differences (browser._ vs chrome._)
  - Different extension store requirements

**Recommendation**: Test thoroughly on Firefox before claiming full support.

## Troubleshooting

### Build Issues

**Problem**: Module not found errors

```bash
# Solution: Clean install
rm -rf node_modules package-lock.json
npm install
```

**Problem**: TypeScript errors

```bash
# Solution: Check version and rebuild
npm run typecheck --workspace=extension
npm run build --workspace=extension
```

### Runtime Issues

**Problem**: Extension not loading

- Check manifest.json syntax
- Verify all required files are in dist/
- Check browser console for errors

**Problem**: Storage not persisting

- Check storage permissions in manifest
- Verify chrome.storage API calls
- Check browser extension storage limits

**Problem**: Tabs not saving/restoring

- Check tab permissions
- Verify active window
- Check for popup blocker interference

**Problem**: Tab groups lost on page refresh

This is a known timing issue with Chrome's tab groups API, related to several Chromium bugs:

- **Chromium Issue 40744390** (Jan 2021): `chrome.tabs.query({groupId: ...})` can return incorrect
  results, with `groupId` not being accurate or immediately updated after grouping operations.
- **Chromium Issue 323982812** (Feb 2024): Issues with updating saved tab groups, contributing to
  broader inconsistencies in tab group management.

**Symptoms:**

- On soft refresh (Cmd+R), `chrome.tabs.query()` returns tabs with `groupId: -1` even when tabs ARE
  in groups
- The `tabGroups.query()` API returns groups correctly, but tabs haven't had their groupIds assigned
  yet
- Hard refresh (Shift+Cmd+R) works because Chrome has more time to initialize

**Workaround:** A 500ms delay is applied before the initial sync to give Chrome time to stabilize
its APIs. See TODO in `useTabSync.ts` for potential better solutions including polling, atomic
queries, or skipping sync on initial load.

## Contributing

### Code Style

- TypeScript strict mode
- ESLint + Prettier for formatting
- Functional components with hooks
- Services use static methods
- Stores use Zustand

### Testing

- Write unit tests for new services
- Add E2E tests for user flows
- Maintain > 80% code coverage
- Test in all target browsers

### Pull Requests

1. Create feature branch
2. Implement changes
3. Add tests
4. Update documentation
5. Submit PR with description

## Roadmap

### Phase 1 (MVP) ✅

- [x] Basic workspace management
- [x] Tab save/restore
- [x] Tab suspension
- [x] Chrome support
- [x] Edge support
- [ ] Firefox support (stretch)

### Phase 2 (Planned)

- [ ] Cloud sync
- [ ] Session history
- [ ] Search functionality
- [ ] Keyboard shortcuts
- [ ] Context menus

### Phase 3 (Future)

- [ ] Tab preview
- [ ] Workspace sharing
- [ ] Mobile PWA
- [ ] Browser action badge

## Support

For issues, questions, or contributions:

- GitHub Issues: https://github.com/VitruvianSoftware/vitruvian-core/issues
- Documentation: https://docs.vitruviansoftware.com/
- Contributing Guide: See CONTRIBUTING.md

## License

MIT License - See LICENSE file for details.
