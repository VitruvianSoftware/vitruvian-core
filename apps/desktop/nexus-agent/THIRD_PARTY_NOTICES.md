# Third-party notices

Nexus Agent is MIT-licensed (see [`LICENSE`](LICENSE)). The Mac app ships one
piece of software written by others.

## Mermaid

The chat draws diagrams with [Mermaid](https://github.com/mermaid-js/mermaid).
A copy ships inside the app, so nothing is fetched from the network to draw one.

| | |
| --- | --- |
| Version | 11.17.2 |
| Licence | MIT |
| File here | [`macos/Sources/NexusAgentUI/Resources/mermaid.min.js`](macos/Sources/NexusAgentUI/Resources/mermaid.min.js), unmodified |
| Taken from | `package/dist/mermaid.min.js` in <https://registry.npmjs.org/mermaid/-/mermaid-11.17.2.tgz> |
| Package integrity (npm) | `sha512-V6K3C8EBdEsPFZXSKMJe6ppQOENxuHARr9GvHX4hh47lAbhMRD9qf4oEK7LoaRQxULMa80/qt5gHO73aCleBBg==` |
| SHA-256 of the file | `581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8` |
| Licence text shipped in the app | [`macos/Sources/NexusAgentUI/Resources/mermaid-LICENSE.txt`](macos/Sources/NexusAgentUI/Resources/mermaid-LICENSE.txt), the package's own `LICENSE` |

The file is Mermaid's own build, which also holds the libraries Mermaid is
built from. Those it declares for this version, with the licence each is
published under on npm: `@braintree/sanitize-url`, `@iconify/utils`,
`@mermaid-js/parser`, `@upsetjs/venn.js`, `cytoscape`, `cytoscape-cose-bilkent`,
`cytoscape-fcose`, `dagre-d3-es`, `dayjs`, `es-toolkit`, `katex`, `khroma`,
`marked`, `roughjs`, `stylis`, `ts-dedent` and `uuid` (MIT); `d3` (ISC);
`d3-sankey` (BSD-3-Clause); `dompurify` (MPL-2.0 or Apache-2.0, whichever the
recipient chooses). `khroma` names no licence on npm; the package carries an
MIT licence file. The licence comments those libraries carry are kept in the
file.

### Why this version

11.17.2 is the newest release whose build holds only permissively licensed
code. Mermaid 12 (12.1.0 when this was written) and Mermaid 10 (10.9.8) both
build `elkjs` into the same file, which is published under EPL-2.0 or
GPL-3.0-or-later, and the 12.1.0 file is half as large again (5.5 MB against
3.6 MB). The chat's page works unchanged with 12.1.0, so moving up is a choice
about that licence and that size, not about code.

### Updating it

1. Download the package from the npm registry (not a CDN) and check it against
   the integrity value `npm view mermaid@<version> dist.integrity` prints.
2. Replace `mermaid.min.js` with the package's `dist/mermaid.min.js` and
   `mermaid-LICENSE.txt` with its `LICENSE`.
3. Update the table above and the SHA-256 in
   `macos/Tests/MermaidPageTests.swift`. Those tests draw a diagram with the
   new copy and fail if the page asks the network for anything.
4. In the monorepo, re-pin the Vitruvian app
   (`bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared`) and add a line
   to its `UPSTREAM.md`.

```text
The MIT License (MIT)

Copyright (c) 2014 - 2022 Knut Sveidqvist

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
