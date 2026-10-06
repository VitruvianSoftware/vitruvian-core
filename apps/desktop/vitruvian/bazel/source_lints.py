#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

"""Rules over how the app's sources and build scripts are written.

These ran inside the Swift unit tests, which read the whole Swift corpus,
`build.sh` and `Tools/uninstall.sh` as text to check them. They are lints,
not unit tests: they say how all of the code is written, not what one piece
of it does, so they run here, on any platform, and fail with the message the
unit test gave:

    bazel test //apps/desktop/vitruvian:source_lints_test

Three checks only a Mac can finish (that each SF Symbol the app draws exists,
that each system tool it runs is where it expects, and that every language
fills a localized format the same way) are split in two: this lint keeps the
lists in `Tests/SourceNames.swift` equal to what the sources spell, and
RepositoryFeatureTests checks each listed name on the Mac the tests run on.
"""

import argparse
import os
import re
import sys
from pathlib import Path

# Foundation's `.whitespaces`: tab and the Unicode space separators.
WHITESPACES = "\t                　"
# Foundation's `.whitespacesAndNewlines`.
WHITESPACES_AND_NEWLINES = WHITESPACES + "\n\u000b\u000c\r\u0085  "

APP_PREFIX = "Sources/Vitruvian/"
UI_PREFIX = "Sources/Vitruvian/UI/"


def trim(text):
    return text.strip(WHITESPACES)


def is_comment(line):
    return trim(line).startswith("//")


def code_without_comments(lines):
    """The lines that are not whole-line comments, so prose naming an API
    cannot answer for it."""
    return "\n".join(line for line in lines if not is_comment(line))


def basename(path):
    return path.rsplit("/", 1)[-1]


def dirname(path):
    return path.rsplit("/", 1)[0] if "/" in path else ""


def literal_after(piece):
    """The text up to the closing quote, or None when there is none."""
    end = piece.find('"')
    return None if end < 0 else piece[:end]


class Repository:
    """The app directory as the rules read it: every Swift source, the build
    script, the uninstall script, the resources and the name lists."""

    def __init__(self, app_dir):
        self.app_dir = Path(app_dir)
        paths = []
        for root, _, files in os.walk(self.app_dir / "Sources", followlinks=True):
            for name in files:
                if name.endswith(".swift"):
                    full = Path(root) / name
                    paths.append(full.relative_to(self.app_dir).as_posix())
        self.swift_paths = sorted(set(paths))
        self.sources = {}
        self.unreadable = []
        for path in self.swift_paths:
            try:
                self.sources[path] = (self.app_dir / path).read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as error:
                self.unreadable.append(f"{path}: {error}")
        self.lines = {path: text.split("\n") for path, text in self.sources.items()}
        tests = []
        for root, _, files in os.walk(self.app_dir / "Tests", followlinks=True):
            for name in files:
                if name.endswith(".swift"):
                    tests.append(
                        (Path(root) / name).relative_to(self.app_dir).as_posix()
                    )
        self.test_paths = sorted(set(tests))
        self.tests = {path: self.read_text(path) for path in self.test_paths}
        self.build_script = self.read_text("build.sh")
        self.uninstall_script = self.read_text("Tools/uninstall.sh")
        self.source_names = self.read_text("Tests/SourceNames.swift")
        resources = []
        for root, dirs, files in os.walk(self.app_dir / "Resources", followlinks=True):
            resources.extend(dirs)
            resources.extend(files)
        self.resource_names = resources

    def read_text(self, path):
        full = self.app_dir / path
        return full.read_text(encoding="utf-8") if full.exists() else ""

    def source(self, path):
        return self.sources.get(path, "")

    def lines_at(self, path):
        return self.lines.get(path, [])

    def app_sources(self):
        """The app's own sources, without Finder's " 2" copies."""
        return [
            p for p in self.swift_paths if p.startswith(APP_PREFIX) and " 2" not in p
        ]

    def ui_sources(self):
        return [p for p in self.swift_paths if p.startswith(UI_PREFIX)]

    def name_list(self, name):
        """A `static let <name>: [String]` list in Tests/SourceNames.swift."""
        match = re.search(
            r"static let " + re.escape(name) + r": \[String\] = \[(.*?)\n    \]",
            self.source_names,
            re.S,
        )
        return None if match is None else re.findall(r'"([^"\\]*)"', match.group(1))


# --- Repository-wide source rules ---------------------------------------------


def swift_sources_read_back(repo):
    """Every rule reads the sources as text, so a file it cannot read, or one
    with nothing in it, would pass every rule unread."""
    problems = []
    if not repo.swift_paths:
        problems.append("the Swift source corpus contains files")
    if repo.unreadable:
        problems.append(f"every Swift source is readable: {repo.unreadable}")
    empty = [
        path
        for path, text in repo.sources.items()
        if not text.strip(WHITESPACES_AND_NEWLINES)
    ]
    if empty:
        problems.append(f"no Swift source is empty: {empty}")
    return problems


def views_read_files_once(repo):
    """Reading a file is not a drawing step. The watermark logo was being
    decoded inside the preview's body, so every frame of an opacity drag
    re-read it from disk; it is loaded once per chosen file now, which is what
    a task is for."""
    found = []
    for path in repo.ui_sources():
        lines = repo.lines_at(path)
        for index, line in enumerate(lines):
            if "NSImage(contentsOfFile:" not in line and "Data(contentsOf:" not in line:
                continue
            around = lines[max(0, index - 6) : min(len(lines) - 1, index + 2) + 1]
            if not any(".task(" in x or "func " in x or "Task {" in x for x in around):
                found.append(f"{path}:{index + 1}")
    if found:
        return [f"a view reads a file once, never while drawing ({', '.join(found)})"]
    return []


