# TabCLI Security Improvements Needed

## Overview

The initial implementation of TabCLI has some command injection vulnerabilities that should be
addressed before production use.

## Issues Identified

### 1. Command Injection in secrets.ts (line 44)

**Severity:** HIGH  
**Issue:** User input (`value`) is directly interpolated into shell command  
**Fix:** Use spawn() with array arguments or write to temp file

### 2. Command Injection in deploy.ts (lines 38-47)

**Severity:** HIGH  
**Issue:** Config values directly interpolated into shell commands  
**Fix:** Use spawn() with array arguments and validate inputs

### 3. Command Injection in db.ts (line 53)

**Severity:** MEDIUM  
**Issue:** Migration name directly interpolated without validation  
**Fix:** Validate migration name pattern (alphanumeric + underscores only)

### 4. Config Parsing Error Handling (config.ts line 13)

**Severity:** LOW  
**Issue:** JSON parsing errors not caught, unclear error messages  
**Fix:** Wrap in try-catch with user-friendly messages (DONE in utils/config.ts)

### 5. Code Duplication

**Severity:** LOW  
**Issue:** Config reading logic duplicated across commands  
**Fix:** Extract to shared utility (DONE in utils/config.ts)

## Recommended Fixes

### Use spawn() instead of execSync

**Before:**

```typescript
execSync(`gcloud secrets create ${key} --project=${projectId}`);
```

**After:**

```typescript
import { spawn } from 'child_process';

function execGcloud(args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const proc = spawn('gcloud', args);
    // Handle stdout, stderr, and exit code
  });
}

// Usage
await execGcloud(['secrets', 'create', key, `--project=${projectId}`]);
```

### Input Validation

Add validation for user inputs:

```typescript
function validateMigrationName(name: string): boolean {
  return /^[a-zA-Z0-9_]+$/.test(name);
}
```

### Temporary File for Secrets

**Before:** Echo into stdin (vulnerable)  
**After:** Write to temp file with secure permissions

```typescript
import os from 'os';
import fs from 'fs';
import path from 'path';

const tmpFile = path.join(os.tmpdir(), `secret-${Date.now()}`);
fs.writeFileSync(tmpFile, value, { mode: 0o600 });
await execGcloud(['secrets', 'create', key, `--data-file=${tmpFile}`]);
fs.unlinkSync(tmpFile);
```

## Implementation Status

- [x] Created utils/config.ts for shared config management
- [x] Added try-catch for config parsing
- [ ] Replace execSync with spawn in all commands
- [ ] Add input validation for all user inputs
- [ ] Use temp files for secret values
- [ ] Add comprehensive unit tests
- [ ] Security audit before production use

## Priority

**For Development (Current):** Medium - The tool works for trusted development environments  
**For Production:** HIGH - Must fix before allowing production use or external deployments

## Notes

The TabCLI tool is currently safe for local development use by trusted developers. However, these
security improvements should be implemented before:

- Deploying TabCLI as a standalone tool
- Using in CI/CD pipelines
- Allowing untrusted input
- Production deployments

## Next Steps

1. Create a follow-up issue to address these security concerns
2. Implement fixes using spawn() and input validation
3. Add security tests
4. Run security audit tools
5. Update documentation with security best practices
