// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The app's words for the menu bar panel's Extensions tab. An extension's
/// own name and page are its own words, never translated here.
package struct MenuPanelExtensionsStrings {
    /// The tab's name, in the panel and in Settings › Menu bar.
    package let title: String
    /// What the tab shows, under its name in Settings › Menu bar.
    package let sectionDescription: String
    /// The tab, when no extension has a panel for it.
    package let emptyNone: String
    /// Opens the Settings page where extensions are added and managed.
    package let manage: String
    /// The tab, when every extension that has a panel is switched off for it.
    package let emptyAllOff: String
    /// Opens Settings › Menu bar, where those switches are.
    package let choose: String
    /// The heading of the switches in Settings › Menu bar.
    package let settingsTitle: String
    /// The line under that heading.
    package let settingsCaption: String

    package init(title: String, sectionDescription: String, emptyNone: String, manage: String,
                 emptyAllOff: String, choose: String, settingsTitle: String, settingsCaption: String) {
        self.title = title
        self.sectionDescription = sectionDescription
        self.emptyNone = emptyNone
        self.manage = manage
        self.emptyAllOff = emptyAllOff
        self.choose = choose
        self.settingsTitle = settingsTitle
        self.settingsCaption = settingsCaption
    }
}

extension FeatureStrings {
    package static func menuPanelExtensions(_ language: AppLanguage) -> MenuPanelExtensionsStrings {
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
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension MenuPanelExtensionsStrings {
    package static let enUS = MenuPanelExtensionsStrings(
        title: "Extensions",
        sectionDescription: "The panels your extensions add, one under another.",
        emptyNone: "None of your extensions adds a panel here yet.",
        manage: "Manage Extensions…",
        emptyAllOff: "Every extension is switched off for this tab.",
        choose: "Choose Extensions…",
        settingsTitle: "Extensions tab",
        settingsCaption: "Choose which extensions show their panel in the Extensions tab."
    )

    package static let ptBR = MenuPanelExtensionsStrings(
        title: "Extensões",
        sectionDescription: "Os painéis que suas extensões adicionam, um abaixo do outro.",
        emptyNone: "Nenhuma das suas extensões adiciona um painel aqui ainda.",
        manage: "Gerenciar extensões…",
        emptyAllOff: "Todas as extensões estão desativadas nesta aba.",
        choose: "Escolher extensões…",
        settingsTitle: "Aba Extensões",
        settingsCaption: "Escolha quais extensões mostram o painel na aba Extensões."
    )

    package static let tr = MenuPanelExtensionsStrings(
        title: "Uzantılar",
        sectionDescription: "Uzantılarınızın eklediği paneller, alt alta.",
        emptyNone: "Uzantılarınızın hiçbiri henüz buraya panel eklemiyor.",
        manage: "Uzantıları Yönet…",
        emptyAllOff: "Bu sekme için tüm uzantılar kapalı.",
        choose: "Uzantıları Seç…",
        settingsTitle: "Uzantılar sekmesi",
        settingsCaption: "Uzantılar sekmesinde hangi uzantıların panelini göstereceğini seçin."
    )

    package static let ru = MenuPanelExtensionsStrings(
        title: "Расширения",
        sectionDescription: "Панели ваших расширений, одна под другой.",
        emptyNone: "Ни одно из ваших расширений пока не добавляет сюда панель.",
        manage: "Управлять расширениями…",
        emptyAllOff: "Все расширения выключены для этой вкладки.",
        choose: "Выбрать расширения…",
        settingsTitle: "Вкладка «Расширения»",
        settingsCaption: "Выберите, какие расширения показывают свою панель на вкладке «Расширения»."
    )

    package static let es = MenuPanelExtensionsStrings(
        title: "Extensiones",
        sectionDescription: "Los paneles que añaden tus extensiones, uno debajo de otro.",
        emptyNone: "Ninguna de tus extensiones añade todavía un panel aquí.",
        manage: "Gestionar extensiones…",
        emptyAllOff: "Todas las extensiones están desactivadas en esta pestaña.",
        choose: "Elegir extensiones…",
        settingsTitle: "Pestaña Extensiones",
        settingsCaption: "Elige qué extensiones muestran su panel en la pestaña Extensiones."
    )

    package static let sk = MenuPanelExtensionsStrings(
        title: "Rozšírenia",
        sectionDescription: "Panely, ktoré pridávajú vaše rozšírenia, jeden pod druhým.",
        emptyNone: "Žiadne z vašich rozšírení sem zatiaľ nepridáva panel.",
        manage: "Spravovať rozšírenia…",
        emptyAllOff: "Všetky rozšírenia sú pre túto kartu vypnuté.",
        choose: "Vybrať rozšírenia…",
        settingsTitle: "Karta Rozšírenia",
        settingsCaption: "Vyberte, ktoré rozšírenia zobrazia svoj panel na karte Rozšírenia."
    )

    package static let de = MenuPanelExtensionsStrings(
        title: "Erweiterungen",
        sectionDescription: "Die Bereiche, die deine Erweiterungen hinzufügen, untereinander.",
        emptyNone: "Noch keine deiner Erweiterungen fügt hier einen Bereich hinzu.",
        manage: "Erweiterungen verwalten…",
        emptyAllOff: "Alle Erweiterungen sind für diesen Tab ausgeschaltet.",
        choose: "Erweiterungen auswählen…",
        settingsTitle: "Tab „Erweiterungen“",
        settingsCaption: "Wähle, welche Erweiterungen ihren Bereich im Tab „Erweiterungen“ zeigen."
    )

    package static let fr = MenuPanelExtensionsStrings(
        title: "Extensions",
        sectionDescription: "Les panneaux ajoutés par vos extensions, l’un sous l’autre.",
        emptyNone: "Aucune de vos extensions n’ajoute encore de panneau ici.",
        manage: "Gérer les extensions…",
        emptyAllOff: "Toutes les extensions sont désactivées pour cet onglet.",
        choose: "Choisir les extensions…",
        settingsTitle: "Onglet Extensions",
        settingsCaption: "Choisissez les extensions qui affichent leur panneau dans l’onglet Extensions."
    )

    package static let it = MenuPanelExtensionsStrings(
        title: "Estensioni",
        sectionDescription: "I pannelli aggiunti dalle tue estensioni, uno sotto l’altro.",
        emptyNone: "Nessuna delle tue estensioni aggiunge ancora un pannello qui.",
        manage: "Gestisci estensioni…",
        emptyAllOff: "Tutte le estensioni sono disattivate per questa scheda.",
        choose: "Scegli estensioni…",
        settingsTitle: "Scheda Estensioni",
        settingsCaption: "Scegli quali estensioni mostrano il loro pannello nella scheda Estensioni."
    )

    package static let ja = MenuPanelExtensionsStrings(
        title: "拡張機能",
        sectionDescription: "拡張機能が追加するパネルを縦に並べて表示します。",
        emptyNone: "ここにパネルを追加する拡張機能はまだありません。",
        manage: "拡張機能を管理…",
        emptyAllOff: "このタブではすべての拡張機能がオフになっています。",
        choose: "拡張機能を選択…",
        settingsTitle: "「拡張機能」タブ",
        settingsCaption: "「拡張機能」タブにパネルを表示する拡張機能を選びます。"
    )

    package static let ko = MenuPanelExtensionsStrings(
        title: "확장 프로그램",
        sectionDescription: "확장 프로그램이 추가하는 패널을 위아래로 보여 줍니다.",
        emptyNone: "아직 여기에 패널을 추가하는 확장 프로그램이 없습니다.",
        manage: "확장 프로그램 관리…",
        emptyAllOff: "이 탭에서 모든 확장 프로그램이 꺼져 있습니다.",
        choose: "확장 프로그램 선택…",
        settingsTitle: "확장 프로그램 탭",
        settingsCaption: "확장 프로그램 탭에 패널을 표시할 확장 프로그램을 선택하세요."
    )

    package static let uk = MenuPanelExtensionsStrings(
        title: "Розширення",
        sectionDescription: "Панелі ваших розширень, одна під одною.",
        emptyNone: "Жодне з ваших розширень поки не додає сюди панель.",
        manage: "Керувати розширеннями…",
        emptyAllOff: "Усі розширення вимкнено для цієї вкладки.",
        choose: "Вибрати розширення…",
        settingsTitle: "Вкладка «Розширення»",
        settingsCaption: "Виберіть, які розширення показують свою панель на вкладці «Розширення»."
    )

    package static let zhHans = MenuPanelExtensionsStrings(
        title: "扩展",
        sectionDescription: "你的扩展所添加的面板，依次排列。",
        emptyNone: "你的扩展还没有在这里添加面板。",
        manage: "管理扩展…",
        emptyAllOff: "所有扩展都已在此标签页中关闭。",
        choose: "选择扩展…",
        settingsTitle: "“扩展”标签页",
        settingsCaption: "选择哪些扩展在“扩展”标签页中显示面板。"
    )

    package static let zhTW = MenuPanelExtensionsStrings(
        title: "擴充功能",
        sectionDescription: "你的擴充功能所加入的面板，依序排列。",
        emptyNone: "你的擴充功能還沒有在這裡加入面板。",
        manage: "管理擴充功能…",
        emptyAllOff: "所有擴充功能都已在此標籤頁中關閉。",
        choose: "選擇擴充功能…",
        settingsTitle: "「擴充功能」標籤頁",
        settingsCaption: "選擇哪些擴充功能在「擴充功能」標籤頁中顯示面板。"
    )

    package static let zhHK = MenuPanelExtensionsStrings(
        title: "擴充功能",
        sectionDescription: "你的擴充功能所加入的面板，依次排列。",
        emptyNone: "你的擴充功能尚未在這裡加入面板。",
        manage: "管理擴充功能…",
        emptyAllOff: "所有擴充功能都已在此分頁中關閉。",
        choose: "選擇擴充功能…",
        settingsTitle: "「擴充功能」分頁",
        settingsCaption: "選擇哪些擴充功能在「擴充功能」分頁中顯示面板。"
    )
}