def borderless_menus_keep_their_size(repo):
    """An unpinned borderless Menu claims the free width of its row on macOS 15
    and starves whatever shares that row (issue #569), so the rule is checked
    for every borderless menu in the app. Kill Process is the one deliberate
    exception: its row controls take a shared minimum width so the Kill button
    and the menu beside it line up down the list."""
    exception = "KillProcess/KillProcessView"
    ui_files = [p for p in repo.ui_sources() if " 2" not in p]
    unpinned = []
    for path in ui_files:
        if exception in path:
            continue
        file = path[len(UI_PREFIX) :]
        lines = repo.lines_at(path)
        for index, line in enumerate(lines):
            if ".menuStyle(.borderlessButton)" not in line:
                continue
            # Read to the end of the menu's own modifier chain: the next line
            # that is neither a modifier nor a comment belongs to something else.
            pinned = False
            for text in (trim(x) for x in lines[index + 1 :]):
                if not (text.startswith(".") or text.startswith("//")):
                    break
                if text.startswith(".fixedSize()"):
                    pinned = True
                    break
            if not pinned:
                unpinned.append(f"{file}:{index + 1}")
    if not ui_files or unpinned:
        return [
            f"every borderless menu keeps its own size, across {len(ui_files)} "
            f"scanned files: {unpinned}"
        ]
    return []


def operation_waits_have_deadlines(repo):
    """`waitUntilAllOperationsAreFinished` has no deadline, and the window walk
    that used it runs on the main thread while its operations run on the
    shared dispatch pool. Once unrelated work had taken every worker in that
    pool, not one operation started and the wait never returned, taking the
    whole app with it (issue #971)."""
    sources = repo.app_sources()
    found = [
        f"{path[len(APP_PREFIX) :]}:{index + 1}"
        for path in sources
        for index, line in enumerate(repo.lines_at(path))
        if "waitUntilAllOperationsAreFinished" in line
    ]
    if not sources or found:
        return [f"no operation queue is waited on without a deadline: {found}"]
    return []


def application_elements_are_not_asked_their_role(repo):
    """Asking an application element for its role switches a Chromium app's
    renderers into full accessibility mode for the rest of the process's life.
    The scan reports real line numbers, so comments are excluded in the
    predicate rather than removed from the source."""
    sources = repo.app_sources()
    found = []
    for path in sources:
        lines = repo.lines_at(path)
        elements = set()
        for line in lines:
            if "AXUIElementCreateApplication(" not in line:
                continue
            assigned = trim(line.split("=")[0]).split(" ")
            if len(assigned) == 2 and assigned[0] in ("let", "var"):
                elements.add(assigned[1])
        for index, line in enumerate(lines):
            if (
                "kAXRoleAttribute" in line
                and not is_comment(line)
                and any(f"({element}, " in line for element in elements)
            ):
                found.append(f"{path[len(APP_PREFIX) :]}:{index + 1}")
    if not sources or found:
        return [f"no application element is ever asked for its role: {found}"]
    return []


def parent_walks_stop_at_the_application(repo):
    """A walk up kAXParent reaches an application element without naming it,
    so every such walk must stop before asking that parent for its role."""
    sources = repo.app_sources()
    found = []
    for path in sources:
        lines = repo.lines_at(path)
        for index, line in enumerate(lines):
            if "role(of: parent)" not in line or is_comment(line):
                continue
            guarded = any(
                "isApplicationElement(parent)" in x and not is_comment(x)
                for x in lines[max(0, index - 3) : index]
            )
            if not guarded:
                found.append(f"{path[len(APP_PREFIX) :]}:{index + 1}")
    if not sources or found:
        return [f"a walk up the parent chain stops at the application element: {found}"]
    return []


def availability_is_written_where_the_gate_runs(repo):
    """Availability is only ever written by the runtime that gates it, so a new
    install surface cannot walk around the hardware check."""
    writers = sorted(
        {
            basename(path)
            for path in repo.swift_paths
            if any(".set(" in x and "availabilityKey" in x for x in repo.lines_at(path))
        }
    )
    expected = ["Defaults.swift", "FeaturePresets.swift", "FeatureRuntime.swift"]
    if writers != expected:
        return [
            "feature availability is written only where the hardware gate runs, "
            f"found {writers}"
        ]
    return []


def shelf_store_is_read_through_its_loader(repo):
    """A saved shelf may only be read through the loader that distinguishes an
    unreadable or partial store from a valid empty one."""
    found = sorted(
        basename(path)
        for path in repo.swift_paths
        if "decode([ShelfPersistedItem]" in repo.source(path)
    )
    if not repo.swift_paths or found:
        return [
            "the saved shelf is read only through ShelfPersistenceSupport.load, "
            f"found a bare decode in {found} across {len(repo.swift_paths)} scanned files"
        ]
    return []


def activation_is_yielded_through_the_handoff(repo):
    """Activation is yielded only through ActivationHandoff."""
    found = sorted(
        basename(path)
        for path in repo.swift_paths
        if basename(path) != "ActivationHandoff.swift"
        and "yieldActivation" in repo.source(path)
    )
    if not repo.swift_paths or found:
        return [
            "activation is yielded only through ActivationHandoff, "
            f"found a bare yield in {found} across {len(repo.swift_paths)} scanned files"
        ]
    return []


def tap_owners_invalidate_their_ports(repo):
    """Dropping the last Swift reference does not deregister an event tap;
    every literal tap creation needs a matching invalidation or removal."""
    owners = 0
    found = []
    for path in repo.app_sources():
        code = code_without_comments(repo.lines_at(path))
        taps = code.count("CGEvent.tapCreate")
        if taps == 0:
            continue
        owners += 1
        invalidations = code.count("CFMachPortInvalidate") + code.count(
            "PointerTapRunLoop.remove("
        )
        if invalidations < taps:
            found.append(
                f"{path[len(APP_PREFIX) :]} ({taps} taps, {invalidations} invalidated)"
            )
    if owners == 0 or found:
        return [
            "every event tap owner invalidates its port on teardown, across "
            f"{owners} scanned owners: {found}"
        ]
    return []


