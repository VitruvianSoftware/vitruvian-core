// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// One rounded group of related controls on a redesigned Settings page, with
/// an optional heading. The same card the Dynamic Island page draws, so the
/// pages read as one design.
package struct SettingsCard<Content: View>: View {
    package let title: String?
    package let content: Content

    package init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Where a row's text column starts, so follow-up controls can line up with it.
package let settingsRowTextInset: CGFloat = 26 + 12

/// Icon, title, one line of explanation and the control on the right. A nil
/// symbol shows the app's own menu bar glyph, for rows about that icon.
package struct SettingsRow<Accessory: View>: View {
    package let symbol: String?
    package let title: String
    package let badge: String?
    package let caption: String?
    package let accessory: Accessory

    package init(symbol: String?, title: String, badge: String? = nil, caption: String? = nil,
         @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.badge = badge
        self.caption = caption
        self.accessory = accessory()
    }

    package var body: some View {
        HStack(spacing: 12) {
            iconTile
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                            .accessibilityHidden(true)
                    }
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
    }

    @ViewBuilder
    private var iconTile: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            // The menu bar draws the glyph white on a dark bar; the badge keeps
            // that pairing so it reads as the same icon in both appearances.
            MenuBarGlyph()
                .frame(width: 17, height: 13)
                .frame(width: 26, height: 26)
                .background(Color.black.opacity(0.82),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

/// A row that picks one of a few options: segments beside the title while the
/// row fits on one line, under the title otherwise, and a menu there when the
/// segments don't fit either. A row wider than its column would center the page
/// and cut it on both sides.
package struct SettingsChoiceRow<Value: Hashable, Options: View>: View {
    package let symbol: String?
    package let title: String
    @Binding package var selection: Value
    package let options: Options

    package init(symbol: String?, title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.symbol = symbol
        self.title = title
        _selection = selection
        self.options = options()
    }

    package var body: some View {
        ViewThatFits(in: .horizontal) {
            SettingsRow(symbol: symbol, title: title) {
                picker.pickerStyle(.segmented).fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(symbol: symbol, title: title) { EmptyView() }
                ViewThatFits(in: .horizontal) {
                    picker.pickerStyle(.segmented).fixedSize()
                    picker.pickerStyle(.menu).fixedSize()
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) { options }.labelsHidden()
    }
}

/// A row whose choice is a menu: beside the title while the row fits on one
/// line, under the title otherwise, lined up with its text, or with its icon
/// when the menu is wider than the text leaves room for. A menu kept beside a
/// title that has to wrap squeezes the title letter by letter, and a row
/// wider than its column would center the page and cut it on both sides.
package struct SettingsMenuRow<Value: Hashable, Options: View>: View {
    package let symbol: String?
    package let title: String
    @Binding package var selection: Value
    package let options: Options

    package init(symbol: String?, title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.symbol = symbol
        self.title = title
        _selection = selection
        self.options = options()
    }

    package var body: some View {
        ViewThatFits(in: .horizontal) {
            SettingsRow(symbol: symbol, title: title) { menu }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(symbol: symbol, title: title) { EmptyView() }
                // Only the menu's width decides here: a title too long for one
                // line wraps above it either way.
                ViewThatFits(in: .horizontal) {
                    menu.padding(.leading, settingsRowTextInset)
                    menu
                }
            }
        }
    }

    private var menu: some View {
        Picker(title, selection: $selection) { options }.pickerStyle(.menu).labelsHidden().fixedSize()
    }
}

/// A form's switch over one stored preference, with its caption on the row
/// under it. For a setting that needs no live sync: what reads the
/// preference reads it again each time it acts. A page builds the row from
/// a function of its own, so the preference it writes and the words it shows
/// can be read back without drawing the page.
package struct PreferenceSwitchRow: View {
    package let preference: Preference<Bool>
    package let title: String
    package let caption: String
    @AppStorage private var isOn: Bool

    package init(_ preference: Preference<Bool>, title: String, caption: String) {
        self.preference = preference
        self.title = title
        self.caption = caption
        _isOn = AppStorage(preference)
    }

    package var body: some View {
        Toggle(title, isOn: $isOn)
        Text(caption)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// A switch pushed to the trailing edge with its label at the leading one,
/// so a shared control that carries its own label lines up with the rows
/// around it on a redesigned page.
package struct TrailingSwitchToggleStyle: ToggleStyle {
    package func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
