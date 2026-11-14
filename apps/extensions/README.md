# Extensions

Products that live only inside a host app, with no app of their own, go in `apps/extensions/<host>/vitruvian-<noun>`. Today the host is Atrium (`apps/extensions/atrium/`), which holds Vitruvian GitHub and Vitruvian TV.

A standalone app that also plugs into a host keeps its own folder (`apps/<platform>/vitruvian-<noun>`) and puts the extension in a folder named `atrium-extension/` inside it; `tools/conformance` fails if a `vitruvian-tool.json` sits anywhere else.