def keychain_is_never_touched(repo):
    """Query learning keeps its key and its digests in memory, and neither
    uninstall path removes a Keychain item: query learning and uninstall
    never access Keychain. The abandoned installation key is never asked
    for, not even to delete it."""
    found = []
    for path in repo.swift_paths:
        if not path.startswith(
            (
                "Sources/Vitruvian/Core/CommandBar/",
                "Sources/Vitruvian/Services/CommandBar/",
            )
        ):
            continue
        for needle in ("SecItem", "import Security"):
            if needle in repo.source(path):
                found.append(f"{basename(path)}: {needle}")
    for path in repo.swift_paths:
        if "removeInstallationKey" in repo.source(path):
            found.append(f"{basename(path)}: removeInstallationKey")
    if not repo.uninstall_script:
        found.append("Tools/uninstall.sh is unreadable")
    elif "delete-generic-password" in repo.uninstall_script:
        found.append("Tools/uninstall.sh: delete-generic-password")
    if found:
        return [f"query learning and uninstall never access Keychain: {found}"]
    return []


# --- Localization -------------------------------------------------------------


def visible_text_curls_its_apostrophes(repo):
    """Visible localization source uses typographic apostrophes rather than
    typewriter marks."""
    paths = [
        path
        for path in repo.swift_paths
        if dirname(path)
        in ("Sources/Vitruvian/Core", "Sources/Vitruvian/Core/Localizations")
        and (
            basename(path).endswith("Strings.swift")
            or basename(path).startswith("Strings+")
            or basename(path) == "Localization.swift"
        )
    ]
    found = []
    for path in paths:
        for index, line in enumerate(repo.lines_at(path)):
            if is_comment(line):
                continue
            opening, closing = line.find('"'), line.rfind('"')
            if opening < 0 or opening >= closing:
                continue
            if "'" in line[opening:closing]:
                found.append(f"{path}:{index + 1}")
    if found:
        return [f"visible text curls its apostrophes ({', '.join(found[:6])})"]
    return []


def _declaration_text(line):
    """Declarations in a module of their own also say `package`, which the
    block search reads past."""
    trimmed = trim(line)
    return trimmed[len("package ") :] if trimmed.startswith("package ") else trimmed


def _french_lines(repo, path):
    lines = repo.lines_at(path)
    if path.endswith("Strings+French.swift"):
        return lines
    start = next(
        (
            i
            for i, x in enumerate(lines)
            if _declaration_text(x).startswith("static let fr = ")
        ),
        None,
    )
    if start is None:
        return []
    end = next(
        (
            i
            for i in range(start + 1, len(lines))
            if _declaration_text(lines[i]).startswith("static let ")
        ),
        len(lines),
    )
    return lines[start:end]


def french_punctuation_stays_on_its_line(repo):
    """French double punctuation and guillemets use non-breaking spaces."""
    sources = [
        path
        for path in repo.swift_paths
        if path == "Sources/Vitruvian/Core/Localizations/Strings+French.swift"
        or (
            dirname(path) == "Sources/Vitruvian/Core" and path.endswith("Strings.swift")
        )
    ]
    breaks = [" ;", " :", " !", " ?", " »", "« "]
    breaking = []
    missed = []
    scanned = 0
    for path in sources:
        block = _french_lines(repo, path)
        scanned += len(block)
        if not block and "let fr = " in repo.source(path):
            missed.append(basename(path))
        for line in block:
            if is_comment(line):
                continue
            opening, closing = line.find('"'), line.rfind('"')
            if opening < 0 or opening >= closing:
                continue
            body = line[opening + 1 : closing]
            if any(mark in body for mark in breaks):
                breaking.append(basename(path))
    problems = []
    if breaking:
        problems.append(
            "French keeps its punctuation on the line it belongs to "
            f"({', '.join(sorted(set(breaking))[:4])})"
        )
    if scanned == 0 or missed:
        problems.append(
            f"the French check reads every French block, {scanned} lines scanned, "
            f"missed {sorted(missed)[:4]}"
        )
    return problems


def decimals_name_their_region(repo):
    """Every formatted decimal explicitly chooses its locale. Long calls may
    put that locale on either of the next two lines."""
    found = []
    for path in repo.swift_paths:
        lines = repo.lines_at(path)
        for index, line in enumerate(lines):
            if "String(format:" not in line:
                continue
            statement = "".join(lines[index : min(index + 2, len(lines) - 1) + 1])
            if "locale:" in statement:
                continue
            pieces = line.split("String(format:")
            piece = pieces[1] if len(pieces) > 1 else ""
            parts = piece.split('"')
            format_text = parts[1] if len(parts) > 1 else ""
            if "f" in format_text and "%" in format_text:
                found.append(f"{path}:{index + 1}")
    if found:
        return [f"a decimal on screen names its region ({', '.join(found)})"]
    return []


def format_fields(repo):
    """The localized fields that reach String(format:): the last name of the
    expression before the first argument."""
    fields = set()
    for path in repo.swift_paths:
        for piece in repo.source(path).split("String(format:")[1:]:
            head = piece[:120]
            comma = head.find(",")
            if comma < 0:
                continue
            expression = head[:comma]
            dot = expression.rfind(".")
            if dot < 0:
                continue
            name = expression[dot + 1 :].strip(WHITESPACES_AND_NEWLINES)
            if name and all(c.isalpha() or c.isnumeric() for c in name):
                fields.add(name)
    return fields


def system_symbol_names(repo):
    """Every literal SF Symbol name the app draws."""
    names = set()
    for path in repo.swift_paths:
        for piece in repo.source(path).split('systemName: "')[1:]:
            name = literal_after(piece)
            if name and "\\" not in name:
                names.add(name)
    return names


def system_tool_paths(repo):
    """Every absolute command-line tool path embedded in Swift."""
    tools = set()
    for path in repo.swift_paths:
        for piece in repo.source(path).split('"/')[1:]:
            rest = literal_after(piece)
            if rest is None:
                continue
            candidate = "/" + rest
            if not candidate.startswith(("/bin/", "/usr/bin/", "/usr/sbin/")):
                continue
            if " " in candidate or "\\" in candidate:
                continue
            tools.add(candidate)
    return tools


def _listed(repo, list_name, found, minimum, what, message):
    """`found` must have at least `minimum` names, and Tests/SourceNames.swift
    must list exactly those, so the unit tests check each one on a Mac."""
    problems = []
    if len(found) < minimum:
        problems.append(f"{what} were found ({len(found)})")
    listed = repo.name_list(list_name)
    if listed is None:
        return problems + [f"Tests/SourceNames.swift lists {list_name} for: {message}"]
    missing = sorted(found - set(listed))
    stale = sorted(set(listed) - found)
    if missing or stale or len(listed) != len(set(listed)):
        problems.append(
            f"{message}: Tests/SourceNames.swift lists in {list_name} what the sources "
            f"spell, so the unit tests can check each one; add {missing}, remove {stale}"
            + (", once each" if len(listed) != len(set(listed)) else "")
        )
    return problems


