# Manual Testing Guide

This guide helps you manually test the Tabula extension to ensure all features work correctly.

## Setup

1. Build the extension:

   ```bash
   npm run build --workspace=extension
   ```

2. Load in Chrome:
   - Open `chrome://extensions/`
   - Enable "Developer mode"
   - Click "Load unpacked"
   - Select `extension/dist` directory

3. Pin the extension to your toolbar for easy access

## Test Scenarios

### 1. First Installation

**Expected:**

- Extension icon appears in toolbar
- Welcome page opens in new tab
- Default settings are initialized

**Test:**

1. Install extension
2. Verify icon is visible
3. Check that new tab opens with GitHub link

### 2. Create Workspace

**Expected:**

- Can create up to 10 workspaces
- Each workspace has customizable name, icon, color
- Workspaces appear in list immediately

**Test:**

1. Click extension icon to open popup
2. Click "+ New" button
3. Enter name: "Test Workspace 1"
4. Enter description: "My first test workspace"
5. Select icon: 📁
6. Select color: Blue (#4F46E5)
7. Click "Create"
8. Verify workspace appears in list
9. Repeat 9 more times to test limit
10. Verify 11th workspace cannot be created

### 3. Save Tabs to Workspace

**Expected:**

- All current tabs are saved with URLs, titles, favicons
- Pinned tabs maintain pinned state
- Tab count updates

**Test:**

1. Open 5-10 tabs in various websites
2. Pin 1-2 tabs
3. Click extension icon
4. Select "Test Workspace 1"
5. Click "Save Tabs"
6. Verify tab count shows correct number
7. Close all tabs
8. Verify tabs are still saved in workspace

### 4. Restore Tabs from Workspace

**Expected:**

- Tabs open in specified location (new window or current)
- Tab order is preserved
- Pinned tabs restore as pinned

**Test:**

1. Close all tabs (or use new window)
2. Click extension icon
3. Select workspace with saved tabs
4. Click "Restore" (opens in new window)
5. Verify all tabs open in new window
6. Verify tab order matches original
7. Verify pinned tabs are pinned
8. Try "Restore" in current window
9. Verify tabs open in current window

### 5. Switch Workspace

**Expected:**

- Current tabs close (except pinned)
- Workspace tabs open
- Active workspace indicator updates

**Test:**

1. Open several tabs manually
2. Click extension icon
3. Select workspace with saved tabs
4. Click "Switch"
5. Verify current tabs close
6. Verify workspace tabs open
7. Verify "ACTIVE" badge shows on workspace
8. Open popup again, verify active workspace highlighted

### 6. Edit Workspace

**Expected:**

- Can edit name, description, icon, color
- Changes save immediately
- List updates

**Test:**

1. Click extension icon
2. Select a workspace
3. Click "Edit" button
4. Change name to "Updated Workspace"
5. Change description
6. Select different icon and color
7. Click "Update"
8. Verify changes appear immediately
9. Close and reopen popup
10. Verify changes persisted

### 7. Delete Workspace

**Expected:**

- Confirmation dialog appears
- Workspace is removed from list
- Active workspace clears if deleted

**Test:**

1. Click extension icon
2. Select a workspace
3. Click "Delete" button
4. Verify confirmation dialog appears
5. Click "Cancel" - verify workspace remains
6. Click "Delete" again
7. Click "OK" - verify workspace is removed
8. Verify workspace no longer in list
9. Create workspace, make it active, then delete
10. Verify active workspace clears

### 8. Tab Suspension

**Expected:**

- Individual tabs can be suspended
- Memory usage reduces
- Tabs reload when clicked

**Test:**

1. Open several tabs
2. Note memory usage in Task Manager
3. Open developer tools > Application > Background
4. In console, run:
   ```javascript
   chrome.runtime.sendMessage({ type: 'SUSPEND_INACTIVE' }, console.log);
   ```
5. Verify inactive tabs are discarded
6. Check memory usage decreased
7. Click suspended tab
8. Verify tab reloads

### 9. Settings Persistence

**Expected:**

- Settings save to local storage
- Settings persist across sessions

**Test:**

1. Open popup
2. Note current state (workspaces, active workspace)
3. Close popup
4. Disable and re-enable extension
5. Open popup
6. Verify all workspaces still present
7. Verify active workspace still set

### 10. Error Handling

**Expected:**

- Graceful error handling
- User-friendly error messages
- No crashes

**Test:**

1. Try to create workspace with empty name - should show validation
2. Try to restore from empty workspace - should disable button
3. Try to exceed 10 workspace limit - should show message
4. Try operations with closed tabs
5. Verify no console errors

### 11. Performance

**Expected:**

- Popup opens in < 200ms
- Operations complete quickly
- No lag or freezing

**Test:**

1. Open popup multiple times
2. Time how long it takes to appear
3. Create several workspaces quickly
4. Save/restore many tabs (50+)
5. Monitor memory usage
6. Check for any performance issues

### 12. UI/UX

**Expected:**

- Clear, intuitive interface
- Proper spacing and alignment
- Responsive to interactions
- Accessible

**Test:**

1. Open popup and inspect layout
2. Verify buttons are clickable
3. Verify text is readable
4. Test with different zoom levels
5. Check for any visual bugs
6. Test keyboard navigation

## Browser-Specific Tests

### Edge

Repeat all tests above in Edge browser.

1. Open `edge://extensions/`
2. Load extension
3. Run through test scenarios
4. Document any Edge-specific issues

### Firefox (Optional)

1. Open `about:debugging#/runtime/this-firefox`
2. Load temporary add-on
3. Run through basic scenarios:
   - Create workspace
   - Save/restore tabs
   - Edit workspace
   - Delete workspace
4. Document any Firefox-specific issues

## Reporting Issues

When you find an issue:

1. Note the browser and version
2. Document steps to reproduce
3. Include any console errors
4. Take screenshots if relevant
5. Report in GitHub Issues

## Success Criteria

All test scenarios should pass with:

- ✅ No console errors
- ✅ Expected behavior matches actual
- ✅ Performance is acceptable
- ✅ No visual bugs
- ✅ Data persists correctly

## Test Results Template

```markdown
## Test Results

**Date**: [DATE] **Tester**: [NAME] **Browser**: Chrome/Edge/Firefox [VERSION] **Extension
Version**: 0.1.0

### Results

- [ ] First Installation
- [ ] Create Workspace
- [ ] Save Tabs
- [ ] Restore Tabs
- [ ] Switch Workspace
- [ ] Edit Workspace
- [ ] Delete Workspace
- [ ] Tab Suspension
- [ ] Settings Persistence
- [ ] Error Handling
- [ ] Performance
- [ ] UI/UX

### Issues Found

1. [Issue description]
2. [Issue description]

### Notes

[Any additional observations]
```
