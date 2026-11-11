# Components

## Overview
Component package providing implementation for `apps/web/oauth-user-inspector/frontend/components`.

## Interface
- `[Tabs.tsx:Tab]`
- `[icons.tsx:GithubIcon]`
- `[icons.tsx:GoogleIcon]`
- `[icons.tsx:Spinner]`
- `[icons.tsx:ClipboardIcon]`
- `[icons.tsx:ClipboardCheckIcon]`
- `[icons.tsx:MenuIcon]`
- `[icons.tsx:HelpIcon]`
- `[icons.tsx:UploadIcon]`
- `[icons.tsx:LogoutIcon]`
- `[icons.tsx:GitLabIcon]`
- `[icons.tsx:Auth0Icon]`
- `[icons.tsx:ZitadelIcon]`
- `[icons.tsx:LinkedInIcon]`

## Invariants
- None

## Side Effects
- [ApiExplorer.tsx:82]: `const apiResponse = await fetch("/api/explore", {`
- [CodeSnippetGenerator.tsx:42]: `type CodeLanguage = "curl" | "nodejs" | "python" | "go";`
- [CodeSnippetGenerator.tsx:53]: `useState<CodeLanguage>("curl");`
- [CodeSnippetGenerator.tsx:94]: `let snippet = `curl -X ${endpoint.method} \\\n`;`
- [LoginScreen.tsx:417]: `Fetch with GitHub Token`
- [icons.tsx:27]: `xmlns="http://www.w3.org/2000/svg"`
- [icons.tsx:43]: `xmlns="http://www.w3.org/2000/svg"`
- [icons.tsx:71]: `xmlns="http://www.w3.org/2000/svg"`

## Verification
- Run: `bazel test //apps/web/oauth-user-inspector/frontend/components/...`