def every_language_fills_a_format_the_same_way(repo):
    """Only localized fields that reach String(format:) need matching
    placeholders in every language. The comparison runs in the unit tests,
    over the fields listed here."""
    return _listed(
        repo,
        "formatFields",
        format_fields(repo),
        11,
        "the format fields",
        "every language fills a format the same way",
    )


def every_symbol_the_app_draws_exists(repo):
    """Every literal SF Symbol name resolves on the test system. The unit
    tests ask the system for each listed name."""
    return _listed(
        repo,
        "symbols",
        system_symbol_names(repo),
        81,
        "the symbol names",
        "every symbol the app draws exists",
    )


def every_system_tool_is_where_it_is_expected(repo):
    """Absolute command-line tool paths embedded in Swift must exist. The unit
    tests look for each listed path."""
    return _listed(
        repo,
        "systemTools",
        system_tool_paths(repo),
        15,
        "the system tools",
        "every system tool the app runs is where it expects",
    )


def every_named_resource_is_shipped(repo):
    """Every literal resource name requested by Swift is shipped or staged by
    the build."""
    named = set()
    for path in repo.swift_paths:
        text = repo.source(path)
        for marker in ('url(forResource: "', 'path(forResource: "', 'NSImage(named: "'):
            for piece in text.split(marker)[1:]:
                name = literal_after(piece)
                if name and "\\" not in name:
                    named.add(name)
    problems = []
    if len(named) < 5:
        problems.append(f"the named resources were found ({len(named)})")
    if not repo.build_script:
        problems.append("the build script reads back for its resource names")
    shipped = {"CHANGELOG"}
    words = re.split(r"[ \n\t\"'()]", repo.build_script)
    for file in repo.resource_names + [w.rstrip("/").rsplit("/", 1)[-1] for w in words]:
        if not file:
            continue
        shipped.add(file)
        shipped.add(os.path.splitext(file)[0])
    absent = sorted(n for n in named if n not in shipped)
    if absent:
        problems.append(
            f"every file the app asks for by name is in the bundle ({', '.join(absent)})"
        )
    return problems


def embedded_scripts_close_what_they_open(repo):
    """Embedded Finder scripts are compiled only when they run, so every
    multiline tell/repeat block has to balance here."""
    found = []
    for path in repo.swift_paths:
        chunks = repo.source(path).split('"""')
        for offset, chunk in enumerate(chunks):
            if offset % 2 == 0 or "tell application" not in chunk:
                continue
            body = [trim(x) for x in chunk.split("\n")]

            def unbalanced(word, closing, inline):
                started = sum(
                    1 for x in body if x.startswith(word + " ") and not inline(x)
                )
                ended = sum(1 for x in body if x == closing)
                return started != ended

            if unbalanced("tell", "end tell", lambda x: " to " in x):
                found.append(f"{basename(path)}:tell")
            if unbalanced("repeat", "end repeat", lambda x: False):
                found.append(f"{basename(path)}:repeat")
    if found:
        return [f"every embedded script closes what it opens ({', '.join(found)})"]
    return []


def stores_delete_only_what_they_own(repo):
    """User-file stores delete only paths whose ownership is established in the
    local scope immediately before removal."""
    guards = [
        "isShelfOwnedFile",
        "discardablePaths",
        "ownedPayloadURLs",
        "isRegularFile",
        "tempDir",
        "legacyDir",
        "root",
        "uuidString",
        "storeRoot",
        "contentsOfDirectory",
    ]
    problems = []
    found = []
    for path in [
        "Sources/Vitruvian/Services/Shelf/ShelfService.swift",
        "Sources/Vitruvian/Services/QuickTools/RecentCaptureService.swift",
        "Sources/Vitruvian/Services/QuickTools/RecentCaptureStore.swift",
    ]:
        lines = repo.lines_at(path)
        if not lines:
            problems.append(
                f"the store source reads back for its deletion check ({path})"
            )
        for index, line in enumerate(lines):
            if "removeItem(at:" not in line:
                continue
            scope = "\n".join(lines[max(0, index - 10) : index + 1])
            if not any(guard in scope for guard in guards):
                found.append(f"{basename(path)}:{index + 1}")
    if found:
        problems.append(
            f"a file is deleted only after the app checks it owns it ({', '.join(found)})"
        )
    return problems


# --- Pointer input --------------------------------------------------------------

# The tap owners cannot be reached from the unit tests (they need the event
# chain), so the wiring is checked here: each service follows the session and
# asks before re-arming a tap the window server disabled.
SESSION_TAP_OWNERS = [
    "Sources/Vitruvian/Services/ScrollInverter.swift",
    "Sources/Vitruvian/Services/SmoothScrollService.swift",
    "Sources/Vitruvian/Services/MouseNavigation/MouseNavigationService.swift",
    "Sources/Vitruvian/Services/MouseButtons/MouseButtonShortcutService.swift",
    "Sources/Vitruvian/Services/MiddleClick/MiddleClickService.swift",
    "Sources/Vitruvian/Services/QuitProtection/QuitProtectionService.swift",
    "Sources/Vitruvian/Services/RadialMenu/RadialMenuService.swift",
    "Sources/Vitruvian/Services/WindowLayout/WindowLayoutService.swift",
    "Sources/Vitruvian/Services/WindowMaximizer.swift",
    "Sources/Vitruvian/Services/Finder/FinderCutPaste.swift",
    "Sources/Vitruvian/Services/Finder/FinderRenameService.swift",
    "Sources/Vitruvian/Services/KeyboardDebounce/KeyboardDebounceService.swift",
    "Sources/Vitruvian/Services/SuperKey/SuperKeyService.swift",
    "Sources/Vitruvian/Services/ShortcutRecordingTap.swift",
    "Sources/Vitruvian/Services/Switcher/AppSwitcher.swift",
    "Sources/Vitruvian/Services/Snippets/TextSnippetService.swift",
    "Sources/Vitruvian/Services/Audio/PreciseVolumeRollerService.swift",
    "Sources/Vitruvian/Services/DockClick/DockClickService.swift",
    "Sources/Vitruvian/Services/Display/BrightnessService.swift",
]

