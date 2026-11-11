# Background

## Overview
Component package providing implementation for `apps/suites/tabula/extension/src/background`.

## Interface
- Internal implementation components

## Invariants
- [index.test.ts:25]: `declare let require: any;`
- [index.test.ts:91]: `require("./index");`
- [index.test.ts:94]: `const { StorageService } = require("../services/storage");`

## Side Effects
- [index.test.ts:56]: `query: jest.fn().mockResolvedValue([]),`
- [index.test.ts:146]: `(chrome.tabs.query as jest.Mock).mockResolvedValue([`
- [index.test.ts:209]: `(chrome.tabs.query as jest.Mock).mockResolvedValue([`
- [index.ts:121]: `const tabs = await chrome.tabs.query({ active: false, pinned: false });`

## Verification
- Run: `bazel test //apps/suites/tabula/extension/src/background/...`
