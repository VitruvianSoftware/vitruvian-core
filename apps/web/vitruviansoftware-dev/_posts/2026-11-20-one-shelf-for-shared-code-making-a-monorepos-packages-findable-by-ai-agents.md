---
title: "One Shelf for Shared Code: Making a Monorepo's Packages Findable by AI Agents"
description: >-
  Our AI agents kept writing the same helpers again: 68 copies of ten helper families,
  most of their lines repeated somewhere else. The fix was not a stricter prompt. It was
  making shared code impossible to miss: one catalog file per package, a generated
  index, Backstage discovery, a reuse-first rule, and a check that flags copied code.
  Here is what we built in one day, what it measured, and what it did not fix.
date: 2026-11-20 18:00:00 -0800
categories: [agents, monorepo, developer-tools, backstage, architecture]
image: /images/shared-packages-loop.svg
---

AI coding agents are very good at writing a helper from scratch. That is the problem.

Ask an agent to port a Python script to Rust, and it will write a perfect little `argparse` clone in a few minutes. Ask a different agent next week to port a different script, and it will write another one. Neither knows the other exists. Each copy has its own tests, its own small quirks, and its own bugs, and every fix has to be found and made again in each one.

In `vitruvian-core`, our monorepo, this had quietly happened ten times over. This morning we counted **68 copies of ten helper families**: Python-style JSON, `argparse`, Unicode tables, Python string rules, an HTTP client, a small `jq`, and a few Go standard-library helpers. Of the 29,769 lines in those copies, **18,277 (61%) also appeared in another copy**.

The shared code already existed for most of them. The agents just could not see it.

This post covers what we changed so they can: the convention, the automation that keeps it honest, the numbers before and after, and the parts that did not work out. In an earlier post we described [how we structure the repo for agents]({{ '/blog/2026/10/11/architecting-your-codebase-for-agentic-development/' | relative_url }}); this is the same idea applied to reuse.

![How an agent finds shared code before it writes its own](/images/shared-packages-loop.svg)
*Figure 1: An agent is told to look first, reads an index generated from one catalog file per package (or searches Backstage, which reads the same files), and reuses what it finds. If it copies anyway, the duplicate check on the pull request names the package to use. A new package without a catalog entry fails the conformance check, so the index cannot fall behind.*

---

## Why agents reinvent the wheel

An agent working on a task sees the files it opens and little else. If nothing on its path says "this already exists", writing new code is the fastest route to a green test. A human engineer has the same problem, but a human remembers last month's code review. An agent starts fresh every session.

When we looked at why the copies existed, three gaps stood out:

1. **No useful index.** `packages/README.md` named 7 of the 9 folders, each only as "Contract for packages/X", with nothing about what the code inside did. Some packages had READMEs; some did not.
2. **A catalog nobody trusted.** Our Backstage catalog, the developer portal that is supposed to answer "what do we have?", listed **3 libraries**. Only **2 of the 9 package folders** had a catalog entry at all, and the catalog depended on a hand-kept list of file locations in the repo root.
3. **No feedback.** Nothing told an agent, or a reviewer, that a new file was a copy of something under `packages/`.

A better-worded prompt would not fix any of these. Each needed a mechanism.

## The convention

The design took a morning to agree. These are its parts, in plain terms.

**One folder per package, named for what it does.** `packages/gocompat`, `packages/sentry-lite`, `packages/orchestrator-core`. Not `packages/rust/...` or `packages/utils`. A folder named after a language says nothing about what is inside, and folders like `utils`, `common` and `shared` become junk drawers. Code shared inside one product stays in that product. Code used by two or more products goes in `packages/`.

**Every package has two files that describe it.** A `README.md` with three fixed sections: what it gives you, when to use it, and when not to use it (with the package to use instead). And a `catalog-info.yaml` with a one-line description, tags, an owner and the Bazel label to depend on. The README is for reading; the catalog file is for machines.

**The index is generated, never written by hand.** `packages/README.md` is built from every `catalog-info.yaml` under `packages/`. A drift test fails the build if someone edits it by hand or adds a package without regenerating it. An agent can read one file and see every shared library, its purpose and its Bazel label.