# The taps that change or swallow events: one kept alive after Accessibility
# is lost holds input it can no longer hand on.
MODIFYING_TAP_OWNERS = [
    "MouseNavigation",
    "MouseButtonShortcut",
    "MiddleClick",
    "QuitProtection",
    "RadialMenu",
    "ShortcutRecordingTap",
]

# The taps that filter ordinary clicks and wheel events are served by a thread
# of their own. On the main run loop each of those events waits for whatever
# this app is drawing or asking Accessibility, which is felt as click lag in
# whatever app is in front.
POINTER_THREAD_TAP_OWNERS = [
    "Sources/Vitruvian/Services/ScrollInverter.swift",
    "Sources/Vitruvian/Services/MiddleClick/MiddleClickService.swift",
]


def tap_owners_follow_the_session(repo):
    """Comments are stripped so prose naming the API cannot answer for it."""
    problems = []
    for owner in SESSION_TAP_OWNERS:
        source = repo.source(owner)
        if not source:
            problems.append(f"{owner} reads back for its session-switch check")
            continue
        code = code_without_comments(source.split("\n"))
        if "SessionActivity.shared.onChange" not in code:
            problems.append(f"{owner} rebuilds its tap when the session comes back")
        rearm = code.split("tapDisabledByTimeout")
        rearm = rearm[1].split("return")[0] if len(rearm) > 1 else ""
        if "SessionActivity.shared.isActive" not in rearm:
            problems.append(
                f"{owner} does not re-arm a disabled tap into a switched-away session"
            )
        if (
            any(name in owner for name in MODIFYING_TAP_OWNERS)
            and "AXIsProcessTrusted()" not in rearm
        ):
            problems.append(
                f"{owner} does not keep a modifying tap alive after Accessibility is lost"
            )
        # Switching a tap off leaves the process owning it, which is what the
        # window server waits on; teardown must invalidate the port, either
        # here or through the pointer thread that owns the source.
        if (
            "CFMachPortInvalidate" not in code
            and "PointerTapRunLoop.remove(" not in code
        ):
            problems.append(f"{owner} hands its tap back rather than only disabling it")
    return problems


def pointer_taps_run_off_the_main_thread(repo):
    problems = []
    for owner in POINTER_THREAD_TAP_OWNERS:
        code = code_without_comments(repo.lines_at(owner))
        if "PointerTapRunLoop.add(" not in code:
            problems.append(f"{owner} serves its tap on the pointer thread")
        if "CFRunLoopGetMain()" in code:
            problems.append(f"{owner} keeps its tap off the main run loop")
    return problems


def inverter_does_not_yield_to_the_switcher(repo):
    """The scroll inverter is the one wheel tap that does not step aside for
    the App Switcher: an open switcher still moves the way the wheel is
    turned. The smooth scroller and the side-wheel shortcuts yield, through
    the environment their tests drive; the inverter is handed nothing that
    names the switcher, and never asks it."""
    code = code_without_comments(
        repo.lines_at("Sources/Vitruvian/Services/ScrollInverter.swift")
    )
    if (
        not code
        or "scrollNavigationActive" in code
        or "switcherNavigatesByWheel" in code
    ):
        return [
            "scroll direction still transforms wheel events before they reach the open switcher"
        ]
    return []


def cleaning_mode_never_synthesizes_mouse_events(repo):
    """Cleaning Mode only watches mouse clicks pass: nothing in the manager
    posts a mouse event, and nothing reads the global button state, which
    cannot say which press the lock itself saw."""
    code = code_without_comments(
        repo.lines_at(
            "Sources/Vitruvian/Services/CleaningMode/CleaningModeManager.swift"
        )
    )
    problems = []
    if not code:
        problems.append("the cleaning mode source reads back for its absence checks")
    if "CGEvent(mouseEventSource:" in code:
        problems.append("Cleaning Mode never synthesizes a global mouse release")
    if "pressedMouseButtons" in code or "CGEventSource.buttonState" in code:
        problems.append(
            "Cleaning Mode does not infer ownership from a global button-state snapshot"
        )
    return problems


def brightness_work_queue_never_touches_nsscreen(repo):
    """Every section of BrightnessService below its "Rebuild (work queue)"
    mark runs on the private work queue. A display's name is read from
    NSScreen on the main thread and handed to the rebuild; AppKit reached
    from below the line would be a main thread violation on every hotplug,
    wake and panel open."""
    source = repo.source("Sources/Vitruvian/Services/Display/BrightnessService.swift")
    marker = "// MARK: - Rebuild (work queue)"
    half = source.split(marker)[-1] if marker in source else ""
    code = code_without_comments(half.split("\n"))
    if not half or "NSScreen" in code:
        return [
            "the brightness work queue resolves display names without touching NSScreen"
        ]
    return []


def click_debounce_schedules_nothing(repo):
    """The click filter answers each click as it arrives: the service itself
    schedules nothing, so a healthy click is never held back by a timer."""
    code = code_without_comments(
        repo.lines_at(
            "Sources/Vitruvian/Services/MouseClickDebounce/MouseClickDebounceService.swift"
        )
    )
    if not code or "Timer(" in code or "asyncAfter" in code:
        return [
            "legacy click filtering adds no timer or delayed release to healthy clicks"
        ]
    return []


def smooth_scroll_disabled_tap_rearms_only_when_wanted(repo):
    """A smooth-scroll tap the system switched off ends its glide, and is put
    back only while the feature is installed and on, Accessibility is
    granted and this session is the one on screen."""
    code = code_without_comments(
        repo.lines_at("Sources/Vitruvian/Services/SmoothScrollService.swift")
    )
    pieces = code.split("tapDisabledByTimeout")
    branch = pieces[1].split("return")[0] if len(pieces) > 1 else ""
    wanted = [
        "tapDisabledByUserInput",
        "stopGlide()",
        "AppFeature.smoothScroll.isAvailable",
        "Preferences.smoothScrollEnabled",
        "AXIsProcessTrusted()",
        "SessionActivity.shared.isActive",
    ]
    if not all(piece in branch for piece in wanted):
        return [
            "a disabled smooth-scroll tap drops its tail and re-arms only while fully wanted"
        ]
    return []


