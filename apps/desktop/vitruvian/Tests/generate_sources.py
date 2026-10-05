#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Compile selected production methods against test doubles, without an app.

Bodies are read verbatim on every build, never copied into a maintained fixture.
The narrow declaration/indentation contract fails closed if a method moves or
changes shape; the Swift compiler then checks the generated source normally.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build/generated-tests"


# A `package` modifier, after the indentation and any attributes, as code that
# moved into its own module spells it.
_PACKAGE_MODIFIER = re.compile(r"^( *(?:@[\w.]+(?:\([^()\n]*\))? +)*)package ", re.M)


def _source(path):
    """A production file's text as the extractions here expect it: without the
    `package` modifiers that its module needs and these copies do not. Each line
    keeps its number, so `#sourceLocation` still points at the right line."""
    return _PACKAGE_MODIFIER.sub(r"\1", (ROOT / path).read_text())


def declaration(path, prefix):
    lines = _source(path).splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.startswith(prefix)]
    if len(starts) != 1:
        raise ValueError(f"Expected one declaration {prefix!r} in {path}")
    start = starts[0]
    indent = prefix[:len(prefix) - len(prefix.lstrip())]
    end = next(i for i in range(start + 1, len(lines)) if lines[i].rstrip() == indent + "}")
    body = "".join(lines[start:end + 1])
    return f'#sourceLocation(file: {json.dumps(path)}, line: {start + 1})\n{body}\n#sourceLocation()\n'


_WRITTEN = set()


def write(name, text):
    _WRITTEN.add(name)
    path = OUTPUT / name
    if not path.exists() or path.read_text() != text:
        path.write_text(text)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    panel = "Sources/Vitruvian/App/AppDelegate.swift"
    write("MenuPanelRecovery.swift", "import AppKit\nimport Foundation\n"
          + "extension MenuPanelRecoveryTests {\nfinal class Host: Fixture {\n"
          + "".join(declaration(panel, prefix).replace("private ", "") for prefix in [
              "    private struct PanelAnchor", "    private func statusButtonMidX(",
              "    private func statusScreen(", "    private func positionSettingsWindow(",
              "    private var freshStatusClick:", "    private func captureStatusClick(",
              "    private func correctedPopoverMidX(", "    private func resolvePanelAnchor(",
              "    private func frameStillDescribesMenuBar(", "    private func statusFrameNeedsAnchorOverride(",
              "    private func anchorVisibleFrame(", "    private func applyPopoverDriftFrame(",
              "    private func beginPopoverDriftCorrection(window: NSWindow, anchor: PanelAnchor) {",
              "    private func armPopoverDriftCorrection(", "    private func endPopoverDriftCorrection(",
              "    private func showPopover(", "    func popoverWillClose(", "    func popoverDidClose(",
              "    private func releasePanelResources(", "    private func anchorAfterForeignClose(",
              "    private func reopenPanelAfterForeignClose(", "    private func shouldDismissPopover(",
              "    private func closePopoverNow("])
          + "var popoverAnchor: PanelAnchor?\nvar lastGoodPanelAnchor: PanelAnchor?\n"
          + "}\n}\n")
    scratchpad_service = "Sources/Vitruvian/Services/QuickTools/ScratchpadService.swift"
    scratchpad_view = "Sources/Vitruvian/UI/Notch/NotchScratchpadView.swift"
    write("NotchCompact.swift", "import AppKit\nimport SwiftUI\nextension NotchCompactTests {\n"
          + declaration("Sources/Vitruvian/Design/PlainTextEditor.swift", "struct PlainTextEditor:")
          + declaration(scratchpad_view, "struct NotchScratchpadView:")
          + "}\n"
          + "extension NotchCompactTests.ScratchpadService {\n"
          + declaration(scratchpad_service, "    func clear(")
          + "}\nextension NotchCompactTests.Floating {\n"
          + declaration(scratchpad_service, "    private func focusText(").replace("private func", "func", 1)
          + "}\nextension NotchCompactTests.Embedded {\n"
          + declaration(scratchpad_view, "    private func focusEditor(").replace("private func", "func", 1)
          + "}\n")
    factories = []
    pattern = r"static\s+func\s+(\w+)\s*\(\s*_\s+\w+:\s*AppLanguage\s*\)\s*->"
    for path in sorted((ROOT / "Sources/Vitruvian/Core").glob("*Strings.swift")):
        source = path.read_text()
        if "extension FeatureStrings" in source or "enum FeatureStrings" in source:
            scopes = re.findall(r"(?:extension|enum) FeatureStrings \{(.*?)^\}", source, re.S | re.M)
            names = [name for scope in scopes for name in re.findall(pattern, scope)]
            if not names:
                raise ValueError(f"No language factory found in {path}")
            factories.extend(names)
    if not factories or len(factories) != len(set(factories)):
        raise ValueError("Missing or duplicate localization factories")
    write("LocalizationCatalog.swift", "extension LocalizationTests {\n"
          + "static let factories: [(String, (AppLanguage) -> Any)] = [\n"
          + "".join(f'("{name}", {{ FeatureStrings.{name}($0) }}),\n' for name in factories)
          + "]\n}\n")
    # A copy no longer extracted must not linger for `build.sh`'s glob to compile.
    for stale in OUTPUT.glob("*.swift"):
        if stale.name not in _WRITTEN:
            stale.unlink()


if __name__ == "__main__":
    main()