**Backstage finds the catalog files itself.** Instead of a hand-kept list of locations, Backstage now discovers every `catalog-info.yaml` in the repo. A new package appears in the portal minutes after it merges, with nobody remembering to register it.

**A reuse-first rule in `AGENTS.md`.** Before writing a helper, an agent looks in this order:

1. our own packages;
2. a third-party library the repo already depends on;
3. a new, well-known, maintained library that passes our vulnerability scan;
4. new code, only if none of those fits.

Our own packages come first, ahead of new third-party code, for a practical reason. Every new dependency costs us something: one version per ecosystem across the whole repo, a license check, vulnerability scanning and lockfile upkeep. Our packages have already paid those costs.

**A check that flags copies.** A new tool, `dupcheck`, compares the lines a pull request adds against every shared package. If 12 or more meaningful lines match, it says which package to use instead. Deliberate copies, such as code generated from an SDK or plugin bundles that must ship self-contained, go in an allow list with a reason.

**A conformance rule that keeps the index complete.** A package, or a product, without a catalog entry fails the repo's conformance check. That is what stops the index and Backstage from drifting again.

## The rollout

We ran the rollout with our own agent team: a lead that designs and reviews, and specialists that implement, test and document. Most implementation ran on Gemini through Antigravity, with Claude taking over when a run timed out; reviews and final checks ran on Claude. Every helper merge followed the same rule: **prove the shared code behaves exactly like the copy before deleting the copy.** For each tool, we ran its tests against the old copy, then swapped in the shared code and ran them again. Some merges went further. For the Python string rules we compared old and new output on every Unicode code point; for float formatting, on three million random and edge-case numbers.

Over the day that produced:

- catalog entries and READMEs for every package;
- Backstage discovery, replacing the hand-kept list;
- the generated index with its drift test;
- the reuse rule in `AGENTS.md`;
- the `dupcheck` tool;
- a template for new packages, so the next one starts with both description files;
- eight helper merges: `argparse` and Go `exec` helpers, three rounds of Unicode tables, Go standard-library helpers, JSON, HTTP, and Python string and error helpers.

## What it measured

All copy counts below come from the same tool run against two commits: the commit before we started, and `main` after the last helper merge landed. Same tool, same rules, so the numbers compare.

| Helper family | Copies before | Copies after | Lines in copies before | Lines in copies after |
|---|---:|---:|---:|---:|
| `json` | 16 | 15 | 9,246 | 8,865 |
| `argparse` | 5 | 2 | 2,996 | 1,118 |
| `unicode_tables` | 4 | 1 | 4,518 | 913 |
| `pystr` | 10 | 7 | 3,298 | 2,832 |
| `http` | 8 | 5 | 3,188 | 2,550 |
| `jq` | 7 | 7 | 2,077 | 2,077 |
| `pyjson` | 5 | 4 | 1,750 | 1,541 |
| `pyerr` | 8 | 5 | 825 | 523 |
| `gostd` | 3 | 0 | 1,263 | 0 |
| `goexec` | 2 | 0 | 608 | 0 |
| **Total** | **68** | **46** | **29,769** | **20,419** |

- **Copies:** 68 → 46, down 22.
- **Lines repeated in another copy:** 18,277 → 10,394, down 7,883. As a share of the lines in copies, 61% → 50%.
- **Net code:** the eight helper merges added 6,045 lines and removed 10,084, for **4,039 fewer lines in the repo**. That includes all the new equivalence tests. Three merges grew the repo. One moved a large Unicode case table into a shared package along with new tests, one added tests for the shared Go helpers, and the shared HTTP client is bigger than any single copy because it carries the strictest security handling of all of them.
- **Backstage:** libraries listed went from **3 to 13**, and components from **33 to 54**.
- **Catalog entries:** every package in `packages/` now has one (13 packages, after splitting the folders that held several), up from 2 of 9 folders.

## Did it work for a new agent?