def menu_panel_switches_have_names(repo):
    """A switch with a hidden label still gives VoiceOver its title, so an
    empty one is read out as an unnamed switch. The menu panel names every
    switch it draws."""
    code = code_without_comments(
        repo.lines_at("Sources/Vitruvian/UI/MenuPanel/MenuPanelView.swift")
    )
    if not code:
        return ["the menu panel source reads back"]
    unnamed = code.count('Toggle("", isOn:')
    if unnamed:
        return [
            f"every menu panel switch has a name for VoiceOver, found {unnamed} unnamed"
        ]
    return []


def path_identity_rule_is_spelled_once(repo):
    """The leading-slash test IS the rule that tells a stored path from a
    bundle identifier. A second spelling of it drifts the day the rule learns
    a new shape (a ~ path, a file URL), so every file that handles an identity
    asks isExecutablePathIdentity instead of re-testing the prefix."""
    sites = []
    for file in [
        "Core/MouseExceptions/MouseAppExceptionSupport.swift",
        "Services/InstalledApps.swift",
        "Core/Defaults.swift",
    ]:
        lines = repo.lines_at(APP_PREFIX + file)
        if len(lines) <= 1:
            sites.append(f"{file} unreadable")
        for index, line in enumerate(lines):
            if not is_comment(line) and 'hasPrefix("/")' in line:
                sites.append(f"{file}:{index + 1}")
    if len(sites) != 1 or not sites[0].startswith(
        "Core/MouseExceptions/MouseAppExceptionSupport.swift:"
    ):
        return [
            f"the leading-slash rule is spelled once, inside isExecutablePathIdentity: {sites}"
        ]
    return []


# --- build.sh -----------------------------------------------------------------


def build_sweeps_its_temp_dirs(repo):
    """`mktemp -d` lands outside the repo, so a dir the script does not remove
    survives the run, a successful one as much as a failed one. The sweep is
    therefore a trap, and a staging dir added later leaks on every build until
    it is named in cleanup(). The names are read out of the script so the two
    cannot drift apart."""
    script = repo.build_script
    if not script:
        return ["build.sh is readable for repository contracts"]
    problems = []
    # The trap has to be installed before the first dir exists: a failure
    # between `mktemp -d` and a later `trap` leaks exactly as before.
    sweep = script.find("trap cleanup EXIT")
    first_staged = script.find("mktemp -d")
    if sweep < 0 or first_staged < 0 or not sweep < first_staged:
        problems.append(
            "build.sh installs the temp dir sweep before it stages the first dir"
        )
    # zsh runs the EXIT trap on HUP but not on INT or TERM, so the signals
    # have to reach it through `exit` or Ctrl-C leaks the staged bundle.
    signals = script.find("trap 'exit 1' INT TERM HUP")
    if signals < 0 or first_staged < 0 or not signals < first_staged:
        problems.append(
            "build.sh routes interrupts through the sweep before it stages the first dir"
        )
    cleanup = script.split("cleanup() {")
    cleanup_body = cleanup[1].split("\n}")[0] if len(cleanup) > 1 else ""
    staged = []
    for piece in script.split('="$(mktemp -d)"')[:-1]:
        tokens = [t for t in re.split(r"[\n\r\u000b\u000c\u0085   \t]", piece) if t]
        if tokens:
            staged.append(tokens[-1])
    if not staged:
        problems.append("the staged temp dirs read back out of build.sh")
    # A dir reached through a path suffix, `X="$(mktemp -d)/name"`, puts the
    # parent in no variable at all, which is how the bundle staging dir leaked.
    # Every call has to be captured whole to be sweepable.
    if script.count("mktemp -d") != len(staged):
        problems.append(
            "every mktemp -d in build.sh is a whole capture — no path suffix, no other spelling"
        )
    for variable in sorted(set(staged)):
        if f'"${variable}"' not in cleanup_body:
            problems.append(f"temp dir {variable} is swept by build.sh cleanup()")
        # The sweep runs under `set -u` before the dir is staged: an entry whose
        # variable is not empty first aborts cleanup() at that line, leaving
        # everything listed below it unswept and the exit status untouched. The
        # leading newline keeps ICON_TMP off STAGE_ICON_TMP.
        initialized = script.find(f'\n{variable}=""')
        if initialized < 0 or sweep < 0 or not initialized < sweep:
            problems.append(
                f"temp dir {variable} is empty before the sweep is installed"
            )
    return problems


def build_signs_with_a_stable_identity(repo):
    """An ad-hoc signature changes hash on every build, so macOS orphans
    Accessibility and Screen Recording grants on each rebuild while System
    Settings keeps showing them as granted. build.sh therefore routes
    identity-less installs through Tools/setup-signing.sh before signing."""
    script = repo.build_script
    if not script:
        return ["build.sh is readable for repository contracts"]
    lines = script.split("\n")
    problems = []
    # The invocation at the start of a command line: the ad-hoc fallback's
    # advice string also names the script, and must not satisfy this check.
    if not any(
        re.search(r"^\s*(if\s+!?\s*)?\./Tools/setup-signing\.sh", x) for x in lines
    ):
        problems.append(
            "an identity-less build that installs invokes Tools/setup-signing.sh itself"
        )
    code = [x for x in lines if not trim(x).startswith("#")]
    # The guard is on the install, not on the variant: a plain --install
    # replaces the bundle under the released id, so it strands the grants on
    # the app people actually use. CI never passes --install.
    if not any(
        "(( DEV || INSTALL ))" in x and "developer_id_identity" in x for x in code
    ):
        problems.append(
            "the signing setup guard covers every install, not only the Developer variant"
        )
    # A find-identity listing names certificates codesign then rejects, and -v
    # excludes every self-signed one, so neither spelling may decide.
    if any("find-identity" in x and "$LEGACY_IDENTITY" in x for x in code):
        problems.append(
            "build.sh never decides the stable identity by a find-identity listing"
        )
    if not (
        any("cp /bin/echo" in x for x in code)
        and any('--sign "$LEGACY_IDENTITY" "$probe"' in x for x in code)
    ):
        problems.append(
            "build.sh asks codesign to sign a throwaway copy of /bin/echo with the stable identity"
        )
    return problems


