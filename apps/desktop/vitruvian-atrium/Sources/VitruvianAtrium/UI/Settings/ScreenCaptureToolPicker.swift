// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// Chooses the tool whose options the page shows. Four tool names can need
/// more room than the narrowest window leaves the page, in English and more so
/// in longer languages, and a page wider than its column is centered and cut
/// on both sides, under the sidebar. The segments give way to a menu whenever
/// they don't fit.
package struct ScreenCaptureToolPicker: View {
    package let tools: [ScreenCaptureTool]
    package let strings: Strings
    package let language: AppLanguage
    @Binding package var selection: ScreenCaptureTool

    package var body: some View {
        ViewThatFits(in: .horizontal) {
            picker
                .pickerStyle(.segmented)
                .controlSize(.large)
            picker
                .pickerStyle(.menu)
        }
    }

    private var picker: some View {
        Picker(FeatureStrings.screenshot(language).screenCaptureTitle, selection: $selection) {
            ForEach(tools, id: \.self) { tool in
                Label(tool.settingsTitle(strings, language: language),
                      systemImage: tool.systemImageName)
                    .tag(tool)
            }
        }
        .labelsHidden()
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(tools: [ScreenCaptureTool], strings: Strings, language: AppLanguage, selection: Binding<ScreenCaptureTool>) {
        self.tools = tools
        self.strings = strings
        self.language = language
        self._selection = selection
    }
}