Numbers about copies say nothing about whether the next agent will find the shared code. So at the end of the day we ran an acceptance test. A fresh agent, with no history in the repo, was given five needs and only the repo to work with:

1. Print `argparse`-style `--help` in Rust exactly like the Python tool it replaces.
2. Produce Python's `json.dumps` output byte for byte, without serde.
3. Get Go's `filepath.Clean` behaviour in Rust.
4. Call an HTTP API from a standard-library-only Rust tool and pass a token safely.
5. Add crash reporting to a Mac app without the full Sentry SDK.

It found the right package for four of the five from `packages/README.md` alone. **It failed on the HTTP client.** The client existed, merged that afternoon, but neither its catalog entry nor its README mentioned HTTP, and the only search hit for "token" pointed at an authentication package for MCP servers, which is the wrong one. A shared package that nobody can find is not much better than no package. We fixed the description the same evening, and a Backstage search for "http curl token" now returns the right package.

The same test caught a worse gap: the conformance rule that refuses an uncatalogued package was not on `main` yet. The change carrying it had been rejected twice by the merge queue because an unrelated end-to-end test still expected the old, wider build visibility. Nobody had noticed. We fixed the test, and the rule landed that evening.

Both failures are why the acceptance test is worth running. Each was invisible from the pull requests themselves.

## What we did not fix

Some of this is still open, and some of it will stay that way.

- **Most JSON copies remain.** Only 2 of the 16 were safe to swap. A few others are deliberate copies or are built outside Bazel; most grew their own value and error types, so switching them would change every place that calls them. That is a rewrite, not a merge.
- **The `jq` copies stay.** There are seven small `jq` implementations, and they disagree on ten behaviours: key order, how `1.0` prints, error wording, line numbers in error messages, and more. One shared version cannot pass all seven tools' tests. Picking a winner means changing tool output on purpose, which is a separate decision.
- **Some tools cannot use shared code yet.** A few tools are built in CI with plain `rustc` outside Bazel, so they cannot link a shared crate without a workflow change. Those changes need a human's approval in our repo, by design, and are queued separately.
- **Two merges changed behaviour, on purpose.** The old copies of Python's "is this character printable?" check were hand-written guesses. The shared one uses Python's real table. That changes how **956,555 code points** print in three tools. Almost all of them are characters you will never see (unassigned, private-use and tag characters), and every spot-check matched Python 3. A smaller change of the same kind made the shared JSON printer escape a few rare characters the way Python does. Matching Python is the point of these tools, so we kept both changes and pinned them with tests. They are still changes, and we listed them in each pull request.
- **Agents cannot query Backstage unattended yet.** We wanted every agent to search the portal through its MCP server with a read-only token. Backstage's current backend refuses to delegate a token that is restricted to read permissions, so a read-only token cannot reach the catalog through that path. That work is parked. For now, agents read the generated `packages/README.md`, which holds the same information.
- **The duplicate check does not block merges yet.** It now runs on every pull request and merge-queue commit, and becomes a required check after it has run cleanly for a while.

## What we would tell another team

- **Make the shared code visible where the agent already looks.** For us that is one generated file at the top of `packages/`, plus a sentence in `AGENTS.md` that points at it. A portal is great for humans, but an agent reads files.
- **Generate the index and test for drift.** A hand-kept list is out of date the day after someone forgets it. Ours was.
- **Give every package a "when not to use it" section.** It is the line that stops an agent from bending the wrong package to fit.
- **Prove equivalence before you delete a copy.** Run the copy's own tests against the shared code. Where a copy has no tests, write them, run them against the old copy first, and keep them.
- **Measure with one tool at two commits.** Counting by hand, or with a tool you changed halfway through, gives numbers you cannot compare.
- **Test the outcome, not the plumbing.** Our checks were all green, and a fresh agent still could not find the HTTP client. Run the scenario the work is for.

Shared code is only shared if the next author can find it. With agents writing more of our code every week, that next author is usually a model that has never seen the repo before. Building for that reader made the repo easier for the rest of us too.