# --- The tests themselves -----------------------------------------------------

# Declarations of a type, at any depth, as the Swift scanner read them: the
# leading space, any attributes and modifiers, the keyword and the name.
# `class func` and the like are members, not types.
DECLARATION = re.compile(
    r"^(\s*)(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:(?:private|fileprivate|internal|public|package|final|nonisolated|indirect|open)\s+)*"
    r"(?:class|struct|enum|actor|protocol|typealias)\s+(?!func\b|var\b|let\b|subscript\b|init\b)([A-Za-z_]\w*)"
)
DECLARATION_KEYWORDS = (
    "class ",
    "struct ",
    "enum ",
    "actor ",
    "protocol ",
    "typealias ",
)
# The Foundation types tests used to fake, beside the framework prefixes.
FAKED_FOUNDATION_TYPES = {
    "UserDefaults",
    "NotificationCenter",
    "DistributedNotificationCenter",
    "Bundle",
    "ProcessInfo",
    "FileManager",
    "RunLoop",
    "Timer",
    "Thread",
    "OperationQueue",
    "URLSession",
    "Date",
    "URL",
    "Data",
    "Calendar",
    "Locale",
}


def declarations(text):
    """Each type declared in `text`, as (name, indented)."""
    found = []
    for line in text.split("\n"):
        if not any(keyword in line for keyword in DECLARATION_KEYWORDS):
            continue
        match = DECLARATION.match(line)
        if match:
            found.append((match.group(2), match.group(1) != ""))
    return found


def is_system_name(name):
    if name in FAKED_FOUNDATION_TYPES:
        return True
    return any(
        name.startswith(prefix) and name[len(prefix) :][:1].isupper()
        for prefix in ("NS", "CG", "CF", "AX", "Dispatch")
    )


def test_types_do_not_shadow_real_ones(repo):
    """No test declares a type named after a system type or one of the app's
    own top-level types (REFACTOR.md step 4). A stand-in named like the real
    thing shadows it for every line around it, which is how tests used to fake
    a service's collaborators; the services now take them instead."""
    problems = []
    sample = declarations(
        "\n".join(
            [
                "package final class Island {",
                "    nonisolated enum DispatchQueue { static var main = 0 }",
                "    @MainActor final class Window {}",
                "    class func make() {}",
                "    private typealias Moment = Double",
                "}",
            ]
        )
    )
    if sample != [
        ("Island", False),
        ("DispatchQueue", True),
        ("Window", True),
        ("Moment", True),
    ]:
        problems.append(
            "the scan finds nested and attributed declarations, and not class members"
        )
    if not (
        all(
            map(
                is_system_name,
                [
                    "NSScreen",
                    "NSEvent",
                    "CGSConnectionID",
                    "DispatchQueue",
                    "UserDefaults",
                    "Bundle",
                ],
            )
        )
        and not any(
            map(
                is_system_name,
                ["Display", "Pointer", "Clock", "Switches", "NSome", "Bundler"],
            )
        )
    ):
        problems.append(
            "system names are the framework prefixes and the Foundation types tests used to fake"
        )
    production = {
        name
        for path in repo.swift_paths
        for name, indented in declarations(repo.source(path))
        if not indented
    }
    if len(production) <= 100 or len(repo.test_paths) <= 100:
        problems.append("the sources and the tests read back from the app directory")
    shadows = [
        f"{path}: {name}"
        for path in repo.test_paths
        for name, _ in declarations(repo.tests[path])
        if name in production or is_system_name(name)
    ]
    if shadows:
        problems.append(
            f"no test type shadows a system type or one of the app's own: {shadows}"
        )
    return problems


# What reading a file looks like in a test. `contentsOfFile` is never the
# way a test reaches a resource any more; a path into Sources/ is never a
# test's business at all.
SOURCE_READS = ("contentsOf" + "File", '"Sources/', '"Sources"')


def source_reads(path, text):
    """Each line of a test that reads a source file as text, outside string
    literals and comments."""
    found = []
    for number, line in enumerate(text.split("\n"), start=1):
        if is_comment(line):
            continue
        for needle in SOURCE_READS:
            at = line.find(needle)
            # A mention inside a string literal is not a read: count the
            # quotes before it, the way the ledger before this rule did.
            if at >= 0 and line[:at].count('"') % 2 == 0:
                found.append(f"{path}:{number}")
                break
    return found


def unit_tests_read_no_source_text(repo):
    """The unit tests run the code; none reads a source file as text
    (REFACTOR.md step 7). How the code is written is checked here, by the
    rules above, and nowhere in the tests."""
    problems = []
    sample = "\n".join(
        [
            "let text = try? String("
            + "contentsOf"
            + 'File: "Sources/Vitruvian/App/AppDelegate.swift")',
            "let files = FileManager.default.enumerator(atPath: " + '"Sources")',
            '// a comment naming "Sources/Vitruvian" reads nothing',
            'suite.expect(true, "a message about '
            + "contentsOf"
            + 'File reads nothing")',
        ]
    )
    if source_reads("sample", sample) != ["sample:1", "sample:2"]:
        problems.append(
            "the scan finds a source read and a walk of Sources/, and not prose"
        )
    if not repo.test_paths:
        problems.append("the tests read back from the app directory")
    reads = [
        read
        for path in repo.test_paths
        for read in source_reads(path, repo.tests[path])
    ]
    if reads:
        problems.append(f"no unit test reads a source file as text, found {reads}")
    return problems


# --- Preferences ----------------------------------------------------------------

PREFERENCES_PATH = APP_PREFIX + "Core/Preferences.swift"
# Registration, and the migrations that run before it: they read what is
# stored, not what a preference falls back to, so they reach keys by name.
KEYED_PREFERENCE_PATHS = {
    APP_PREFIX + "Core/Defaults.swift",
    APP_PREFIX + "Core/DefaultsKey.swift",
    PREFERENCES_PATH,
}

