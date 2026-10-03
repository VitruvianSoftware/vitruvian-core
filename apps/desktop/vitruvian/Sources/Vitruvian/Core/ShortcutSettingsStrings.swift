// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

package struct ShortcutSettingsStrings {
    package let active: String
    package let inactive: String
    package let superKeyAlternativeFormat: String
}

extension FeatureStrings {
    package static func shortcuts(_ language: AppLanguage) -> ShortcutSettingsStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension ShortcutSettingsStrings {
    package static let enUS = ShortcutSettingsStrings(
        active: "Active",
        inactive: "Inactive",
        superKeyAlternativeFormat: "or %@"
    )

    package static let ptBR = ShortcutSettingsStrings(
        active: "Ativo",
        inactive: "Inativo",
        superKeyAlternativeFormat: "ou %@"
    )

    package static let tr = ShortcutSettingsStrings(
        active: "Etkin",
        inactive: "Etkin değil",
        superKeyAlternativeFormat: "veya %@"
    )

    package static let ru = ShortcutSettingsStrings(
        active: "Активно",
        inactive: "Неактивно",
        superKeyAlternativeFormat: "или %@"
    )

    package static let es = ShortcutSettingsStrings(
        active: "Activo",
        inactive: "Inactivo",
        superKeyAlternativeFormat: "o %@"
    )

    package static let sk = ShortcutSettingsStrings(
        active: "Aktívna",
        inactive: "Neaktívna",
        superKeyAlternativeFormat: "alebo %@"
    )

    package static let de = ShortcutSettingsStrings(
        active: "Aktiv",
        inactive: "Inaktiv",
        superKeyAlternativeFormat: "oder %@"
    )

    package static let fr = ShortcutSettingsStrings(
        active: "Actif",
        inactive: "Inactif",
        superKeyAlternativeFormat: "ou %@"
    )

    package static let it = ShortcutSettingsStrings(
        active: "Attiva",
        inactive: "Inattiva",
        superKeyAlternativeFormat: "oppure %@"
    )

    package static let ja = ShortcutSettingsStrings(
        active: "有効",
        inactive: "無効",
        superKeyAlternativeFormat: "または %@"
    )

    package static let ko = ShortcutSettingsStrings(
        active: "활성",
        inactive: "비활성",
        superKeyAlternativeFormat: "또는 %@"
    )

    package static let zhHans = ShortcutSettingsStrings(
        active: "已启用",
        inactive: "未启用",
        superKeyAlternativeFormat: "或 %@"
    )

    package static let zhTW = ShortcutSettingsStrings(
        active: "已啟用",
        inactive: "未啟用",
        superKeyAlternativeFormat: "或 %@"
    )

    package static let zhHK = ShortcutSettingsStrings(
        active: "已啟用",
        inactive: "未啟用",
        superKeyAlternativeFormat: "或 %@"
    )
    package static let uk = ShortcutSettingsStrings(
        active: "Активно",
        inactive: "Неактивно",
        superKeyAlternativeFormat: "або %@"
    )
}
