# The tool catalog

`tools.json` is the list of tools Vitruvian offers on its Extensions page in
Settings, and on vitruviansoftware.dev/tools/catalog/.
VitruvianSoftware curates it: a tool is listed, changed or taken off by a
pull request that James merges.

## What listing means

Listing a tool means two things, and only these:

- **VitruvianSoftware read the tool's manifest** and the entry says what the
  manifest says: its id, version, name, publisher, summary, what it says it
  uses, and its commands.
- **The download is pinned.** The entry names one zip, its size and its
  SHA-256. The app refuses a download whose size or checksum is not the one
  listed, and a list that is not signed by VitruvianSoftware's key.

Listing does not mean the tool was audited, and it puts no limit on what the
tool does. A tool is a separate program with every permission Vitruvian has.
The app's agreement sheet says so before anything is installed, for a tool
from the catalog exactly as for a folder a person picked.

## An entry

```json
{
  "id": "dev.vitruvian.reference",
  "name": { "en": "Reference tool" },
  "publisher": "VitruvianSoftware",
  "summary": { "en": "Says hello. The smallest tool that speaks protocol 1." },
  "version": "0.1.0",
  "protocol": "1",
  "minimumAppVersion": "3.43.0",
  "source": "https://github.com/VitruvianSoftware/vitruvian-sdk",
  "download": {
    "url": "https://github.com/VitruvianSoftware/vitruvian-sdk/releases/download/v0.9.0/reference-tool-0.1.0.zip",
    "sha256": "<64 lower-case hex digits>",
    "size": 4096
  },
  "uses": ["notify"],
  "commands": [{ "id": "hello", "title": { "en": "Say hello" } }]
}
```

`name`, `publisher`, `version`, `protocol`, `uses` and each command's `id` and
`title` are copied from the tool's `vitruvian-tool.json`; `summary` is its
`description`. `minimumAppVersion` is the oldest Vitruvian that may install it:
an older one does not show it.

## The zip

The tool's folder, zipped so that `vitruvian-tool.json` is at the top of the
zip, not inside a folder of its own, with no links and nothing encrypted:

```sh
cd path/to/the-tool && zip -r -X ../the-tool-1.0.0.zip .
```

It is attached to a GitHub release of a `VitruvianSoftware` repository. Any
other place is refused by the schema; adding one is a change to the pattern
of `download.url` in `catalog.schema.json` and to `DOWNLOAD_PREFIXES` in
`catalog_rules.py`, in a pull request of its own.

## A pull request that lists a tool

- [ ] One entry added or changed in `tools.json`, and `generated` set to now,
      in UTC (`date -u +%Y-%m-%dT%H:%M:%SZ`). The app refuses a list older
      than one it has seen.
- [ ] `size` is `stat -f %z the-tool.zip` and `sha256` is
      `shasum -a 256 the-tool.zip`, of the file attached to the release.
- [ ] `bazel test //catalog/...` passes: the schema and the rules.
- [ ] `bazel run //tools/sync-site-tools:sync` has updated the website's
      page, and the pull request holds that change too.
- [ ] The check **catalog-check** passed. It downloads each new or changed
      entry, compares its size and checksum, unpacks it the way the app
      does, runs `vitruvian-tool validate` on it, and compares its manifest
      with the entry.

What CI cannot judge, and the reviewer reads:

- **Who made the tool, and its source.** The link in `source` is the code
  the release was built from; read what it does with the services it lists
  and with the network.
- **The words.** `name`, `summary` and the command titles are shown in the
  app and on the website as the tool wrote them.
- **The release.** The zip is attached to a release of the repository in
  `source`, made by its owner, and was not replaced after it was checked.

After the merge, the workflow **catalog-publish** signs `tools.json` and opens
a pull request that writes the signed copy into the website. The app sees
the change once that pull request merges and the site is deployed.

## The signature

The app trusts a list only when it is signed with VitruvianSoftware's key.
The key is Ed25519. Its public half is in `public-key.txt` and, the same
line, in the app as `CatalogueSigning.publicKey`; `//catalog:catalog_test`
fails when the two differ. Its private half is the repository secret
`CATALOG_SIGNING_KEY`: the 32 bytes of the key, in base64. Only the workflow
**catalog-publish** reads it.

What is signed is the exact bytes of `tools.json` at the commit on `main`.
The website serves a byte copy of it at `/tools/catalog/tools.json` and the
signature at `/tools/catalog/tools.json.sig`: the 64 bytes of the signature in
base64, then a newline.

A new key is a new line in `public-key.txt`, a new constant in a new release
of the app, and a new secret. A release that has the old constant refuses
every list the new key signs, so the old key keeps signing until that release
is out; after that it signs nothing.

## Taking a tool off

Delete its entry and set `generated`. Within a day of the signed copy being
deployed the app stops offering it. A copy a person installed stays
installed: removing it is theirs to do.