# How many times the sources still reach a declared preference by its
# `DefaultsKey`, by the `UserDefaults` call that does it (REFACTOR.md
# step 8). A slice that moves some to `UserDefaults[Preferences.x]` lowers
# its count here. The rule fails on one more, so no new access by key comes
# in, and on one fewer, so each count stays exact.
PREFERENCE_ACCESS_BY_KEY = {
    "array": 2,
    "bool": 0,
    "data": 8,
    "dictionary": 6,
    "double": 0,
    "integer": 0,
    "object": 25,
    "removeObject": 18,
    "set": 66,
    "string": 117,
    "stringArray": 18,
}


def _call_name(text, at):
    """The name of the call whose parentheses hold position `at`."""
    depth = 0
    for index in range(at - 1, -1, -1):
        character = text[index]
        if character == ")":
            depth += 1
        elif character == "(":
            if depth == 0:
                match = re.search(r"(\w+)\s*$", text[:index])
                return match.group(1) if match else None
            depth -= 1
    return None


def keyed_preference_access(text, declared):
    """How many times `text` hands a key in `declared` to one of the
    `UserDefaults` calls the ledger lists, by call name. Whole-line comments
    do not count, nor a dictionary keyed by the name."""
    code = code_without_comments(text.split("\n"))
    counts = {}
    for match in re.finditer(r"forKey:\s*DefaultsKey\.(\w+)", code):
        if match.group(1) not in declared:
            continue
        name = _call_name(code, match.start())
        if name in PREFERENCE_ACCESS_BY_KEY:
            counts[name] = counts.get(name, 0) + 1
    return counts


def preferences_are_reached_through_their_type(repo):
    """Code reads and writes a declared preference through its `Preference`,
    `UserDefaults[Preferences.x]`, so the value has the preference's type and
    falls back to its declared default. Only registration and the migrations
    before it reach a declared key by name (REFACTOR.md step 8)."""
    problems = []
    sample = "\n".join(
        [
            "let a = defaults.bool(forKey: DefaultsKey.alpha)",
            "defaults.set(min(1, 2), forKey: DefaultsKey.alpha)",
            "let b = defaults.string(",
            '    forKey: DefaultsKey.alpha) ?? ""',
            "// defaults.bool(forKey: DefaultsKey.alpha) in prose",
            "let c = defaults[Preferences.alpha]",
            "let d = defaults.bool(forKey: DefaultsKey.undeclared)",
            "values.removeValue(forKey: DefaultsKey.alpha)",
        ]
    )
    if keyed_preference_access(sample, {"alpha"}) != {
        "bool": 1,
        "set": 1,
        "string": 1,
    }:
        problems.append(
            "the scan counts each UserDefaults call by name across lines, and "
            "not prose, typed reads, undeclared keys or a dictionary"
        )
    declared = set(
        re.findall(
            r"=\s*Preference(?:<[^>]+>)?\(\s*DefaultsKey\.(\w+)",
            repo.source(PREFERENCES_PATH),
        )
    )
    if not declared:
        problems.append("the preferences read back from Core/Preferences.swift")
    counts = {}
    for path in repo.app_sources():
        if path in KEYED_PREFERENCE_PATHS:
            continue
        for name, count in keyed_preference_access(repo.source(path), declared).items():
            counts[name] = counts.get(name, 0) + count
    for name, allowed in sorted(PREFERENCE_ACCESS_BY_KEY.items()):
        found = counts.get(name, 0)
        if found > allowed:
            problems.append(
                f"{found} {name}(forKey: DefaultsKey.…) on declared preferences, "
                f"{allowed} allowed: use UserDefaults[Preferences.x]"
            )
        elif found < allowed:
            problems.append(
                f"{found} {name}(forKey: DefaultsKey.…) on declared preferences: "
                f"lower PREFERENCE_ACCESS_BY_KEY[{name!r}] from {allowed}"
            )
    return problems


RULES = [
    swift_sources_read_back,
    views_read_files_once,
    borderless_menus_keep_their_size,
    operation_waits_have_deadlines,
    application_elements_are_not_asked_their_role,
    parent_walks_stop_at_the_application,
    availability_is_written_where_the_gate_runs,
    shelf_store_is_read_through_its_loader,
    activation_is_yielded_through_the_handoff,
    tap_owners_invalidate_their_ports,
    keychain_is_never_touched,
    visible_text_curls_its_apostrophes,
    french_punctuation_stays_on_its_line,
    decimals_name_their_region,
    every_language_fills_a_format_the_same_way,
    every_symbol_the_app_draws_exists,
    every_system_tool_is_where_it_is_expected,
    every_named_resource_is_shipped,
    embedded_scripts_close_what_they_open,
    stores_delete_only_what_they_own,
    tap_owners_follow_the_session,
    pointer_taps_run_off_the_main_thread,
    inverter_does_not_yield_to_the_switcher,
    cleaning_mode_never_synthesizes_mouse_events,
    brightness_work_queue_never_touches_nsscreen,
    click_debounce_schedules_nothing,
    smooth_scroll_disabled_tap_rearms_only_when_wanted,
    menu_panel_switches_have_names,
    path_identity_rule_is_spelled_once,
    build_sweeps_its_temp_dirs,
    build_signs_with_a_stable_identity,
    test_types_do_not_shadow_real_ones,
    unit_tests_read_no_source_text,
    preferences_are_reached_through_their_type,
]


def problems(repo):
    """Every rule's problems, in rule order."""
    found = []
    for rule in RULES:
        found.extend(f"{rule.__name__}: {problem}" for problem in rule(repo))
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--app-dir", type=Path, help="app root (defaults to the workspace copy)"
    )
    args = parser.parse_args()
    app_dir = args.app_dir
    if app_dir is None:
        workspace = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
        app_dir = (
            Path(workspace, "apps/desktop/vitruvian")
            if workspace
            else Path(__file__).resolve().parents[1]
        )
    repo = Repository(app_dir.absolute())
    found = problems(repo)
    for problem in found:
        print(problem, file=sys.stderr)
    if found:
        return 1
    print(f"{len(RULES)} source rules hold across {len(repo.swift_paths)} Swift files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
