# Browser Compatibility Notes

## Firefox Support

Firefox has partial support for Manifest V3. The following adjustments may be needed for full
Firefox compatibility:

### Known Issues

1. **Service Worker vs Background Scripts**
   - Firefox has limited service worker support
   - May need to convert to background page for Firefox
   - Consider using `browser.runtime` API for cross-browser compatibility

2. **API Differences**
   - Use `browser.*` instead of `chrome.*` for Firefox
   - Install `webextension-polyfill` for compatibility layer

3. **Storage API**
   - Firefox requires different storage quota limits
   - Test storage.local extensively on Firefox

### Recommended Approach

For Phase 1, focus on Chrome and Edge (Chromium-based). Firefox support can be added in Phase 2
with:

1. Install webextension-polyfill:

```bash
npm install webextension-polyfill --workspace=extension
```

2. Replace chrome._ calls with browser._ calls

3. Test thoroughly on Firefox Developer Edition

4. Create Firefox-specific manifest if needed

### Current Status

- ✅ Chrome: Fully supported
- ✅ Edge: Fully supported (Chromium-based)
- ⚠️ Firefox: Requires testing and potential adjustments

## Edge Compatibility

Edge uses the same Chromium engine as Chrome, so the extension should work without modifications.

### Installation

1. Navigate to `edge://extensions/`
2. Enable "Developer mode"
3. Load unpacked from `extension/dist`

### Testing Checklist

- [ ] Extension loads without errors
- [ ] Popup displays correctly
- [ ] Workspaces can be created
- [ ] Tabs can be saved and restored
- [ ] Tab suspension works
- [ ] Settings persist
- [ ] No console errors

## Chrome Compatibility

Primary development target. All features fully supported.

### Testing Checklist

- [x] Extension loads without errors
- [x] Popup displays correctly
- [x] Workspaces can be created
- [x] Tabs can be saved and restored
- [x] Tab suspension works
- [x] Settings persist
- [x] No console errors

## Recommended Testing Process

1. **Chrome** (Primary)
   - Test all features
   - Validate performance
   - Check memory usage

2. **Edge** (Secondary)
   - Verify extension loads
   - Test core workflows
   - Check for Edge-specific issues

3. **Firefox** (Stretch Goal)
   - Install with temporary loading
   - Identify compatibility issues
   - Document required changes
   - Create Firefox-specific branch if needed
