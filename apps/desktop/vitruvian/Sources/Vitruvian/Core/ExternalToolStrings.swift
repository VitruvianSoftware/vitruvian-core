// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianToolProtocol

/// The app's own words about tools that run as their own programs: their
/// page in Settings, Extensions, and its line on the Features page, the sheet
/// that asks before one is added, and the message when one stops working. A tool's name, publisher, description
/// and command titles are never here: they are shown as the tool wrote them.
///
/// Same contract as the other feature string sets: one static per language,
/// all in this file, and `FeatureStrings.externalTools` switches over every
/// language, so a missing one does not compile.
package struct ExternalToolStrings {
    /// What the Features page called its card for these, "Extensions &
    /// Tools", before they had a page of their own. The Settings search
    /// still finds the page by it.
    package let sectionTitle: String
    /// The Installed list's one line when nothing is added.
    package let sectionEmpty: String
    /// The button on the Extensions page that adds one from a folder.
    package let addButton: String
    package let statusRunning: String
    package let statusStopped: String
    package let startAgain: String
    /// A tool whose files are not what the person agreed to. It is not started.
    package let statusChanged: String
    package let commandsTitle: String
    /// Heads the list of app services the tool's manifest names in `uses`.
    package let usesTitle: String
    package let usesNote: String
    package let useNotify: String
    package let useOpen: String
    package let useClipboardRead: String
    package let useClipboardWrite: String
    package let useKeystrokes: String
    package let useProcesses: String
    package let useStorage: String
    package let updateButton: String
    package let refusalTitle: String
    package let refusalNoManifest: String
    /// `%@` is which rule of the manifest was broken, in the runtime's own English.
    package let refusalMistakeFormat: String
    /// `%@` is the name the manifest uses that this app does not have.
    package let refusalNeedsNewerFormat: String
    /// `%@` is the program's path inside the folder, as the manifest gives it.
    package let refusalProgramFormat: String
    /// Shown above the command that clears the quarantine, which is not translated.
    package let refusalQuarantined: String
    /// `%1$@` is the most a tool's folder may weigh, such as "256 MB"; `%2$@` is the most things it may hold.
    package let refusalTooBigFormat: String
    package let refusalNotAdded: String
    /// `%@` is the tool's name, as the tool wrote it.
    package let agreeTitleFormat: String
    /// `%@` is the folder the person picked, with a tilde for their home folder.
    package let agreeFromFormat: String
    package let agreeOwnWords: String
    /// The one sentence the sheet exists to say.
    package let agreeHeadline: String
    package let agreeDetail: String
    package let agreeAdd: String
    /// `%@` is the tool's name, as the tool wrote it.
    package let updateTitleFormat: String
    /// `%1$@` is the version the person agreed to; `%2$@` is the one in the folder.
    package let updateVersionsFormat: String
    /// Shown when the manifest's bytes differ from the ones the person agreed to.
    package let updateChanged: String
    package let updateKeepsData: String
    package let updateConfirm: String
    /// `%@` is the tool's name, as the tool wrote it.
    package let removeTitleFormat: String
    package let removeMessage: String
    package let removeKeepData: String
    package let removeDeleteData: String
    /// The title of the alert after a tool is removed and what it saved could not be
    /// deleted. `%@` is the tool's name, as the tool wrote it.
    package let removeKeptTitleFormat: String
    /// Shown above the folder that holds what the tool saved.
    package let removeKeptMessage: String
    /// The title of the alert after a tool is removed and one of its folders could
    /// not be deleted, with its program gone. `%@` is the tool's name, as the tool wrote it.
    package let removeUndeletedTitleFormat: String
    /// Shown above the folder, or the two folders, that could not be deleted.
    package let removeUndeletedMessage: String
    /// The app's short on-screen message. `%@` is the tool's name, as the tool wrote it.
    package let stoppedFormat: String
    /// Where a tool's panel would be: its web page did not load or left the tool's
    /// folder, or the tool did not answer.
    package let panelNotShown: String
    /// The switch in a tool's detail that lists its page among the island's sections.
    package let showInIsland: String
    /// The heading of the catalog on the Extensions page.
    package let catalogTitle: String
    /// The catalog's one line when it lists no tool this app can install.
    package let catalogEmpty: String
    package let installButton: String
    /// In place of the install button, for a tool that is added already.
    package let installedLabel: String
    /// Beside a tool from the catalog, in its row and its detail, when the catalog has a newer version.
    package let updateAvailable: String
    /// The button that fetches the newer version from the catalog.
    package let updateNow: String
    /// The one line the agreement sheet adds for a tool from the catalog.
    package let agreeCatalog: String
    /// The list, or a tool's download, could not be fetched.
    package let catalogUnreachable: String
    /// The list's signature is not one the app's own key made.
    package let catalogNotOurs: String
    /// The download's size or SHA-256 is not the one the catalog pins.
    package let downloadMismatch: String
    /// The download is no tool, holds a path that leaves its folder or a link, or names another tool or version.
    package let downloadNotTheTool: String
    /// The title of the alert after an install from the catalog was refused. `%@` is the tool's name, as the catalog gives it.
    package let installRefusedFormat: String
    /// The switch in a tool's detail that draws its status on the closed island.
    package let showStatusInIsland: String
    /// The one line the agreement sheet adds for a tool whose manifest declares a status.
    package let agreeShowsStatus: String
    /// The same line, for a tool whose status may also carry a few words (`"activity": true`).
    package let agreeShowsStatusAndWords: String
    /// What VoiceOver says for a tool's status mark when the tool gave no words: all is well.
    package let markOK: String
    /// The same, for something under way.
    package let markBusy: String
    /// The same, for something that waits for the person.
    package let markAttention: String
    /// The same, for something that failed.
    package let markFailure: String
    /// The pill beside an added package that contributes panels.
    package let kindExtension: String
    /// The pill beside an added package that contributes only commands.
    package let kindTool: String
    /// The Settings page's name, in the sidebar and as its title.
    package let pageTitle: String
    /// The heading of what the person added, on the Extensions page.
    package let installedTitle: String
    /// In place of the catalog's rows when each tool it lists is added already.
    package let catalogAllInstalled: String
    /// The Features page's line when nothing is added.
    package let summaryNone: String
    /// The Features page's line when one is added.
    package let summaryOne: String
    /// The same line for more than one. `%d` is how many.
    package let summaryCountFormat: String
    /// After the line, the link to the Extensions page when something is added.
    package let summaryManage: String
    /// The same link when nothing is added.
    package let summaryBrowse: String
    /// The button on the row of an extension added from a folder when the catalog lists a newer
    /// version of it: it fetches that version, and the extension is from the catalog from then on.
    package let updateFromCatalog: String
    /// The agreement sheet's line for that update: the source moves from a folder to the catalog.
    /// `%@` is the folder it was added from, with a tilde for the home folder.
    package let updateMovesToCatalogFormat: String
    /// The agreement sheet's versions for an update from the catalog. `%1$@` is the version the
    /// person agreed to; `%2$@` is the one the catalog lists.
    package let updateVersionsCatalogFormat: String
    /// The quiet line at the foot of the catalog's card, in every state of
    /// the list: where to start building one's own. It holds
    /// `CatalogueSheetContent.SDKLine.name` once, untranslated, and those
    /// words are the link to the SDK.
    package let sdkLine: String
    /// The heading of Vitruvian's own rows on an extension's settings
    /// sheet (the island switches and the settings its manifest declares),
    /// and their link in the sheet's row of sections. The app's name, in
    /// every language.
    package let vitruvianSection: String
    /// The field that searches an extension's settings sheet, as it says
    /// before anything is typed and to VoiceOver.
    package let searchSettings: String
    /// What the sheet says when a search keeps nothing. `%@` is what was
    /// typed.
    package let noSettingsMatchFormat: String
    /// What a search says of an extension's settings page that is a web
    /// page, which the app cannot look inside.
    package let pageNotSearchable: String
    /// Where a panel would be, when the first page its extension sent was
    /// refused: too large, or a field missing or of the wrong kind. `%1$@`
    /// is the extension's name, as it wrote it; `%2$@` is why, one of the
    /// two below.
    package let panelRefusedFormat: String
    /// Why, for a page over the most a page may weigh. `%@` is the most,
    /// "256 KB". The page's own size is left to the log: rounded, a page
    /// just over the limit would read as the limit.
    package let panelTooLargeFormat: String
    /// Why, for a page with a field missing or of the wrong kind. `%@` is
    /// where, in the protocol's own words, such as `blocks[76].id`.
    package let panelNotWellFormedFormat: String
    /// The button beside a text setting whose author asked for a folder: it
    /// opens a panel to pick one, and the folder's path is saved.
    package let chooseFolder: String

    /// What a panel says in its place when the first page its extension
    /// sent was refused, and why. `tool` is the extension's name.
    package func panelRefused(_ tool: String, _ problem: ToolPanelProblem) -> String {
        let why: String
        switch problem {
        case .tooLarge:
            let most = ByteCountFormatter.string(fromByteCount: Int64(UILimits.maxTreeBytes), countStyle: .memory)
            why = String(format: panelTooLargeFormat, locale: Locale.current, most)
        case .notWellFormed(let place):
            why = String(format: panelNotWellFormedFormat, locale: Locale.current, place)
        }
        return String(format: panelRefusedFormat, locale: Locale.current, tool, why)
    }

    package func noSettingsMatch(_ query: String) -> String {
        String(format: noSettingsMatchFormat, locale: Locale.current, query)
    }

    package func agreeTitle(_ name: String) -> String {
        String(format: agreeTitleFormat, locale: Locale.current, name)
    }

    package func agreeFrom(_ folder: String) -> String {
        String(format: agreeFromFormat, locale: Locale.current, folder)
    }

    package func updateTitle(_ name: String) -> String {
        String(format: updateTitleFormat, locale: Locale.current, name)
    }

    package func updateVersions(agreed: String, offered: String) -> String {
        String(format: updateVersionsFormat, locale: Locale.current, agreed, offered)
    }

    package func updateVersionsFromCatalog(agreed: String, offered: String) -> String {
        String(format: updateVersionsCatalogFormat, locale: Locale.current, agreed, offered)
    }

    package func updateMovesToCatalog(_ folder: String) -> String {
        String(format: updateMovesToCatalogFormat, locale: Locale.current, folder)
    }

    package func removeTitle(_ name: String) -> String {
        String(format: removeTitleFormat, locale: Locale.current, name)
    }

    package func removeKeptTitle(_ name: String) -> String {
        String(format: removeKeptTitleFormat, locale: Locale.current, name)
    }

    package func removeUndeletedTitle(_ name: String) -> String {
        String(format: removeUndeletedTitleFormat, locale: Locale.current, name)
    }

    package func stopped(_ name: String) -> String {
        String(format: stoppedFormat, locale: Locale.current, name)
    }

    /// How many are added, for the Features page's line.
    package func summaryCount(_ count: Int) -> String {
        String(format: summaryCountFormat, locale: Locale.current, count)
    }

    package func installRefused(_ name: String) -> String {
        String(format: installRefusedFormat, locale: Locale.current, name)
    }

    package func refusalMistake(_ detail: String) -> String {
        String(format: refusalMistakeFormat, locale: Locale.current, detail)
    }

    package func refusalNeedsNewer(_ name: String) -> String {
        String(format: refusalNeedsNewerFormat, locale: Locale.current, name)
    }

    package func refusalProgram(_ path: String) -> String {
        String(format: refusalProgramFormat, locale: Locale.current, path)
    }

    package func refusalTooBig(size: String, items: String) -> String {
        String(format: refusalTooBigFormat, locale: Locale.current, size, items)
    }

    /// The app's own word for a state of a tool's status, for a tool that
    /// gave none of its own. Nil for `none`, which is no status.
    package func mark(_ state: StatusState) -> String? {
        switch state {
        case .ok: return markOK
        case .busy: return markBusy
        case .attention: return markAttention
        case .failure: return markFailure
        case .none: return nil
        }
    }

    /// One of the app's services, in plain words, as a tool's manifest
    /// lists it in `uses`. Nil for the two a tool from outside may not
    /// list.
    package func use(_ capability: Capability) -> String? {
        switch capability {
        case .notify: return useNotify
        case .open: return useOpen
        case .clipboardRead: return useClipboardRead
        case .clipboardWrite: return useClipboardWrite
        case .keystrokes: return useKeystrokes
        case .processes: return useProcesses
        case .storage: return useStorage
        case .clipboardRewrite, .hotkey: return nil
        }
    }

    /// Every text, by its field's name, for a check that reads them all.
    package var all: [(key: String, text: String)] {
        [
            ("sectionTitle", sectionTitle),
            ("sectionEmpty", sectionEmpty),
            ("addButton", addButton),
            ("statusRunning", statusRunning),
            ("statusStopped", statusStopped),
            ("startAgain", startAgain),
            ("statusChanged", statusChanged),
            ("commandsTitle", commandsTitle),
            ("usesTitle", usesTitle),
            ("usesNote", usesNote),
            ("useNotify", useNotify),
            ("useOpen", useOpen),
            ("useClipboardRead", useClipboardRead),
            ("useClipboardWrite", useClipboardWrite),
            ("useKeystrokes", useKeystrokes),
            ("useProcesses", useProcesses),
            ("useStorage", useStorage),
            ("updateButton", updateButton),
            ("refusalTitle", refusalTitle),
            ("refusalNoManifest", refusalNoManifest),
            ("refusalMistakeFormat", refusalMistakeFormat),
            ("refusalNeedsNewerFormat", refusalNeedsNewerFormat),
            ("refusalProgramFormat", refusalProgramFormat),
            ("refusalQuarantined", refusalQuarantined),
            ("refusalTooBigFormat", refusalTooBigFormat),
            ("refusalNotAdded", refusalNotAdded),
            ("agreeTitleFormat", agreeTitleFormat),
            ("agreeFromFormat", agreeFromFormat),
            ("agreeOwnWords", agreeOwnWords),
            ("agreeHeadline", agreeHeadline),
            ("agreeDetail", agreeDetail),
            ("agreeAdd", agreeAdd),
            ("updateTitleFormat", updateTitleFormat),
            ("updateVersionsFormat", updateVersionsFormat),
            ("updateChanged", updateChanged),
            ("updateKeepsData", updateKeepsData),
            ("updateConfirm", updateConfirm),
            ("removeTitleFormat", removeTitleFormat),
            ("removeMessage", removeMessage),
            ("removeKeepData", removeKeepData),
            ("removeDeleteData", removeDeleteData),
            ("removeKeptTitleFormat", removeKeptTitleFormat),
            ("removeKeptMessage", removeKeptMessage),
            ("removeUndeletedTitleFormat", removeUndeletedTitleFormat),
            ("removeUndeletedMessage", removeUndeletedMessage),
            ("stoppedFormat", stoppedFormat),
            ("panelNotShown", panelNotShown),
            ("showInIsland", showInIsland),
            ("catalogTitle", catalogTitle),
            ("catalogEmpty", catalogEmpty),
            ("installButton", installButton),
            ("installedLabel", installedLabel),
            ("updateAvailable", updateAvailable),
            ("updateNow", updateNow),
            ("agreeCatalog", agreeCatalog),
            ("catalogUnreachable", catalogUnreachable),
            ("catalogNotOurs", catalogNotOurs),
            ("downloadMismatch", downloadMismatch),
            ("downloadNotTheTool", downloadNotTheTool),
            ("installRefusedFormat", installRefusedFormat),
            ("showStatusInIsland", showStatusInIsland),
            ("agreeShowsStatus", agreeShowsStatus),
            ("agreeShowsStatusAndWords", agreeShowsStatusAndWords),
            ("markOK", markOK),
            ("markBusy", markBusy),
            ("markAttention", markAttention),
            ("markFailure", markFailure),
            ("kindExtension", kindExtension),
            ("kindTool", kindTool),
            ("pageTitle", pageTitle),
            ("installedTitle", installedTitle),
            ("catalogAllInstalled", catalogAllInstalled),
            ("summaryNone", summaryNone),
            ("summaryOne", summaryOne),
            ("summaryCountFormat", summaryCountFormat),
            ("summaryManage", summaryManage),
            ("summaryBrowse", summaryBrowse),
            ("updateFromCatalog", updateFromCatalog),
            ("updateMovesToCatalogFormat", updateMovesToCatalogFormat),
            ("updateVersionsCatalogFormat", updateVersionsCatalogFormat),
            ("sdkLine", sdkLine),
            ("vitruvianSection", vitruvianSection),
            ("searchSettings", searchSettings),
            ("noSettingsMatchFormat", noSettingsMatchFormat),
            ("pageNotSearchable", pageNotSearchable),
            ("panelRefusedFormat", panelRefusedFormat),
            ("panelTooLargeFormat", panelTooLargeFormat),
            ("panelNotWellFormedFormat", panelNotWellFormedFormat),
            ("chooseFolder", chooseFolder),
        ]
    }
}

extension ExternalToolStrings {
    package static let enUS = ExternalToolStrings(
        sectionTitle: "Extensions & Tools",
        sectionEmpty: "No extensions or tools added. Each is a separate program. An extension adds pages of its own, in the Dynamic Island, in Settings or in a window. A tool adds commands to Vitruvian.",
        addButton: "Add from Folder…",
        statusRunning: "Running",
        statusStopped: "Stopped working",
        startAgain: "Start Again",
        statusChanged: "Changed since you added it. Update it to use it again.",
        commandsTitle: "Commands",
        usesTitle: "What it says it uses",
        usesNote: "This list comes from the tool. It is not a limit on what the tool can do.",
        useNotify: "Show messages and play the alert sound",
        useOpen: "Open links",
        useClipboardRead: "Read the clipboard",
        useClipboardWrite: "Write to the clipboard",
        useKeystrokes: "Paste and press menu commands in other apps",
        useProcesses: "End other programs",
        useStorage: "Save its own settings",
        updateButton: "Update from Folder…",
        refusalTitle: "This folder can’t be added",
        refusalNoManifest: "It has no vitruvian-tool.json file, so it is not a tool.",
        refusalMistakeFormat: "Its vitruvian-tool.json file has a mistake. Tell whoever made the tool: %@",
        refusalNeedsNewerFormat: "It needs something this version of Vitruvian does not have: %@",
        refusalProgramFormat: "Its program, %@, is missing or macOS will not run it.",
        refusalQuarantined: "macOS has quarantined this folder because it was downloaded. Vitruvian will not clear that for you. If you trust it, run this in Terminal, then add it again:",
        refusalTooBigFormat: "The folder is too large. A tool can hold up to %1$@ and %2$@ files.",
        refusalNotAdded: "Vitruvian could not copy the folder, or it changed while you were reading. Nothing was added.",
        agreeTitleFormat: "Add “%@” to Vitruvian?",
        agreeFromFormat: "From %@",
        agreeOwnWords: "The name, publisher and description are the tool’s own words. Vitruvian has not checked them.",
        agreeHeadline: "This tool can do anything Vitruvian can on this Mac.",
        agreeDetail: "It is a separate program. It can read the screen, control other apps, read your files and use the network. Vitruvian does not limit or check what it does. Add it only if you trust who made it.",
        agreeAdd: "Add Tool",
        updateTitleFormat: "Update “%@”?",
        updateVersionsFormat: "You have version %1$@. This folder has version %2$@.",
        updateChanged: "What the tool says about itself has changed since you agreed. Read it again.",
        updateKeepsData: "What the tool saved is kept.",
        updateConfirm: "Update Tool",
        removeTitleFormat: "Remove “%@”?",
        removeMessage: "Vitruvian deletes its copy of the tool. The folder you added it from is not touched.",
        removeKeepData: "Remove, Keep What It Saved",
        removeDeleteData: "Remove and Delete What It Saved",
        removeKeptTitleFormat: "What “%@” saved was kept",
        removeKeptMessage: "Its program would not stop, so Vitruvian did not delete what the tool saved. It is in this folder:",
        removeUndeletedTitleFormat: "Some files of “%@” could not be deleted",
        removeUndeletedMessage: "The tool is removed, but Vitruvian could not delete all of its files. What is left is here:",
        stoppedFormat: "“%@” stopped working",
        panelNotShown: "This page could not be shown. The tool’s log, in Settings, says why.",
        showInIsland: "Show in the Dynamic Island",
        catalogTitle: "The Vitruvian catalog",
        catalogEmpty: "There are no extensions or tools in the catalog yet.",
        installButton: "Install",
        installedLabel: "Installed",
        updateAvailable: "Update available",
        updateNow: "Update",
        agreeCatalog: "From the Vitruvian catalog: VitruvianSoftware listed this tool, and the download is exactly the one it listed.",
        catalogUnreachable: "Vitruvian could not reach the catalog. Check your connection and try again.",
        catalogNotOurs: "This list of tools is not signed by VitruvianSoftware, so Vitruvian will not use it.",
        downloadMismatch: "The download is not the one the catalog lists, so nothing was installed.",
        downloadNotTheTool: "The download is not the tool the catalog says it is, so nothing was installed.",
        installRefusedFormat: "“%@” was not installed",
        showStatusInIsland: "Show its status on the closed Dynamic Island",
        agreeShowsStatus: "It shows a small status mark on the closed Dynamic Island.",
        agreeShowsStatusAndWords: "It shows a small status mark and a few words on the closed Dynamic Island.",
        markOK: "OK",
        markBusy: "Working",
        markAttention: "Needs attention",
        markFailure: "Failed",
        kindExtension: "Extension",
        kindTool: "Tool",
        pageTitle: "Extensions",
        installedTitle: "Installed",
        catalogAllInstalled: "Everything in the catalog is installed.",
        summaryNone: "No extensions yet",
        summaryOne: "1 extension installed",
        summaryCountFormat: "%d extensions installed",
        summaryManage: "Manage",
        summaryBrowse: "Browse",
        updateFromCatalog: "Update from the catalog",
        updateMovesToCatalogFormat: "You added it from the folder %@; from now on it comes from the Vitruvian catalog.",
        updateVersionsCatalogFormat: "You have version %1$@. The catalog has version %2$@.",
        sdkLine: "Build your own extension with the Vitruvian SDK.",
        vitruvianSection: "Vitruvian",
        searchSettings: "Search settings",
        noSettingsMatchFormat: "No settings match “%@”",
        pageNotSearchable: "This page can’t be searched.",
        panelRefusedFormat: "%1$@ sent a page Vitruvian can’t show (%2$@). Updating the extension may fix it.",
        panelTooLargeFormat: "over the %@ size limit",
        panelNotWellFormedFormat: "%@ is not well formed",
        chooseFolder: "Choose…")

    package static let ptBR = ExternalToolStrings(
        sectionTitle: "Extensões e ferramentas",
        sectionEmpty: "Nenhuma extensão ou ferramenta adicionada. Cada uma é um programa separado. Uma extensão adiciona páginas próprias, no Dynamic Island, em Ajustes ou em uma janela. Uma ferramenta adiciona comandos ao Vitruvian.",
        addButton: "Adicionar a partir de uma pasta…",
        statusRunning: "Em execução",
        statusStopped: "Parou de funcionar",
        startAgain: "Iniciar novamente",
        statusChanged: "Mudou desde que você a adicionou. Atualize-a para voltar a usá-la.",
        commandsTitle: "Comandos",
        usesTitle: "O que ela diz que usa",
        usesNote: "Esta lista vem da ferramenta. Ela não limita o que a ferramenta pode fazer.",
        useNotify: "Mostrar mensagens e tocar o som de alerta",
        useOpen: "Abrir links",
        useClipboardRead: "Ler a área de transferência",
        useClipboardWrite: "Escrever na área de transferência",
        useKeystrokes: "Colar e acionar comandos de menu em outros apps",
        useProcesses: "Encerrar outros programas",
        useStorage: "Salvar as próprias configurações",
        updateButton: "Atualizar a partir de uma pasta…",
        refusalTitle: "Esta pasta não pode ser adicionada",
        refusalNoManifest: "Ela não tem um arquivo vitruvian-tool.json, então não é uma ferramenta.",
        refusalMistakeFormat: "O arquivo vitruvian-tool.json tem um erro. Avise quem fez a ferramenta: %@",
        refusalNeedsNewerFormat: "Ela precisa de algo que esta versão do Vitruvian não tem: %@",
        refusalProgramFormat: "O programa dela, %@, está ausente ou o macOS não o executa.",
        refusalQuarantined: "O macOS colocou esta pasta em quarentena porque ela foi baixada. O Vitruvian não remove isso por você. Se você confia nela, execute isto no Terminal e adicione-a de novo:",
        refusalTooBigFormat: "A pasta é grande demais. Uma ferramenta pode ter até %1$@ e %2$@ arquivos.",
        refusalNotAdded: "O Vitruvian não conseguiu copiar a pasta, ou ela mudou enquanto você lia. Nada foi adicionado.",
        agreeTitleFormat: "Adicionar “%@” ao Vitruvian?",
        agreeFromFormat: "De %@",
        agreeOwnWords: "O nome, o autor e a descrição são palavras da própria ferramenta. O Vitruvian não os verificou.",
        agreeHeadline: "Esta ferramenta pode fazer tudo o que o Vitruvian pode neste Mac.",
        agreeDetail: "É um programa separado. Ela pode ler a tela, controlar outros apps, ler seus arquivos e usar a rede. O Vitruvian não limita nem verifica o que ela faz. Adicione-a somente se você confia em quem a fez.",
        agreeAdd: "Adicionar ferramenta",
        updateTitleFormat: "Atualizar “%@”?",
        updateVersionsFormat: "Você tem a versão %1$@. Esta pasta tem a versão %2$@.",
        updateChanged: "O que a ferramenta diz sobre si mesma mudou desde que você concordou. Leia de novo.",
        updateKeepsData: "O que a ferramenta salvou é mantido.",
        updateConfirm: "Atualizar ferramenta",
        removeTitleFormat: "Remover “%@”?",
        removeMessage: "O Vitruvian apaga a cópia que ele tem da ferramenta. A pasta de onde você a adicionou não é alterada.",
        removeKeepData: "Remover e manter o que ela salvou",
        removeDeleteData: "Remover e apagar o que ela salvou",
        removeKeptTitleFormat: "O que “%@” salvou foi mantido",
        removeKeptMessage: "O programa dela não parou, então o Vitruvian não apagou o que a ferramenta salvou. Está nesta pasta:",
        removeUndeletedTitleFormat: "Alguns arquivos de “%@” não puderam ser apagados",
        removeUndeletedMessage: "A ferramenta foi removida, mas o Vitruvian não conseguiu apagar todos os arquivos dela. O que restou está aqui:",
        stoppedFormat: "“%@” parou de funcionar",
        panelNotShown: "Não foi possível mostrar esta página. O registro da ferramenta, em Ajustes, diz por quê.",
        showInIsland: "Mostrar no Dynamic Island",
        catalogTitle: "O catálogo do Vitruvian",
        catalogEmpty: "Ainda não há extensões nem ferramentas no catálogo.",
        installButton: "Instalar",
        installedLabel: "Instalada",
        updateAvailable: "Atualização disponível",
        updateNow: "Atualizar",
        agreeCatalog: "Do catálogo do Vitruvian: a VitruvianSoftware listou esta ferramenta, e o download é exatamente o que ela listou.",
        catalogUnreachable: "O Vitruvian não conseguiu acessar o catálogo. Verifique sua conexão e tente novamente.",
        catalogNotOurs: "Esta lista de ferramentas não foi assinada pela VitruvianSoftware, então o Vitruvian não vai usá-la.",
        downloadMismatch: "O download não é o que o catálogo lista, então nada foi instalado.",
        downloadNotTheTool: "O download não é a ferramenta que o catálogo diz que é, então nada foi instalado.",
        installRefusedFormat: "A ferramenta “%@” não foi instalada",
        showStatusInIsland: "Mostrar o status dela no Dynamic Island fechado",
        agreeShowsStatus: "Ela mostra uma pequena marca de status no Dynamic Island fechado.",
        agreeShowsStatusAndWords: "Ela mostra uma pequena marca de status e algumas palavras no Dynamic Island fechado.",
        markOK: "Tudo certo",
        markBusy: "Trabalhando",
        markAttention: "Precisa de atenção",
        markFailure: "Falhou",
        kindExtension: "Extensão",
        kindTool: "Ferramenta",
        pageTitle: "Extensões",
        installedTitle: "Instalados",
        catalogAllInstalled: "Tudo o que está no catálogo já está instalado.",
        summaryNone: "Nenhuma extensão ainda",
        summaryOne: "1 extensão instalada",
        summaryCountFormat: "%d extensões instaladas",
        summaryManage: "Gerenciar",
        summaryBrowse: "Explorar",
        updateFromCatalog: "Atualizar pelo catálogo",
        updateMovesToCatalogFormat: "Você a adicionou a partir da pasta %@; de agora em diante, ela vem do catálogo do Vitruvian.",
        updateVersionsCatalogFormat: "Você tem a versão %1$@. O catálogo tem a versão %2$@.",
        sdkLine: "Crie sua própria extensão com o Vitruvian SDK.",
        vitruvianSection: "Vitruvian",
        searchSettings: "Buscar nos ajustes",
        noSettingsMatchFormat: "Nenhum ajuste corresponde a “%@”",
        pageNotSearchable: "Não é possível buscar nesta página.",
        panelRefusedFormat: "%1$@ enviou uma página que o Vitruvian não consegue mostrar (%2$@). Atualizar a extensão pode resolver.",
        panelTooLargeFormat: "acima do limite de tamanho de %@",
        panelNotWellFormedFormat: "%@ está malformado",
        chooseFolder: "Escolher…")

    package static let tr = ExternalToolStrings(
        sectionTitle: "Uzantılar ve araçlar",
        sectionEmpty: "Eklenmiş uzantı veya araç yok. Her biri ayrı bir programdır. Bir uzantı, Dynamic Island’da, Ayarlar’da ya da bir pencerede kendi sayfalarını ekler. Bir araç, Vitruvian’a komut ekler.",
        addButton: "Klasörden ekle…",
        statusRunning: "Çalışıyor",
        statusStopped: "Çalışmayı durdurdu",
        startAgain: "Yeniden başlat",
        statusChanged: "Eklediğinizden beri değişti. Yeniden kullanmak için güncelleyin.",
        commandsTitle: "Komutlar",
        usesTitle: "Kullandığını söyledikleri",
        usesNote: "Bu liste aracın kendisinden gelir. Aracın yapabileceklerini sınırlamaz.",
        useNotify: "İleti gösterme ve uyarı sesini çalma",
        useOpen: "Bağlantıları açma",
        useClipboardRead: "Panoyu okuma",
        useClipboardWrite: "Panoya yazma",
        useKeystrokes: "Diğer uygulamalarda yapıştırma ve menü komutlarına basma",
        useProcesses: "Diğer programları sonlandırma",
        useStorage: "Kendi ayarlarını kaydetme",
        updateButton: "Klasörden güncelle…",
        refusalTitle: "Bu klasör eklenemiyor",
        refusalNoManifest: "İçinde vitruvian-tool.json dosyası yok, bu yüzden bir araç değil.",
        refusalMistakeFormat: "vitruvian-tool.json dosyasında bir hata var. Aracı yapana bildirin: %@",
        refusalNeedsNewerFormat: "Vitruvian’ın bu sürümünde olmayan bir şeye ihtiyaç duyuyor: %@",
        refusalProgramFormat: "Programı (%@) eksik veya macOS onu çalıştırmıyor.",
        refusalQuarantined: "macOS bu klasörü indirildiği için karantinaya aldı. Vitruvian bunu sizin yerinize kaldırmaz. Güveniyorsanız Terminal’de şunu çalıştırın, sonra yeniden ekleyin:",
        refusalTooBigFormat: "Klasör çok büyük. Bir araç en fazla %1$@ ve %2$@ dosya içerebilir.",
        refusalNotAdded: "Vitruvian klasörü kopyalayamadı veya klasör siz okurken değişti. Hiçbir şey eklenmedi.",
        agreeTitleFormat: "“%@” Vitruvian’a eklensin mi?",
        agreeFromFormat: "Kaynak: %@",
        agreeOwnWords: "Ad, yayıncı ve açıklama aracın kendi sözleridir. Vitruvian bunları doğrulamadı.",
        agreeHeadline: "Bu araç, Vitruvian’ın bu Mac’te yapabildiği her şeyi yapabilir.",
        agreeDetail: "Ayrı bir programdır. Ekranı okuyabilir, diğer uygulamaları kontrol edebilir, dosyalarınızı okuyabilir ve ağı kullanabilir. Vitruvian onun yaptıklarını sınırlamaz ve denetlemez. Yalnızca yapana güveniyorsanız ekleyin.",
        agreeAdd: "Aracı ekle",
        updateTitleFormat: "“%@” güncellensin mi?",
        updateVersionsFormat: "Sizde %1$@ sürümü var. Bu klasörde %2$@ sürümü var.",
        updateChanged: "Aracın kendisi hakkında söyledikleri, onay verdiğinizden beri değişti. Yeniden okuyun.",
        updateKeepsData: "Aracın kaydettikleri korunur.",
        updateConfirm: "Aracı güncelle",
        removeTitleFormat: "“%@” kaldırılsın mı?",
        removeMessage: "Vitruvian, aracın kendisindeki kopyasını siler. Aracı eklediğiniz klasöre dokunulmaz.",
        removeKeepData: "Kaldır, kaydettiklerini koru",
        removeDeleteData: "Kaldır ve kaydettiklerini sil",
        removeKeptTitleFormat: "“%@” aracının kaydettikleri korundu",
        removeKeptMessage: "Programı durmadığı için Vitruvian aracın kaydettiklerini silmedi. Kaydettikleri şu klasörde:",
        removeUndeletedTitleFormat: "“%@” aracının bazı dosyaları silinemedi",
        removeUndeletedMessage: "Araç kaldırıldı, ancak Vitruvian aracın tüm dosyalarını silemedi. Kalanlar burada:",
        stoppedFormat: "“%@” çalışmayı durdurdu",
        panelNotShown: "Bu sayfa gösterilemedi. Nedeni, Ayarlar’daki aracın günlüğünde yazıyor.",
        showInIsland: "Dynamic Island’da göster",
        catalogTitle: "Vitruvian kataloğu",
        catalogEmpty: "Katalogda henüz uzantı veya araç yok.",
        installButton: "Yükle",
        installedLabel: "Yüklendi",
        updateAvailable: "Güncelleme var",
        updateNow: "Güncelle",
        agreeCatalog: "Vitruvian kataloğundan: Bu aracı VitruvianSoftware listeledi ve indirilen dosya tam olarak listelenen dosya.",
        catalogUnreachable: "Vitruvian kataloğa ulaşamadı. Bağlantınızı kontrol edip yeniden deneyin.",
        catalogNotOurs: "Bu araç listesi VitruvianSoftware tarafından imzalanmamış, bu yüzden Vitruvian onu kullanmayacak.",
        downloadMismatch: "İndirilen dosya katalogda listelenen dosya değil, bu yüzden hiçbir şey yüklenmedi.",
        downloadNotTheTool: "İndirilen dosya, kataloğun söylediği araç değil, bu yüzden hiçbir şey yüklenmedi.",
        installRefusedFormat: "“%@” yüklenmedi",
        showStatusInIsland: "Durumunu kapalı Dynamic Island’da göster",
        agreeShowsStatus: "Kapalı Dynamic Island’da küçük bir durum işareti gösterir.",
        agreeShowsStatusAndWords: "Kapalı Dynamic Island’da küçük bir durum işareti ve birkaç kelime gösterir.",
        markOK: "Sorun yok",
        markBusy: "İşlem sürüyor",
        markAttention: "Dikkat gerekiyor",
        markFailure: "Başarısız oldu",
        kindExtension: "Uzantı",
        kindTool: "Araç",
        pageTitle: "Uzantılar",
        installedTitle: "Yüklü",
        catalogAllInstalled: "Katalogdaki her şey yüklü.",
        summaryNone: "Henüz uzantı yok",
        summaryOne: "1 uzantı yüklü",
        summaryCountFormat: "%d uzantı yüklü",
        summaryManage: "Yönet",
        summaryBrowse: "Göz at",
        updateFromCatalog: "Katalogdan güncelle",
        updateMovesToCatalogFormat: "Bunu %@ klasöründen eklediniz; bundan sonra Vitruvian kataloğundan gelecek.",
        updateVersionsCatalogFormat: "Sizde %1$@ sürümü var. Katalogda %2$@ sürümü var.",
        sdkLine: "Vitruvian SDK ile kendi uzantınızı oluşturun.",
        vitruvianSection: "Vitruvian",
        searchSettings: "Ayarlarda ara",
        noSettingsMatchFormat: "“%@” ile eşleşen ayar yok",
        pageNotSearchable: "Bu sayfada arama yapılamaz.",
        panelRefusedFormat: "%1$@, Vitruvian’ın gösteremediği bir sayfa gönderdi (%2$@). Uzantıyı güncellemek sorunu çözebilir.",
        panelTooLargeFormat: "%@ boyut sınırının üzerinde",
        panelNotWellFormedFormat: "%@ hatalı biçimde",
        chooseFolder: "Seç…")

    package static let ru = ExternalToolStrings(
        sectionTitle: "Расширения и инструменты",
        sectionEmpty: "Расширения и инструменты не добавлены. Каждое из них является отдельной программой. Расширение добавляет собственные страницы в Dynamic Island, в Настройки или в отдельное окно. Инструмент добавляет команды в Vitruvian.",
        addButton: "Добавить из папки…",
        statusRunning: "Работает",
        statusStopped: "Перестал работать",
        startAgain: "Запустить снова",
        statusChanged: "Изменился с момента добавления. Обновите его, чтобы снова использовать.",
        commandsTitle: "Команды",
        usesTitle: "Что он, по его словам, использует",
        usesNote: "Этот список предоставлен самим инструментом. Он не ограничивает то, что инструмент может делать.",
        useNotify: "Показывать сообщения и воспроизводить звук предупреждения",
        useOpen: "Открывать ссылки",
        useClipboardRead: "Читать буфер обмена",
        useClipboardWrite: "Записывать в буфер обмена",
        useKeystrokes: "Вставлять текст и выбирать команды меню в других приложениях",
        useProcesses: "Завершать другие программы",
        useStorage: "Сохранять собственные настройки",
        updateButton: "Обновить из папки…",
        refusalTitle: "Эту папку нельзя добавить",
        refusalNoManifest: "В ней нет файла vitruvian-tool.json, поэтому это не инструмент.",
        refusalMistakeFormat: "В файле vitruvian-tool.json есть ошибка. Сообщите автору инструмента: %@",
        refusalNeedsNewerFormat: "Ему нужно то, чего нет в этой версии Vitruvian: %@",
        refusalProgramFormat: "Его программа %@ отсутствует, или macOS не может её запустить.",
        refusalQuarantined: "macOS поместила эту папку в карантин, потому что она была загружена. Vitruvian не снимет его за вас. Если вы ей доверяете, выполните это в Терминале и добавьте её снова:",
        refusalTooBigFormat: "Папка слишком велика. Инструмент может содержать не более %1$@ и %2$@ файлов.",
        refusalNotAdded: "Vitruvian не смог скопировать папку, или она изменилась, пока вы читали. Ничего не добавлено.",
        agreeTitleFormat: "Добавить «%@» в Vitruvian?",
        agreeFromFormat: "Из папки %@",
        agreeOwnWords: "Название, издатель и описание указаны самим инструментом. Vitruvian их не проверял.",
        agreeHeadline: "Этот инструмент может делать на этом Mac всё, что может Vitruvian.",
        agreeDetail: "Это отдельная программа. Она может читать экран, управлять другими приложениями, читать ваши файлы и использовать сеть. Vitruvian не ограничивает и не проверяет её действия. Добавляйте инструмент, только если доверяете его автору.",
        agreeAdd: "Добавить инструмент",
        updateTitleFormat: "Обновить «%@»?",
        updateVersionsFormat: "У вас версия %1$@. В этой папке версия %2$@.",
        updateChanged: "То, что инструмент сообщает о себе, изменилось с момента вашего согласия. Прочитайте ещё раз.",
        updateKeepsData: "Сохранённые инструментом данные останутся.",
        updateConfirm: "Обновить инструмент",
        removeTitleFormat: "Удалить «%@»?",
        removeMessage: "Vitruvian удалит свою копию инструмента. Папка, из которой вы его добавили, не будет затронута.",
        removeKeepData: "Удалить, сохранив его данные",
        removeDeleteData: "Удалить вместе с его данными",
        removeKeptTitleFormat: "Данные «%@» не удалены",
        removeKeptMessage: "Его программа не завершилась, поэтому Vitruvian не удалил сохранённые инструментом данные. Они в этой папке:",
        removeUndeletedTitleFormat: "Некоторые файлы «%@» не удалось удалить",
        removeUndeletedMessage: "Инструмент удалён, но Vitruvian не смог удалить все его файлы. То, что осталось, находится здесь:",
        stoppedFormat: "«%@» перестал работать",
        panelNotShown: "Не удалось показать эту страницу. Причина указана в журнале инструмента в Настройках.",
        showInIsland: "Показывать в Dynamic Island",
        catalogTitle: "Каталог Vitruvian",
        catalogEmpty: "В каталоге пока нет расширений и инструментов.",
        installButton: "Установить",
        installedLabel: "Установлен",
        updateAvailable: "Доступно обновление",
        updateNow: "Обновить",
        agreeCatalog: "Из каталога Vitruvian: VitruvianSoftware включила этот инструмент в каталог, и загруженный файл в точности тот, что указан в каталоге.",
        catalogUnreachable: "Vitruvian не удалось связаться с каталогом. Проверьте подключение и попробуйте снова.",
        catalogNotOurs: "Этот список инструментов не подписан VitruvianSoftware, поэтому Vitruvian не будет его использовать.",
        downloadMismatch: "Загруженный файл не совпадает с указанным в каталоге, поэтому ничего не установлено.",
        downloadNotTheTool: "Загруженный файл не является инструментом, указанным в каталоге, поэтому ничего не установлено.",
        installRefusedFormat: "Инструмент «%@» не установлен",
        showStatusInIsland: "Показывать его статус на закрытом Dynamic Island",
        agreeShowsStatus: "Он показывает небольшую отметку статуса на закрытом Dynamic Island.",
        agreeShowsStatusAndWords: "Он показывает небольшую отметку статуса и несколько слов на закрытом Dynamic Island.",
        markOK: "Всё в порядке",
        markBusy: "Выполняется",
        markAttention: "Требует внимания",
        markFailure: "Сбой",
        kindExtension: "Расширение",
        kindTool: "Инструмент",
        pageTitle: "Расширения",
        installedTitle: "Установленные",
        catalogAllInstalled: "Всё из каталога уже установлено.",
        summaryNone: "Расширений пока нет",
        summaryOne: "Установлено 1 расширение",
        summaryCountFormat: "Установлено расширений: %d",
        summaryManage: "Управлять",
        summaryBrowse: "Обзор",
        updateFromCatalog: "Обновить из каталога",
        updateMovesToCatalogFormat: "Вы добавили его из папки %@; теперь он будет поступать из каталога Vitruvian.",
        updateVersionsCatalogFormat: "У вас версия %1$@. В каталоге версия %2$@.",
        sdkLine: "Создайте собственное расширение с помощью Vitruvian SDK.",
        vitruvianSection: "Vitruvian",
        searchSettings: "Поиск по настройкам",
        noSettingsMatchFormat: "Нет настроек, совпадающих с «%@»",
        pageNotSearchable: "Поиск по этой странице невозможен.",
        panelRefusedFormat: "%1$@ прислал страницу, которую Vitruvian не может показать (%2$@). Обновление расширения может помочь.",
        panelTooLargeFormat: "больше предела в %@",
        panelNotWellFormedFormat: "%@ имеет неверный формат",
        chooseFolder: "Выбрать…")

    package static let es = ExternalToolStrings(
        sectionTitle: "Extensiones y herramientas",
        sectionEmpty: "No hay extensiones ni herramientas añadidas. Cada una es un programa aparte. Una extensión añade páginas propias, en el Dynamic Island, en Ajustes o en una ventana. Una herramienta añade comandos a Vitruvian.",
        addButton: "Añadir desde una carpeta…",
        statusRunning: "En ejecución",
        statusStopped: "Dejó de funcionar",
        startAgain: "Iniciar de nuevo",
        statusChanged: "Ha cambiado desde que la añadiste. Actualízala para volver a usarla.",
        commandsTitle: "Comandos",
        usesTitle: "Lo que dice que usa",
        usesNote: "Esta lista la proporciona la herramienta. No limita lo que la herramienta puede hacer.",
        useNotify: "Mostrar mensajes y reproducir el sonido de alerta",
        useOpen: "Abrir enlaces",
        useClipboardRead: "Leer el portapapeles",
        useClipboardWrite: "Escribir en el portapapeles",
        useKeystrokes: "Pegar y pulsar comandos de menú en otras apps",
        useProcesses: "Cerrar otros programas",
        useStorage: "Guardar sus propios ajustes",
        updateButton: "Actualizar desde una carpeta…",
        refusalTitle: "No se puede añadir esta carpeta",
        refusalNoManifest: "No contiene un archivo vitruvian-tool.json, así que no es una herramienta.",
        refusalMistakeFormat: "Su archivo vitruvian-tool.json tiene un error. Díselo a quien hizo la herramienta: %@",
        refusalNeedsNewerFormat: "Necesita algo que esta versión de Vitruvian no tiene: %@",
        refusalProgramFormat: "Su programa, %@, no está o macOS no lo ejecuta.",
        refusalQuarantined: "macOS ha puesto esta carpeta en cuarentena porque se descargó. Vitruvian no la quitará por ti. Si confías en ella, ejecuta esto en Terminal y añádela de nuevo:",
        refusalTooBigFormat: "La carpeta es demasiado grande. Una herramienta puede tener hasta %1$@ y %2$@ archivos.",
        refusalNotAdded: "Vitruvian no pudo copiar la carpeta, o cambió mientras leías. No se añadió nada.",
        agreeTitleFormat: "¿Añadir “%@” a Vitruvian?",
        agreeFromFormat: "Desde %@",
        agreeOwnWords: "El nombre, el editor y la descripción son palabras de la propia herramienta. Vitruvian no los ha comprobado.",
        agreeHeadline: "Esta herramienta puede hacer todo lo que Vitruvian puede hacer en este Mac.",
        agreeDetail: "Es un programa aparte. Puede leer la pantalla, controlar otras apps, leer tus archivos y usar la red. Vitruvian no limita ni comprueba lo que hace. Añádela solo si confías en quien la hizo.",
        agreeAdd: "Añadir herramienta",
        updateTitleFormat: "¿Actualizar “%@”?",
        updateVersionsFormat: "Tienes la versión %1$@. Esta carpeta tiene la versión %2$@.",
        updateChanged: "Lo que la herramienta dice de sí misma ha cambiado desde que aceptaste. Léelo de nuevo.",
        updateKeepsData: "Lo que la herramienta guardó se conserva.",
        updateConfirm: "Actualizar herramienta",
        removeTitleFormat: "¿Eliminar “%@”?",
        removeMessage: "Vitruvian borra su copia de la herramienta. La carpeta desde la que la añadiste no se toca.",
        removeKeepData: "Eliminar y conservar lo que guardó",
        removeDeleteData: "Eliminar y borrar lo que guardó",
        removeKeptTitleFormat: "Lo que “%@” guardó se ha conservado",
        removeKeptMessage: "Su programa no se detuvo, así que Vitruvian no borró lo que la herramienta guardó. Está en esta carpeta:",
        removeUndeletedTitleFormat: "Algunos archivos de “%@” no se pudieron borrar",
        removeUndeletedMessage: "La herramienta se ha eliminado, pero Vitruvian no pudo borrar todos sus archivos. Lo que queda está aquí:",
        stoppedFormat: "“%@” dejó de funcionar",
        panelNotShown: "No se ha podido mostrar esta página. El registro de la herramienta, en Ajustes, dice por qué.",
        showInIsland: "Mostrar en el Dynamic Island",
        catalogTitle: "El catálogo de Vitruvian",
        catalogEmpty: "Todavía no hay extensiones ni herramientas en el catálogo.",
        installButton: "Instalar",
        installedLabel: "Instalada",
        updateAvailable: "Actualización disponible",
        updateNow: "Actualizar",
        agreeCatalog: "Del catálogo de Vitruvian: VitruvianSoftware incluyó esta herramienta, y la descarga es exactamente la que incluyó.",
        catalogUnreachable: "Vitruvian no pudo acceder al catálogo. Comprueba tu conexión e inténtalo de nuevo.",
        catalogNotOurs: "Esta lista de herramientas no está firmada por VitruvianSoftware, así que Vitruvian no la usará.",
        downloadMismatch: "La descarga no es la que indica el catálogo, así que no se instaló nada.",
        downloadNotTheTool: "La descarga no es la herramienta que el catálogo dice, así que no se instaló nada.",
        installRefusedFormat: "No se instaló “%@”",
        showStatusInIsland: "Mostrar su estado en el Dynamic Island cerrado",
        agreeShowsStatus: "Muestra una pequeña marca de estado en el Dynamic Island cerrado.",
        agreeShowsStatusAndWords: "Muestra una pequeña marca de estado y unas pocas palabras en el Dynamic Island cerrado.",
        markOK: "Todo bien",
        markBusy: "Trabajando",
        markAttention: "Requiere atención",
        markFailure: "Falló",
        kindExtension: "Extensión",
        kindTool: "Herramienta",
        pageTitle: "Extensiones",
        installedTitle: "Instalados",
        catalogAllInstalled: "Todo lo del catálogo ya está instalado.",
        summaryNone: "Aún no hay extensiones",
        summaryOne: "1 extensión instalada",
        summaryCountFormat: "%d extensiones instaladas",
        summaryManage: "Gestionar",
        summaryBrowse: "Explorar",
        updateFromCatalog: "Actualizar desde el catálogo",
        updateMovesToCatalogFormat: "La añadiste desde la carpeta %@; a partir de ahora viene del catálogo de Vitruvian.",
        updateVersionsCatalogFormat: "Tienes la versión %1$@. El catálogo tiene la versión %2$@.",
        sdkLine: "Crea tu propia extensión con el Vitruvian SDK.",
        vitruvianSection: "Vitruvian",
        searchSettings: "Buscar en los ajustes",
        noSettingsMatchFormat: "Ningún ajuste coincide con «%@»",
        pageNotSearchable: "No se puede buscar en esta página.",
        panelRefusedFormat: "%1$@ ha enviado una página que Vitruvian no puede mostrar (%2$@). Actualizar la extensión puede solucionarlo.",
        panelTooLargeFormat: "supera el límite de tamaño de %@",
        panelNotWellFormedFormat: "%@ no tiene un formato válido",
        chooseFolder: "Elegir…")

    package static let sk = ExternalToolStrings(
        sectionTitle: "Rozšírenia a nástroje",
        sectionEmpty: "Žiadne rozšírenia ani nástroje nie sú pridané. Každé z nich je samostatný program. Rozšírenie pridáva vlastné stránky, v Dynamic Island, v Nastaveniach alebo v okne. Nástroj pridáva príkazy do aplikácie Vitruvian.",
        addButton: "Pridať z priečinka…",
        statusRunning: "Beží",
        statusStopped: "Prestal fungovať",
        startAgain: "Spustiť znova",
        statusChanged: "Od pridania sa zmenil. Aktualizujte ho, aby ste ho mohli znova používať.",
        commandsTitle: "Príkazy",
        usesTitle: "Čo podľa vlastných slov používa",
        usesNote: "Tento zoznam pochádza od nástroja. Neobmedzuje, čo nástroj môže robiť.",
        useNotify: "Zobrazovať správy a prehrávať zvuk upozornenia",
        useOpen: "Otvárať odkazy",
        useClipboardRead: "Čítať schránku",
        useClipboardWrite: "Zapisovať do schránky",
        useKeystrokes: "Vkladať obsah a spúšťať príkazy ponuky v iných aplikáciách",
        useProcesses: "Ukončovať iné programy",
        useStorage: "Ukladať vlastné nastavenia",
        updateButton: "Aktualizovať z priečinka…",
        refusalTitle: "Tento priečinok sa nedá pridať",
        refusalNoManifest: "Neobsahuje súbor vitruvian-tool.json, takže to nie je nástroj.",
        refusalMistakeFormat: "Súbor vitruvian-tool.json obsahuje chybu. Oznámte to autorovi nástroja: %@",
        refusalNeedsNewerFormat: "Potrebuje niečo, čo táto verzia aplikácie Vitruvian nemá: %@",
        refusalProgramFormat: "Jeho program %@ chýba alebo ho macOS nespustí.",
        refusalQuarantined: "macOS dal tento priečinok do karantény, pretože bol stiahnutý. Vitruvian ju za vás nezruší. Ak mu dôverujete, spustite toto v Termináli a pridajte ho znova:",
        refusalTooBigFormat: "Priečinok je príliš veľký. Nástroj môže mať najviac %1$@ a %2$@ súborov.",
        refusalNotAdded: "Vitruvian nedokázal priečinok skopírovať alebo sa počas čítania zmenil. Nič sa nepridalo.",
        agreeTitleFormat: "Pridať „%@“ do aplikácie Vitruvian?",
        agreeFromFormat: "Z priečinka %@",
        agreeOwnWords: "Názov, vydavateľ a opis sú vlastné slová nástroja. Vitruvian ich neoveril.",
        agreeHeadline: "Tento nástroj môže na tomto Macu robiť všetko, čo môže Vitruvian.",
        agreeDetail: "Je to samostatný program. Môže čítať obrazovku, ovládať iné aplikácie, čítať vaše súbory a používať sieť. Vitruvian neobmedzuje ani nekontroluje, čo robí. Pridajte ho, len ak dôverujete jeho autorovi.",
        agreeAdd: "Pridať nástroj",
        updateTitleFormat: "Aktualizovať „%@“?",
        updateVersionsFormat: "Máte verziu %1$@. V tomto priečinku je verzia %2$@.",
        updateChanged: "To, čo nástroj o sebe uvádza, sa od vášho súhlasu zmenilo. Prečítajte si to znova.",
        updateKeepsData: "To, čo si nástroj uložil, zostane zachované.",
        updateConfirm: "Aktualizovať nástroj",
        removeTitleFormat: "Odstrániť „%@“?",
        removeMessage: "Vitruvian vymaže svoju kópiu nástroja. Priečinok, z ktorého ste ho pridali, zostane nedotknutý.",
        removeKeepData: "Odstrániť a ponechať uložené údaje",
        removeDeleteData: "Odstrániť a vymazať uložené údaje",
        removeKeptTitleFormat: "Údaje nástroja „%@“ zostali zachované",
        removeKeptMessage: "Jeho program sa nezastavil, preto Vitruvian nevymazal to, čo si nástroj uložil. Nachádza sa to v tomto priečinku:",
        removeUndeletedTitleFormat: "Niektoré súbory nástroja „%@“ sa nepodarilo vymazať",
        removeUndeletedMessage: "Nástroj je odstránený, ale Vitruvian nedokázal vymazať všetky jeho súbory. To, čo zostalo, sa nachádza tu:",
        stoppedFormat: "„%@“ prestal fungovať",
        panelNotShown: "Túto stránku sa nepodarilo zobraziť. Dôvod je v protokole nástroja v Nastaveniach.",
        showInIsland: "Zobraziť v Dynamic Island",
        catalogTitle: "Katalóg Vitruvian",
        catalogEmpty: "V katalógu zatiaľ nie sú žiadne rozšírenia ani nástroje.",
        installButton: "Inštalovať",
        installedLabel: "Nainštalovaný",
        updateAvailable: "K dispozícii je aktualizácia",
        updateNow: "Aktualizovať",
        agreeCatalog: "Z katalógu Vitruvian: VitruvianSoftware tento nástroj zaradil do katalógu a stiahnutý súbor je presne ten, ktorý uviedol.",
        catalogUnreachable: "Vitruvian sa nedokázal spojiť s katalógom. Skontrolujte pripojenie a skúste to znova.",
        catalogNotOurs: "Tento zoznam nástrojov nepodpísal VitruvianSoftware, preto ho Vitruvian nepoužije.",
        downloadMismatch: "Stiahnutý súbor nie je ten, ktorý uvádza katalóg, preto sa nič nenainštalovalo.",
        downloadNotTheTool: "Stiahnutý súbor nie je nástroj, za ktorý ho katalóg vydáva, preto sa nič nenainštalovalo.",
        installRefusedFormat: "Nástroj „%@“ sa nenainštaloval",
        showStatusInIsland: "Zobraziť jeho stav na zatvorenom Dynamic Island",
        agreeShowsStatus: "Zobrazuje malú značku stavu na zatvorenom Dynamic Island.",
        agreeShowsStatusAndWords: "Zobrazuje malú značku stavu a niekoľko slov na zatvorenom Dynamic Island.",
        markOK: "V poriadku",
        markBusy: "Pracuje",
        markAttention: "Vyžaduje pozornosť",
        markFailure: "Zlyhalo",
        kindExtension: "Rozšírenie",
        kindTool: "Nástroj",
        pageTitle: "Rozšírenia",
        installedTitle: "Nainštalované",
        catalogAllInstalled: "Všetko z katalógu je nainštalované.",
        summaryNone: "Zatiaľ žiadne rozšírenia",
        summaryOne: "Nainštalované 1 rozšírenie",
        summaryCountFormat: "Nainštalované rozšírenia: %d",
        summaryManage: "Spravovať",
        summaryBrowse: "Prehľadávať",
        updateFromCatalog: "Aktualizovať z katalógu",
        updateMovesToCatalogFormat: "Pridali ste ho z priečinka %@; odteraz pochádza z katalógu Vitruvian.",
        updateVersionsCatalogFormat: "Máte verziu %1$@. V katalógu je verzia %2$@.",
        sdkLine: "Vytvorte si vlastné rozšírenie pomocou Vitruvian SDK.",
        vitruvianSection: "Vitruvian",
        searchSettings: "Hľadať v nastaveniach",
        noSettingsMatchFormat: "Žiadne nastavenie nezodpovedá „%@“",
        pageNotSearchable: "V tejto stránke sa nedá vyhľadávať.",
        panelRefusedFormat: "%1$@ poslal stránku, ktorú Vitruvian nevie zobraziť (%2$@). Aktualizácia rozšírenia to môže vyriešiť.",
        panelTooLargeFormat: "nad limitom veľkosti %@",
        panelNotWellFormedFormat: "%@ nemá správny formát",
        chooseFolder: "Vybrať…")

    package static let de = ExternalToolStrings(
        sectionTitle: "Erweiterungen und Werkzeuge",
        sectionEmpty: "Keine Erweiterungen oder Werkzeuge hinzugefügt. Beide sind eigene Programme. Eine Erweiterung fügt eigene Seiten hinzu, im Dynamic Island, in den Einstellungen oder in einem Fenster. Ein Werkzeug erweitert Vitruvian um Befehle.",
        addButton: "Aus Ordner hinzufügen…",
        statusRunning: "Läuft",
        statusStopped: "Funktioniert nicht mehr",
        startAgain: "Erneut starten",
        statusChanged: "Seit dem Hinzufügen geändert. Aktualisiere es, um es wieder zu verwenden.",
        commandsTitle: "Befehle",
        usesTitle: "Was es nach eigenen Angaben nutzt",
        usesNote: "Diese Liste stammt vom Werkzeug. Sie begrenzt nicht, was das Werkzeug tun kann.",
        useNotify: "Meldungen anzeigen und den Warnton abspielen",
        useOpen: "Links öffnen",
        useClipboardRead: "Die Zwischenablage lesen",
        useClipboardWrite: "In die Zwischenablage schreiben",
        useKeystrokes: "In anderen Apps einfügen und Menübefehle auslösen",
        useProcesses: "Andere Programme beenden",
        useStorage: "Eigene Einstellungen speichern",
        updateButton: "Aus Ordner aktualisieren…",
        refusalTitle: "Dieser Ordner kann nicht hinzugefügt werden",
        refusalNoManifest: "Er enthält keine Datei vitruvian-tool.json und ist daher kein Werkzeug.",
        refusalMistakeFormat: "Die Datei vitruvian-tool.json enthält einen Fehler. Sag es der Person, die das Werkzeug gemacht hat: %@",
        refusalNeedsNewerFormat: "Es braucht etwas, das diese Version von Vitruvian nicht hat: %@",
        refusalProgramFormat: "Sein Programm, %@, fehlt oder macOS führt es nicht aus.",
        refusalQuarantined: "macOS hat diesen Ordner unter Quarantäne gestellt, weil er geladen wurde. Vitruvian hebt das nicht für dich auf. Wenn du ihm vertraust, führe dies im Terminal aus und füge ihn dann erneut hinzu:",
        refusalTooBigFormat: "Der Ordner ist zu groß. Ein Werkzeug darf höchstens %1$@ und %2$@ Dateien enthalten.",
        refusalNotAdded: "Vitruvian konnte den Ordner nicht kopieren, oder er hat sich geändert, während du gelesen hast. Nichts wurde hinzugefügt.",
        agreeTitleFormat: "„%@“ zu Vitruvian hinzufügen?",
        agreeFromFormat: "Aus %@",
        agreeOwnWords: "Name, Herausgeber und Beschreibung sind Angaben des Werkzeugs selbst. Vitruvian hat sie nicht geprüft.",
        agreeHeadline: "Dieses Werkzeug kann auf diesem Mac alles tun, was Vitruvian kann.",
        agreeDetail: "Es ist ein eigenes Programm. Es kann den Bildschirm lesen, andere Apps steuern, deine Dateien lesen und das Netzwerk nutzen. Vitruvian begrenzt und prüft nicht, was es tut. Füge es nur hinzu, wenn du der Person vertraust, die es gemacht hat.",
        agreeAdd: "Werkzeug hinzufügen",
        updateTitleFormat: "„%@“ aktualisieren?",
        updateVersionsFormat: "Du hast Version %1$@. Dieser Ordner enthält Version %2$@.",
        updateChanged: "Was das Werkzeug über sich angibt, hat sich seit deiner Zustimmung geändert. Lies es noch einmal.",
        updateKeepsData: "Was das Werkzeug gespeichert hat, bleibt erhalten.",
        updateConfirm: "Werkzeug aktualisieren",
        removeTitleFormat: "„%@“ entfernen?",
        removeMessage: "Vitruvian löscht seine Kopie des Werkzeugs. Der Ordner, aus dem du es hinzugefügt hast, bleibt unberührt.",
        removeKeepData: "Entfernen, Gespeichertes behalten",
        removeDeleteData: "Entfernen und Gespeichertes löschen",
        removeKeptTitleFormat: "Was „%@“ gespeichert hat, wurde behalten",
        removeKeptMessage: "Sein Programm ließ sich nicht beenden, daher hat Vitruvian nicht gelöscht, was das Werkzeug gespeichert hat. Es liegt in diesem Ordner:",
        removeUndeletedTitleFormat: "Einige Dateien von „%@“ konnten nicht gelöscht werden",
        removeUndeletedMessage: "Das Werkzeug ist entfernt, aber Vitruvian konnte nicht alle seine Dateien löschen. Was übrig ist, liegt hier:",
        stoppedFormat: "„%@“ funktioniert nicht mehr",
        panelNotShown: "Diese Seite konnte nicht angezeigt werden. Das Protokoll des Werkzeugs in den Einstellungen nennt den Grund.",
        showInIsland: "Im Dynamic Island anzeigen",
        catalogTitle: "Der Vitruvian-Katalog",
        catalogEmpty: "Im Katalog sind noch keine Erweiterungen oder Werkzeuge.",
        installButton: "Installieren",
        installedLabel: "Installiert",
        updateAvailable: "Aktualisierung verfügbar",
        updateNow: "Aktualisieren",
        agreeCatalog: "Aus dem Vitruvian-Katalog: VitruvianSoftware hat dieses Werkzeug aufgenommen, und der Download ist genau der aufgeführte.",
        catalogUnreachable: "Vitruvian konnte den Katalog nicht erreichen. Prüfe deine Verbindung und versuche es erneut.",
        catalogNotOurs: "Diese Werkzeugliste ist nicht von VitruvianSoftware signiert, darum verwendet Vitruvian sie nicht.",
        downloadMismatch: "Der Download ist nicht der, den der Katalog aufführt, darum wurde nichts installiert.",
        downloadNotTheTool: "Der Download ist nicht das Werkzeug, das der Katalog angibt, darum wurde nichts installiert.",
        installRefusedFormat: "„%@“ wurde nicht installiert",
        showStatusInIsland: "Seinen Status im geschlossenen Dynamic Island anzeigen",
        agreeShowsStatus: "Es zeigt eine kleine Statusmarke im geschlossenen Dynamic Island.",
        agreeShowsStatusAndWords: "Es zeigt eine kleine Statusmarke und ein paar Worte im geschlossenen Dynamic Island.",
        markOK: "In Ordnung",
        markBusy: "Arbeitet",
        markAttention: "Braucht Aufmerksamkeit",
        markFailure: "Fehlgeschlagen",
        kindExtension: "Erweiterung",
        kindTool: "Werkzeug",
        pageTitle: "Erweiterungen",
        installedTitle: "Installiert",
        catalogAllInstalled: "Alles aus dem Katalog ist installiert.",
        summaryNone: "Noch keine Erweiterungen",
        summaryOne: "1 Erweiterung installiert",
        summaryCountFormat: "%d Erweiterungen installiert",
        summaryManage: "Verwalten",
        summaryBrowse: "Durchsuchen",
        updateFromCatalog: "Aus dem Katalog aktualisieren",
        updateMovesToCatalogFormat: "Du hast es aus dem Ordner %@ hinzugefügt; ab jetzt kommt es aus dem Vitruvian-Katalog.",
        updateVersionsCatalogFormat: "Du hast Version %1$@. Der Katalog enthält Version %2$@.",
        sdkLine: "Bau deine eigene Erweiterung mit dem Vitruvian SDK.",
        vitruvianSection: "Vitruvian",
        searchSettings: "Einstellungen durchsuchen",
        noSettingsMatchFormat: "Keine Einstellung passt zu „%@“",
        pageNotSearchable: "Diese Seite kann nicht durchsucht werden.",
        panelRefusedFormat: "%1$@ hat eine Seite gesendet, die Vitruvian nicht anzeigen kann (%2$@). Ein Update der Erweiterung kann das beheben.",
        panelTooLargeFormat: "größer als die Grenze von %@",
        panelNotWellFormedFormat: "%@ ist nicht wohlgeformt",
        chooseFolder: "Auswählen…")

    package static let fr = ExternalToolStrings(
        sectionTitle: "Extensions et outils",
        sectionEmpty: "Aucune extension ni aucun outil ajouté. Chacun est un programme distinct. Une extension ajoute ses propres pages, dans le Dynamic Island, dans les Réglages ou dans une fenêtre. Un outil ajoute des commandes à Vitruvian.",
        addButton: "Ajouter depuis un dossier…",
        statusRunning: "En cours d’exécution",
        statusStopped: "A cessé de fonctionner",
        startAgain: "Redémarrer",
        statusChanged: "Modifié depuis son ajout. Mettez-le à jour pour l’utiliser de nouveau.",
        commandsTitle: "Commandes",
        usesTitle: "Ce qu’il déclare utiliser",
        usesNote: "Cette liste vient de l’outil. Elle ne limite pas ce que l’outil peut faire.",
        useNotify: "Afficher des messages et émettre le son d’alerte",
        useOpen: "Ouvrir des liens",
        useClipboardRead: "Lire le presse-papiers",
        useClipboardWrite: "Écrire dans le presse-papiers",
        useKeystrokes: "Coller et activer des commandes de menu dans d’autres apps",
        useProcesses: "Arrêter d’autres programmes",
        useStorage: "Enregistrer ses propres réglages",
        updateButton: "Mettre à jour depuis un dossier…",
        refusalTitle: "Impossible d’ajouter ce dossier",
        refusalNoManifest: "Il ne contient pas de fichier vitruvian-tool.json, ce n’est donc pas un outil.",
        refusalMistakeFormat: "Son fichier vitruvian-tool.json contient une erreur. Signalez-la à l’auteur de l’outil\u{00A0}: %@",
        refusalNeedsNewerFormat: "Il a besoin de quelque chose que cette version de Vitruvian n’a pas\u{00A0}: %@",
        refusalProgramFormat: "Son programme, %@, est introuvable ou macOS refuse de l’exécuter.",
        refusalQuarantined: "macOS a placé ce dossier en quarantaine parce qu’il a été téléchargé. Vitruvian ne la lèvera pas à votre place. Si vous lui faites confiance, exécutez ceci dans Terminal, puis ajoutez-le de nouveau\u{00A0}:",
        refusalTooBigFormat: "Le dossier est trop volumineux. Un outil peut contenir jusqu’à %1$@ et %2$@ fichiers.",
        refusalNotAdded: "Vitruvian n’a pas pu copier le dossier, ou il a changé pendant votre lecture. Rien n’a été ajouté.",
        agreeTitleFormat: "Ajouter «\u{00A0}%@\u{00A0}» à Vitruvian\u{00A0}?",
        agreeFromFormat: "Depuis %@",
        agreeOwnWords: "Le nom, l’éditeur et la description sont ceux que l’outil indique lui-même. Vitruvian ne les a pas vérifiés.",
        agreeHeadline: "Cet outil peut faire tout ce que Vitruvian peut faire sur ce Mac.",
        agreeDetail: "C’est un programme distinct. Il peut lire l’écran, contrôler d’autres apps, lire vos fichiers et utiliser le réseau. Vitruvian ne limite ni ne vérifie ce qu’il fait. Ne l’ajoutez que si vous faites confiance à son auteur.",
        agreeAdd: "Ajouter l’outil",
        updateTitleFormat: "Mettre à jour «\u{00A0}%@\u{00A0}»\u{00A0}?",
        updateVersionsFormat: "Vous avez la version %1$@. Ce dossier contient la version %2$@.",
        updateChanged: "Ce que l’outil déclare sur lui-même a changé depuis votre accord. Relisez-le.",
        updateKeepsData: "Ce que l’outil a enregistré est conservé.",
        updateConfirm: "Mettre à jour l’outil",
        removeTitleFormat: "Supprimer «\u{00A0}%@\u{00A0}»\u{00A0}?",
        removeMessage: "Vitruvian efface sa copie de l’outil. Le dossier depuis lequel vous l’avez ajouté n’est pas touché.",
        removeKeepData: "Supprimer et garder ses données",
        removeDeleteData: "Supprimer et effacer ses données",
        removeKeptTitleFormat: "Les données de «\u{00A0}%@\u{00A0}» ont été conservées",
        removeKeptMessage: "Son programme ne s’est pas arrêté, donc Vitruvian n’a pas effacé ce que l’outil a enregistré. Cela se trouve dans ce dossier\u{00A0}:",
        removeUndeletedTitleFormat: "Certains fichiers de «\u{00A0}%@\u{00A0}» n’ont pas pu être effacés",
        removeUndeletedMessage: "L’outil est supprimé, mais Vitruvian n’a pas pu effacer tous ses fichiers. Ce qui reste se trouve ici\u{00A0}:",
        stoppedFormat: "«\u{00A0}%@\u{00A0}» a cessé de fonctionner",
        panelNotShown: "Cette page n’a pas pu être affichée. Le journal de l’outil, dans les Réglages, en donne la raison.",
        showInIsland: "Afficher dans le Dynamic Island",
        catalogTitle: "Le catalogue Vitruvian",
        catalogEmpty: "Le catalogue ne contient encore aucune extension ni aucun outil.",
        installButton: "Installer",
        installedLabel: "Installé",
        updateAvailable: "Mise à jour disponible",
        updateNow: "Mettre à jour",
        agreeCatalog: "Du catalogue Vitruvian\u{00A0}: VitruvianSoftware a répertorié cet outil, et le téléchargement est exactement celui qui est répertorié.",
        catalogUnreachable: "Vitruvian n’a pas pu joindre le catalogue. Vérifiez votre connexion et réessayez.",
        catalogNotOurs: "Cette liste d’outils n’est pas signée par VitruvianSoftware, donc Vitruvian ne l’utilisera pas.",
        downloadMismatch: "Le téléchargement n’est pas celui que le catalogue indique, donc rien n’a été installé.",
        downloadNotTheTool: "Le téléchargement n’est pas l’outil que le catalogue annonce, donc rien n’a été installé.",
        installRefusedFormat: "«\u{00A0}%@\u{00A0}» n’a pas été installé",
        showStatusInIsland: "Afficher son état sur le Dynamic Island fermé",
        agreeShowsStatus: "Il affiche une petite marque d’état sur le Dynamic Island fermé.",
        agreeShowsStatusAndWords: "Il affiche une petite marque d’état et quelques mots sur le Dynamic Island fermé.",
        markOK: "Tout va bien",
        markBusy: "En cours",
        markAttention: "Demande votre attention",
        markFailure: "Échec",
        kindExtension: "Module d’extension",
        kindTool: "Outil",
        pageTitle: "Modules d’extension",
        installedTitle: "Installés",
        catalogAllInstalled: "Tout le catalogue est installé.",
        summaryNone: "Aucun module d’extension pour l’instant",
        summaryOne: "1 module d’extension installé",
        summaryCountFormat: "%d modules d’extension installés",
        summaryManage: "Gérer",
        summaryBrowse: "Parcourir",
        updateFromCatalog: "Mettre à jour depuis le catalogue",
        updateMovesToCatalogFormat: "Vous l’avez ajouté depuis le dossier %@\u{00A0}; désormais, il provient du catalogue Vitruvian.",
        updateVersionsCatalogFormat: "Vous avez la version %1$@. Le catalogue contient la version %2$@.",
        sdkLine: "Créez votre propre module d’extension avec le Vitruvian SDK.",
        vitruvianSection: "Vitruvian",
        searchSettings: "Rechercher dans les réglages",
        noSettingsMatchFormat: "Aucun réglage ne correspond à «\u{00A0}%@\u{00A0}»",
        pageNotSearchable: "Impossible de rechercher dans cette page.",
        panelRefusedFormat: "%1$@ a envoyé une page que Vitruvian ne peut pas afficher (%2$@). Mettre à jour le module d’extension peut corriger cela.",
        panelTooLargeFormat: "au-delà de la limite de taille de %@",
        panelNotWellFormedFormat: "%@ est mal formé",
        chooseFolder: "Choisir…")

    package static let it = ExternalToolStrings(
        sectionTitle: "Estensioni e strumenti",
        sectionEmpty: "Nessuna estensione o strumento aggiunto. Ognuno è un programma separato. Un’estensione aggiunge pagine proprie, nel Dynamic Island, nelle Impostazioni o in una finestra. Uno strumento aggiunge comandi a Vitruvian.",
        addButton: "Aggiungi da una cartella…",
        statusRunning: "In esecuzione",
        statusStopped: "Ha smesso di funzionare",
        startAgain: "Avvia di nuovo",
        statusChanged: "È cambiato da quando lo hai aggiunto. Aggiornalo per usarlo di nuovo.",
        commandsTitle: "Comandi",
        usesTitle: "Cosa dichiara di usare",
        usesNote: "Questo elenco viene dallo strumento. Non limita ciò che lo strumento può fare.",
        useNotify: "Mostrare messaggi e riprodurre il suono di avviso",
        useOpen: "Aprire link",
        useClipboardRead: "Leggere gli appunti",
        useClipboardWrite: "Scrivere negli appunti",
        useKeystrokes: "Incollare e attivare comandi di menu in altre app",
        useProcesses: "Terminare altri programmi",
        useStorage: "Salvare le proprie impostazioni",
        updateButton: "Aggiorna da una cartella…",
        refusalTitle: "Impossibile aggiungere questa cartella",
        refusalNoManifest: "Non contiene un file vitruvian-tool.json, quindi non è uno strumento.",
        refusalMistakeFormat: "Il file vitruvian-tool.json contiene un errore. Segnalalo a chi ha creato lo strumento: %@",
        refusalNeedsNewerFormat: "Richiede qualcosa che questa versione di Vitruvian non ha: %@",
        refusalProgramFormat: "Il suo programma, %@, manca oppure macOS non lo esegue.",
        refusalQuarantined: "macOS ha messo questa cartella in quarantena perché è stata scaricata. Vitruvian non la rimuoverà al posto tuo. Se ti fidi, esegui questo nel Terminale e poi aggiungila di nuovo:",
        refusalTooBigFormat: "La cartella è troppo grande. Uno strumento può contenere fino a %1$@ e %2$@ file.",
        refusalNotAdded: "Vitruvian non è riuscito a copiare la cartella, oppure è cambiata mentre leggevi. Non è stato aggiunto nulla.",
        agreeTitleFormat: "Aggiungere “%@” a Vitruvian?",
        agreeFromFormat: "Da %@",
        agreeOwnWords: "Nome, autore e descrizione sono parole dello strumento stesso. Vitruvian non li ha verificati.",
        agreeHeadline: "Questo strumento può fare tutto ciò che Vitruvian può fare su questo Mac.",
        agreeDetail: "È un programma separato. Può leggere lo schermo, controllare altre app, leggere i tuoi file e usare la rete. Vitruvian non limita né controlla ciò che fa. Aggiungilo solo se ti fidi di chi lo ha creato.",
        agreeAdd: "Aggiungi strumento",
        updateTitleFormat: "Aggiornare “%@”?",
        updateVersionsFormat: "Hai la versione %1$@. Questa cartella contiene la versione %2$@.",
        updateChanged: "Ciò che lo strumento dichiara di sé è cambiato da quando hai accettato. Rileggilo.",
        updateKeepsData: "Ciò che lo strumento ha salvato viene conservato.",
        updateConfirm: "Aggiorna strumento",
        removeTitleFormat: "Rimuovere “%@”?",
        removeMessage: "Vitruvian elimina la propria copia dello strumento. La cartella da cui lo hai aggiunto non viene toccata.",
        removeKeepData: "Rimuovi e conserva i dati salvati",
        removeDeleteData: "Rimuovi ed elimina i dati salvati",
        removeKeptTitleFormat: "Ciò che “%@” ha salvato è stato conservato",
        removeKeptMessage: "Il suo programma non si è fermato, quindi Vitruvian non ha eliminato ciò che lo strumento ha salvato. Si trova in questa cartella:",
        removeUndeletedTitleFormat: "Non è stato possibile eliminare alcuni file di “%@”",
        removeUndeletedMessage: "Lo strumento è stato rimosso, ma Vitruvian non è riuscito a eliminare tutti i suoi file. Ciò che resta si trova qui:",
        stoppedFormat: "“%@” ha smesso di funzionare",
        panelNotShown: "Impossibile mostrare questa pagina. Il registro dello strumento, nelle Impostazioni, spiega perché.",
        showInIsland: "Mostra nel Dynamic Island",
        catalogTitle: "Il catalogo di Vitruvian",
        catalogEmpty: "Non ci sono ancora estensioni o strumenti nel catalogo.",
        installButton: "Installa",
        installedLabel: "Installato",
        updateAvailable: "Aggiornamento disponibile",
        updateNow: "Aggiorna",
        agreeCatalog: "Dal catalogo di Vitruvian: VitruvianSoftware ha inserito questo strumento, e il download è esattamente quello indicato.",
        catalogUnreachable: "Vitruvian non è riuscito a raggiungere il catalogo. Controlla la connessione e riprova.",
        catalogNotOurs: "Questo elenco di strumenti non è firmato da VitruvianSoftware, quindi Vitruvian non lo userà.",
        downloadMismatch: "Il download non è quello indicato nel catalogo, quindi non è stato installato nulla.",
        downloadNotTheTool: "Il download non è lo strumento che il catalogo dichiara, quindi non è stato installato nulla.",
        installRefusedFormat: "“%@” non è stato installato",
        showStatusInIsland: "Mostra il suo stato nel Dynamic Island chiuso",
        agreeShowsStatus: "Mostra un piccolo indicatore di stato nel Dynamic Island chiuso.",
        agreeShowsStatusAndWords: "Mostra un piccolo indicatore di stato e poche parole nel Dynamic Island chiuso.",
        markOK: "Tutto a posto",
        markBusy: "Al lavoro",
        markAttention: "Richiede attenzione",
        markFailure: "Non riuscito",
        kindExtension: "Estensione",
        kindTool: "Strumento",
        pageTitle: "Estensioni",
        installedTitle: "Installati",
        catalogAllInstalled: "Tutto il catalogo è installato.",
        summaryNone: "Nessuna estensione per ora",
        summaryOne: "1 estensione installata",
        summaryCountFormat: "%d estensioni installate",
        summaryManage: "Gestisci",
        summaryBrowse: "Sfoglia",
        updateFromCatalog: "Aggiorna dal catalogo",
        updateMovesToCatalogFormat: "L’hai aggiunto dalla cartella %@; d’ora in poi arriva dal catalogo di Vitruvian.",
        updateVersionsCatalogFormat: "Hai la versione %1$@. Il catalogo contiene la versione %2$@.",
        sdkLine: "Crea la tua estensione con il Vitruvian SDK.",
        vitruvianSection: "Vitruvian",
        searchSettings: "Cerca nelle impostazioni",
        noSettingsMatchFormat: "Nessuna impostazione corrisponde a “%@”",
        pageNotSearchable: "Non è possibile cercare in questa pagina.",
        panelRefusedFormat: "%1$@ ha inviato una pagina che Vitruvian non può mostrare (%2$@). Aggiornare l’estensione potrebbe risolvere.",
        panelTooLargeFormat: "oltre il limite di dimensione di %@",
        panelNotWellFormedFormat: "%@ non è ben formato",
        chooseFolder: "Scegli…")

    package static let ja = ExternalToolStrings(
        sectionTitle: "拡張機能とツール",
        sectionEmpty: "拡張機能もツールも追加されていません。どちらも別のプログラムです。拡張機能は、Dynamic Island、「設定」、またはウインドウに独自のページを追加します。ツールは、Vitruvianにコマンドを追加します。",
        addButton: "フォルダから追加…",
        statusRunning: "実行中",
        statusStopped: "動作を停止しました",
        startAgain: "もう一度開始",
        statusChanged: "追加後に変更されました。もう一度使うにはアップデートしてください。",
        commandsTitle: "コマンド",
        usesTitle: "ツールが使うと申告しているもの",
        usesNote: "このリストはツールが申告したものです。ツールにできることを制限するものではありません。",
        useNotify: "メッセージの表示と警告音の再生",
        useOpen: "リンクを開く",
        useClipboardRead: "クリップボードの読み取り",
        useClipboardWrite: "クリップボードへの書き込み",
        useKeystrokes: "ほかのアプリでのペーストとメニューコマンドの実行",
        useProcesses: "ほかのプログラムの終了",
        useStorage: "ツール自身の設定の保存",
        updateButton: "フォルダからアップデート…",
        refusalTitle: "このフォルダは追加できません",
        refusalNoManifest: "vitruvian-tool.jsonファイルがないため、ツールではありません。",
        refusalMistakeFormat: "vitruvian-tool.jsonファイルに誤りがあります。ツールの作者に伝えてください: %@",
        refusalNeedsNewerFormat: "このバージョンのVitruvianにないものが必要です: %@",
        refusalProgramFormat: "プログラム（%@）が見つからないか、macOSが実行できません。",
        refusalQuarantined: "このフォルダはダウンロードされたものなので、macOSによって隔離されています。Vitruvianが代わりに解除することはありません。信頼できる場合は、ターミナルで次を実行してから、もう一度追加してください:",
        refusalTooBigFormat: "フォルダが大きすぎます。ツールに含められるのは最大%1$@、ファイル%2$@個までです。",
        refusalNotAdded: "Vitruvianがフォルダをコピーできなかったか、読んでいる間にフォルダが変更されました。何も追加されていません。",
        agreeTitleFormat: "「%@」をVitruvianに追加しますか？",
        agreeFromFormat: "場所: %@",
        agreeOwnWords: "名前、発行元、説明はツール自身が申告したものです。Vitruvianは確認していません。",
        agreeHeadline: "このツールは、このMacでVitruvianにできることをすべて実行できます。",
        agreeDetail: "これは別のプログラムです。画面の読み取り、ほかのアプリの操作、ファイルの読み取り、ネットワークの使用ができます。Vitruvianはその動作を制限も確認もしません。作者を信頼できる場合にのみ追加してください。",
        agreeAdd: "ツールを追加",
        updateTitleFormat: "「%@」をアップデートしますか？",
        updateVersionsFormat: "現在のバージョンは%1$@です。このフォルダのバージョンは%2$@です。",
        updateChanged: "同意した後、ツールが自身について申告している内容が変わりました。もう一度お読みください。",
        updateKeepsData: "ツールが保存したデータは保持されます。",
        updateConfirm: "ツールをアップデート",
        removeTitleFormat: "「%@」を削除しますか？",
        removeMessage: "Vitruvianが持つツールのコピーを削除します。追加元のフォルダには手を加えません。",
        removeKeepData: "削除して保存データを残す",
        removeDeleteData: "削除して保存データも消去",
        removeKeptTitleFormat: "「%@」が保存したデータは残されました",
        removeKeptMessage: "プログラムが停止しなかったため、Vitruvianはツールが保存したデータを削除しませんでした。データは次のフォルダにあります:",
        removeUndeletedTitleFormat: "「%@」の一部のファイルを削除できませんでした",
        removeUndeletedMessage: "ツールは削除されましたが、Vitruvianはそのファイルをすべて削除することはできませんでした。残っているものは次の場所にあります:",
        stoppedFormat: "「%@」が動作を停止しました",
        panelNotShown: "このページを表示できませんでした。理由は「設定」にあるツールのログに記録されています。",
        showInIsland: "Dynamic Islandに表示",
        catalogTitle: "Vitruvianカタログ",
        catalogEmpty: "カタログにはまだ拡張機能もツールもありません。",
        installButton: "インストール",
        installedLabel: "インストール済み",
        updateAvailable: "アップデートがあります",
        updateNow: "アップデート",
        agreeCatalog: "Vitruvianカタログから：VitruvianSoftwareがこのツールを掲載しており、ダウンロードしたファイルは掲載されたものと完全に一致しています。",
        catalogUnreachable: "Vitruvianはカタログに接続できませんでした。接続を確認して、もう一度お試しください。",
        catalogNotOurs: "このツールの一覧はVitruvianSoftwareによって署名されていないため、Vitruvianは使用しません。",
        downloadMismatch: "ダウンロードしたファイルがカタログに掲載されたものと一致しないため、何もインストールされていません。",
        downloadNotTheTool: "ダウンロードしたファイルがカタログに記載されたツールではないため、何もインストールされていません。",
        installRefusedFormat: "「%@」はインストールされませんでした",
        showStatusInIsland: "閉じたDynamic Islandに状態を表示",
        agreeShowsStatus: "閉じたDynamic Islandに小さな状態マークを表示します。",
        agreeShowsStatusAndWords: "閉じたDynamic Islandに小さな状態マークと短い言葉を表示します。",
        markOK: "問題なし",
        markBusy: "処理中",
        markAttention: "確認が必要",
        markFailure: "失敗",
        kindExtension: "拡張機能",
        kindTool: "ツール",
        pageTitle: "拡張機能",
        installedTitle: "インストール済み",
        catalogAllInstalled: "カタログのものはすべてインストール済みです。",
        summaryNone: "拡張機能はまだありません",
        summaryOne: "1個の拡張機能がインストール済み",
        summaryCountFormat: "%d個の拡張機能がインストール済み",
        summaryManage: "管理",
        summaryBrowse: "参照",
        updateFromCatalog: "カタログからアップデート",
        updateMovesToCatalogFormat: "このツールはフォルダ %@ から追加しましたが、今後はVitruvianカタログから入手します。",
        updateVersionsCatalogFormat: "現在のバージョンは%1$@です。カタログのバージョンは%2$@です。",
        sdkLine: "Vitruvian SDKで独自の拡張機能を作成できます。",
        vitruvianSection: "Vitruvian",
        searchSettings: "設定を検索",
        noSettingsMatchFormat: "「%@」に一致する設定はありません",
        pageNotSearchable: "このページは検索できません。",
        panelRefusedFormat: "%1$@ から、Vitruvian で表示できないページが送られてきました（%2$@）。拡張機能をアップデートすると直る場合があります。",
        panelTooLargeFormat: "上限の %@ を超えています",
        panelNotWellFormedFormat: "%@ の形式が正しくありません",
        chooseFolder: "選択…")

    package static let ko = ExternalToolStrings(
        sectionTitle: "확장 프로그램 및 도구",
        sectionEmpty: "추가된 확장 프로그램이나 도구가 없습니다. 둘 다 별도의 프로그램입니다. 확장 프로그램은 Dynamic Island, 설정 또는 창에 자체 페이지를 추가합니다. 도구는 Vitruvian에 명령을 추가합니다.",
        addButton: "폴더에서 추가…",
        statusRunning: "실행 중",
        statusStopped: "작동이 중지됨",
        startAgain: "다시 시작",
        statusChanged: "추가한 뒤 변경되었습니다. 다시 사용하려면 업데이트하세요.",
        commandsTitle: "명령",
        usesTitle: "도구가 사용한다고 밝힌 항목",
        usesNote: "이 목록은 도구가 직접 밝힌 것입니다. 도구가 할 수 있는 일을 제한하지 않습니다.",
        useNotify: "메시지 표시 및 경고음 재생",
        useOpen: "링크 열기",
        useClipboardRead: "클립보드 읽기",
        useClipboardWrite: "클립보드에 쓰기",
        useKeystrokes: "다른 앱에서 붙여넣기 및 메뉴 명령 실행",
        useProcesses: "다른 프로그램 종료",
        useStorage: "도구 자체 설정 저장",
        updateButton: "폴더에서 업데이트…",
        refusalTitle: "이 폴더는 추가할 수 없습니다",
        refusalNoManifest: "vitruvian-tool.json 파일이 없으므로 도구가 아닙니다.",
        refusalMistakeFormat: "vitruvian-tool.json 파일에 오류가 있습니다. 도구를 만든 사람에게 알려 주세요: %@",
        refusalNeedsNewerFormat: "이 버전의 Vitruvian에 없는 기능이 필요합니다: %@",
        refusalProgramFormat: "프로그램(%@)이 없거나 macOS에서 실행할 수 없습니다.",
        refusalQuarantined: "이 폴더는 다운로드된 것이라 macOS가 격리했습니다. Vitruvian은 이를 대신 해제하지 않습니다. 신뢰한다면 터미널에서 다음을 실행한 뒤 다시 추가하세요:",
        refusalTooBigFormat: "폴더가 너무 큽니다. 도구는 최대 %1$@, 파일 %2$@개까지 담을 수 있습니다.",
        refusalNotAdded: "Vitruvian이 폴더를 복사하지 못했거나, 읽는 동안 폴더가 변경되었습니다. 아무것도 추가되지 않았습니다.",
        agreeTitleFormat: "‘%@’을(를) Vitruvian에 추가할까요?",
        agreeFromFormat: "위치: %@",
        agreeOwnWords: "이름, 게시자, 설명은 도구가 직접 밝힌 내용입니다. Vitruvian은 이를 확인하지 않았습니다.",
        agreeHeadline: "이 도구는 이 Mac에서 Vitruvian이 할 수 있는 모든 일을 할 수 있습니다.",
        agreeDetail: "별도의 프로그램입니다. 화면을 읽고, 다른 앱을 제어하고, 파일을 읽고, 네트워크를 사용할 수 있습니다. Vitruvian은 이 도구가 하는 일을 제한하거나 확인하지 않습니다. 만든 사람을 신뢰할 때만 추가하세요.",
        agreeAdd: "도구 추가",
        updateTitleFormat: "‘%@’을(를) 업데이트할까요?",
        updateVersionsFormat: "현재 버전은 %1$@입니다. 이 폴더의 버전은 %2$@입니다.",
        updateChanged: "동의한 뒤 도구가 자신에 대해 밝힌 내용이 바뀌었습니다. 다시 읽어 보세요.",
        updateKeepsData: "도구가 저장한 내용은 유지됩니다.",
        updateConfirm: "도구 업데이트",
        removeTitleFormat: "‘%@’을(를) 제거할까요?",
        removeMessage: "Vitruvian이 가진 도구 사본을 삭제합니다. 도구를 추가한 원래 폴더는 건드리지 않습니다.",
        removeKeepData: "제거하고 저장한 내용 유지",
        removeDeleteData: "제거하고 저장한 내용 삭제",
        removeKeptTitleFormat: "‘%@’이(가) 저장한 내용은 유지되었습니다",
        removeKeptMessage: "프로그램이 멈추지 않아 Vitruvian이 도구가 저장한 내용을 삭제하지 않았습니다. 저장한 내용은 다음 폴더에 있습니다:",
        removeUndeletedTitleFormat: "‘%@’의 일부 파일을 삭제하지 못했습니다",
        removeUndeletedMessage: "도구는 제거되었지만 Vitruvian이 도구의 파일을 모두 삭제하지는 못했습니다. 남은 파일은 다음 위치에 있습니다:",
        stoppedFormat: "‘%@’의 작동이 중지되었습니다",
        panelNotShown: "이 페이지를 표시할 수 없습니다. 이유는 설정에 있는 도구의 로그에서 확인할 수 있습니다.",
        showInIsland: "Dynamic Island에 표시",
        catalogTitle: "Vitruvian 카탈로그",
        catalogEmpty: "카탈로그에 아직 확장 프로그램이나 도구가 없습니다.",
        installButton: "설치",
        installedLabel: "설치됨",
        updateAvailable: "업데이트 있음",
        updateNow: "업데이트",
        agreeCatalog: "Vitruvian 카탈로그에서: VitruvianSoftware가 이 도구를 등록했으며, 다운로드한 파일은 등록된 파일과 정확히 같습니다.",
        catalogUnreachable: "Vitruvian이 카탈로그에 연결하지 못했습니다. 연결을 확인하고 다시 시도하세요.",
        catalogNotOurs: "이 도구 목록은 VitruvianSoftware가 서명하지 않았으므로 Vitruvian은 사용하지 않습니다.",
        downloadMismatch: "다운로드한 파일이 카탈로그에 등록된 파일과 달라 아무것도 설치되지 않았습니다.",
        downloadNotTheTool: "다운로드한 파일이 카탈로그에 적힌 도구가 아니어서 아무것도 설치되지 않았습니다.",
        installRefusedFormat: "‘%@’이(가) 설치되지 않았습니다",
        showStatusInIsland: "닫힌 Dynamic Island에 상태 표시",
        agreeShowsStatus: "닫힌 Dynamic Island에 작은 상태 표시를 보여 줍니다.",
        agreeShowsStatusAndWords: "닫힌 Dynamic Island에 작은 상태 표시와 몇 마디 말을 보여 줍니다.",
        markOK: "정상",
        markBusy: "작업 중",
        markAttention: "확인 필요",
        markFailure: "실패",
        kindExtension: "확장 프로그램",
        kindTool: "도구",
        pageTitle: "확장 프로그램",
        installedTitle: "설치됨",
        catalogAllInstalled: "카탈로그의 모든 항목이 설치되어 있습니다.",
        summaryNone: "아직 확장 프로그램이 없습니다",
        summaryOne: "확장 프로그램 1개 설치됨",
        summaryCountFormat: "확장 프로그램 %d개 설치됨",
        summaryManage: "관리",
        summaryBrowse: "둘러보기",
        updateFromCatalog: "카탈로그에서 업데이트",
        updateMovesToCatalogFormat: "이 도구는 %@ 폴더에서 추가했지만, 이제부터는 Vitruvian 카탈로그에서 받습니다.",
        updateVersionsCatalogFormat: "현재 버전은 %1$@입니다. 카탈로그의 버전은 %2$@입니다.",
        sdkLine: "Vitruvian SDK로 나만의 확장 프로그램을 만들어 보세요.",
        vitruvianSection: "Vitruvian",
        searchSettings: "설정 검색",
        noSettingsMatchFormat: "‘%@’과(와) 일치하는 설정이 없습니다",
        pageNotSearchable: "이 페이지는 검색할 수 없습니다.",
        panelRefusedFormat: "%1$@에서 Vitruvian이 표시할 수 없는 페이지를 보냈습니다(%2$@). 확장 프로그램을 업데이트하면 해결될 수 있습니다.",
        panelTooLargeFormat: "크기 한도 %@ 초과",
        panelNotWellFormedFormat: "%@의 형식이 올바르지 않음",
        chooseFolder: "선택…")

    package static let uk = ExternalToolStrings(
        sectionTitle: "Розширення та інструменти",
        sectionEmpty: "Розширення та інструменти не додано. Кожне з них є окремою програмою. Розширення додає власні сторінки в Dynamic Island, у Параметри або в окреме вікно. Інструмент додає команди до Vitruvian.",
        addButton: "Додати з папки…",
        statusRunning: "Працює",
        statusStopped: "Перестав працювати",
        startAgain: "Запустити знову",
        statusChanged: "Змінився з моменту додавання. Оновіть його, щоб знову користуватися.",
        commandsTitle: "Команди",
        usesTitle: "Що він, за його словами, використовує",
        usesNote: "Цей список надав сам інструмент. Він не обмежує те, що інструмент може робити.",
        useNotify: "Показувати повідомлення та відтворювати звук попередження",
        useOpen: "Відкривати посилання",
        useClipboardRead: "Читати буфер обміну",
        useClipboardWrite: "Записувати в буфер обміну",
        useKeystrokes: "Вставляти текст і вибирати команди меню в інших програмах",
        useProcesses: "Завершувати інші програми",
        useStorage: "Зберігати власні налаштування",
        updateButton: "Оновити з папки…",
        refusalTitle: "Цю папку не можна додати",
        refusalNoManifest: "У ній немає файлу vitruvian-tool.json, тому це не інструмент.",
        refusalMistakeFormat: "У файлі vitruvian-tool.json є помилка. Повідомте автора інструмента: %@",
        refusalNeedsNewerFormat: "Йому потрібне те, чого немає в цій версії Vitruvian: %@",
        refusalProgramFormat: "Його програма %@ відсутня, або macOS не може її запустити.",
        refusalQuarantined: "macOS помістила цю папку на карантин, бо її було завантажено. Vitruvian не зніме його за вас. Якщо ви їй довіряєте, виконайте це в Терміналі й додайте її знову:",
        refusalTooBigFormat: "Папка завелика. Інструмент може містити щонайбільше %1$@ і %2$@ файлів.",
        refusalNotAdded: "Vitruvian не зміг скопіювати папку, або вона змінилася, поки ви читали. Нічого не додано.",
        agreeTitleFormat: "Додати «%@» до Vitruvian?",
        agreeFromFormat: "З папки %@",
        agreeOwnWords: "Назву, видавця й опис указав сам інструмент. Vitruvian їх не перевіряв.",
        agreeHeadline: "Цей інструмент може робити на цьому Mac усе, що може Vitruvian.",
        agreeDetail: "Це окрема програма. Вона може читати екран, керувати іншими програмами, читати ваші файли й користуватися мережею. Vitruvian не обмежує і не перевіряє її дії. Додавайте інструмент, лише якщо довіряєте його авторові.",
        agreeAdd: "Додати інструмент",
        updateTitleFormat: "Оновити «%@»?",
        updateVersionsFormat: "У вас версія %1$@. У цій папці версія %2$@.",
        updateChanged: "Те, що інструмент повідомляє про себе, змінилося з моменту вашої згоди. Прочитайте ще раз.",
        updateKeepsData: "Збережені інструментом дані залишаться.",
        updateConfirm: "Оновити інструмент",
        removeTitleFormat: "Вилучити «%@»?",
        removeMessage: "Vitruvian видалить свою копію інструмента. Папку, з якої ви його додали, не буде змінено.",
        removeKeepData: "Вилучити, зберігши його дані",
        removeDeleteData: "Вилучити разом з його даними",
        removeKeptTitleFormat: "Дані «%@» не видалено",
        removeKeptMessage: "Його програма не завершилася, тому Vitruvian не видалив збережені інструментом дані. Вони в цій папці:",
        removeUndeletedTitleFormat: "Деякі файли «%@» не вдалося видалити",
        removeUndeletedMessage: "Інструмент вилучено, але Vitruvian не зміг видалити всі його файли. Те, що залишилося, міститься тут:",
        stoppedFormat: "«%@» перестав працювати",
        panelNotShown: "Не вдалося показати цю сторінку. Причину вказано в журналі інструмента в Параметрах.",
        showInIsland: "Показувати в Dynamic Island",
        catalogTitle: "Каталог Vitruvian",
        catalogEmpty: "У каталозі ще немає розширень та інструментів.",
        installButton: "Встановити",
        installedLabel: "Встановлено",
        updateAvailable: "Доступне оновлення",
        updateNow: "Оновити",
        agreeCatalog: "З каталогу Vitruvian: VitruvianSoftware додала цей інструмент до каталогу, і завантажений файл точно той, що вказаний у каталозі.",
        catalogUnreachable: "Vitruvian не вдалося зв’язатися з каталогом. Перевірте підключення та спробуйте ще раз.",
        catalogNotOurs: "Цей список інструментів не підписано VitruvianSoftware, тому Vitruvian не використовуватиме його.",
        downloadMismatch: "Завантажений файл не той, що вказаний у каталозі, тому нічого не встановлено.",
        downloadNotTheTool: "Завантажений файл не є інструментом, указаним у каталозі, тому нічого не встановлено.",
        installRefusedFormat: "Інструмент «%@» не встановлено",
        showStatusInIsland: "Показувати його стан на закритому Dynamic Island",
        agreeShowsStatus: "Він показує невелику позначку стану на закритому Dynamic Island.",
        agreeShowsStatusAndWords: "Він показує невелику позначку стану та кілька слів на закритому Dynamic Island.",
        markOK: "Усе гаразд",
        markBusy: "Виконується",
        markAttention: "Потребує уваги",
        markFailure: "Збій",
        kindExtension: "Розширення",
        kindTool: "Інструмент",
        pageTitle: "Розширення",
        installedTitle: "Встановлені",
        catalogAllInstalled: "Усе з каталогу вже встановлено.",
        summaryNone: "Розширень поки немає",
        summaryOne: "Встановлено 1 розширення",
        summaryCountFormat: "Встановлено розширень: %d",
        summaryManage: "Керувати",
        summaryBrowse: "Огляд",
        updateFromCatalog: "Оновити з каталогу",
        updateMovesToCatalogFormat: "Ви додали його з папки %@; відтепер він надходитиме з каталогу Vitruvian.",
        updateVersionsCatalogFormat: "У вас версія %1$@. У каталозі версія %2$@.",
        sdkLine: "Створіть власне розширення за допомогою Vitruvian SDK.",
        vitruvianSection: "Vitruvian",
        searchSettings: "Пошук у параметрах",
        noSettingsMatchFormat: "Немає параметрів, що відповідають «%@»",
        pageNotSearchable: "Пошук на цій сторінці неможливий.",
        panelRefusedFormat: "%1$@ надіслав сторінку, яку Vitruvian не може показати (%2$@). Оновлення розширення може допомогти.",
        panelTooLargeFormat: "більше за межу в %@",
        panelNotWellFormedFormat: "%@ має неправильний формат",
        chooseFolder: "Вибрати…")

    package static let zhHans = ExternalToolStrings(
        sectionTitle: "扩展与工具",
        sectionEmpty: "尚未添加扩展或工具。两者都是独立程序。扩展会在 Dynamic Island、“设置”或窗口中添加自己的页面。工具为 Vitruvian 添加命令。",
        addButton: "从文件夹添加…",
        statusRunning: "正在运行",
        statusStopped: "已停止工作",
        startAgain: "重新启动",
        statusChanged: "添加后已发生更改。请更新后再使用。",
        commandsTitle: "命令",
        usesTitle: "它声明会使用的功能",
        usesNote: "此列表由工具自行提供，并不限制工具能做的事。",
        useNotify: "显示消息并播放提示音",
        useOpen: "打开链接",
        useClipboardRead: "读取剪贴板",
        useClipboardWrite: "写入剪贴板",
        useKeystrokes: "在其他 App 中粘贴并触发菜单命令",
        useProcesses: "结束其他程序",
        useStorage: "保存它自己的设置",
        updateButton: "从文件夹更新…",
        refusalTitle: "无法添加此文件夹",
        refusalNoManifest: "其中没有 vitruvian-tool.json 文件，因此它不是工具。",
        refusalMistakeFormat: "它的 vitruvian-tool.json 文件有错误。请告知工具的作者：%@",
        refusalNeedsNewerFormat: "它需要此版本的 Vitruvian 没有的功能：%@",
        refusalProgramFormat: "它的程序 %@ 不存在，或者 macOS 无法运行它。",
        refusalQuarantined: "此文件夹是下载而来的，macOS 已将其隔离。Vitruvian 不会替你解除隔离。如果你信任它，请在“终端”中运行以下命令，然后重新添加：",
        refusalTooBigFormat: "文件夹太大。一个工具最多可包含 %1$@ 和 %2$@ 个文件。",
        refusalNotAdded: "Vitruvian 无法拷贝该文件夹，或者它在你阅读时发生了更改。未添加任何内容。",
        agreeTitleFormat: "将“%@”添加到 Vitruvian？",
        agreeFromFormat: "来自 %@",
        agreeOwnWords: "名称、发布者和描述均由工具自行提供，Vitruvian 并未核实。",
        agreeHeadline: "此工具可以在这台 Mac 上做 Vitruvian 能做的任何事。",
        agreeDetail: "它是一个独立的程序，可以读取屏幕、控制其他 App、读取你的文件并使用网络。Vitruvian 不会限制或检查它的行为。仅在你信任其作者时才添加。",
        agreeAdd: "添加工具",
        updateTitleFormat: "更新“%@”？",
        updateVersionsFormat: "你当前的版本是 %1$@。此文件夹中的版本是 %2$@。",
        updateChanged: "自你同意以来，工具对自身的说明已发生更改。请重新阅读。",
        updateKeepsData: "工具已保存的内容会保留。",
        updateConfirm: "更新工具",
        removeTitleFormat: "移除“%@”？",
        removeMessage: "Vitruvian 会删除它自己的那份工具副本。你添加工具时所用的文件夹不会受影响。",
        removeKeepData: "移除并保留它保存的内容",
        removeDeleteData: "移除并删除它保存的内容",
        removeKeptTitleFormat: "“%@”保存的内容已保留",
        removeKeptMessage: "它的程序没有停止，所以 Vitruvian 没有删除工具保存的内容。这些内容在此文件夹中：",
        removeUndeletedTitleFormat: "“%@”的部分文件无法删除",
        removeUndeletedMessage: "工具已移除，但 Vitruvian 无法删除它的全部文件。剩下的内容在这里：",
        stoppedFormat: "“%@”已停止工作",
        panelNotShown: "无法显示此页面。原因记录在“设置”中该工具的日志里。",
        showInIsland: "在 Dynamic Island 中显示",
        catalogTitle: "Vitruvian 目录",
        catalogEmpty: "目录中还没有扩展或工具。",
        installButton: "安装",
        installedLabel: "已安装",
        updateAvailable: "有可用更新",
        updateNow: "更新",
        agreeCatalog: "来自 Vitruvian 目录：VitruvianSoftware 收录了此工具，且下载的文件与收录的完全一致。",
        catalogUnreachable: "Vitruvian 无法连接到目录。请检查网络连接，然后重试。",
        catalogNotOurs: "此工具列表未经 VitruvianSoftware 签名，因此 Vitruvian 不会使用它。",
        downloadMismatch: "下载的文件与目录中列出的不一致，因此未安装任何内容。",
        downloadNotTheTool: "下载的文件不是目录所说的工具，因此未安装任何内容。",
        installRefusedFormat: "未安装“%@”",
        showStatusInIsland: "在收起的 Dynamic Island 上显示其状态",
        agreeShowsStatus: "它会在收起的 Dynamic Island 上显示一个小状态标记。",
        agreeShowsStatusAndWords: "它会在收起的 Dynamic Island 上显示一个小状态标记和几个字。",
        markOK: "正常",
        markBusy: "进行中",
        markAttention: "需要留意",
        markFailure: "失败",
        kindExtension: "扩展",
        kindTool: "工具",
        pageTitle: "扩展",
        installedTitle: "已安装",
        catalogAllInstalled: "目录中的内容已全部安装。",
        summaryNone: "还没有扩展",
        summaryOne: "已安装 1 个扩展",
        summaryCountFormat: "已安装 %d 个扩展",
        summaryManage: "管理",
        summaryBrowse: "浏览",
        updateFromCatalog: "从目录更新",
        updateMovesToCatalogFormat: "你是从文件夹 %@ 添加的此工具；今后它将来自 Vitruvian 目录。",
        updateVersionsCatalogFormat: "你当前的版本是 %1$@。目录中的版本是 %2$@。",
        sdkLine: "使用 Vitruvian SDK 打造你自己的扩展。",
        vitruvianSection: "Vitruvian",
        searchSettings: "搜索设置",
        noSettingsMatchFormat: "没有与“%@”匹配的设置",
        pageNotSearchable: "无法搜索此页面。",
        panelRefusedFormat: "%1$@ 发送了 Vitruvian 无法显示的页面（%2$@）。更新该扩展可能会解决此问题。",
        panelTooLargeFormat: "超过 %@ 的大小上限",
        panelNotWellFormedFormat: "%@ 格式不正确",
        chooseFolder: "选取…")

    package static let zhTW = ExternalToolStrings(
        sectionTitle: "擴充功能與工具",
        sectionEmpty: "尚未加入擴充功能或工具。兩者都是獨立程式。擴充功能會在 Dynamic Island、「設定」或視窗中加入自己的頁面。工具為 Vitruvian 加入指令。",
        addButton: "從檔案夾加入…",
        statusRunning: "執行中",
        statusStopped: "已停止運作",
        startAgain: "重新啟動",
        statusChanged: "加入後已變更。請更新後再使用。",
        commandsTitle: "指令",
        usesTitle: "它聲明會使用的功能",
        usesNote: "此列表由工具自行提供，並不限制工具能做的事。",
        useNotify: "顯示訊息並播放提示音",
        useOpen: "打開連結",
        useClipboardRead: "讀取剪貼簿",
        useClipboardWrite: "寫入剪貼簿",
        useKeystrokes: "在其他 App 中貼上並觸發選單指令",
        useProcesses: "結束其他程式",
        useStorage: "儲存它自己的設定",
        updateButton: "從檔案夾更新…",
        refusalTitle: "無法加入此檔案夾",
        refusalNoManifest: "其中沒有 vitruvian-tool.json 檔案，因此它不是工具。",
        refusalMistakeFormat: "它的 vitruvian-tool.json 檔案有錯誤。請告知工具的作者：%@",
        refusalNeedsNewerFormat: "它需要此版本的 Vitruvian 沒有的功能：%@",
        refusalProgramFormat: "它的程式 %@ 不存在，或者 macOS 無法執行它。",
        refusalQuarantined: "此檔案夾是下載而來，macOS 已將其隔離。Vitruvian 不會替你解除隔離。如果你信任它，請在「終端機」中執行以下指令，然後重新加入：",
        refusalTooBigFormat: "檔案夾太大。一個工具最多可包含 %1$@ 和 %2$@ 個檔案。",
        refusalNotAdded: "Vitruvian 無法拷貝該檔案夾，或者它在你閱讀時發生了變更。未加入任何內容。",
        agreeTitleFormat: "將「%@」加入 Vitruvian？",
        agreeFromFormat: "來自 %@",
        agreeOwnWords: "名稱、發佈者和描述均由工具自行提供，Vitruvian 並未核實。",
        agreeHeadline: "此工具可以在這台 Mac 上做 Vitruvian 能做的任何事。",
        agreeDetail: "它是一個獨立的程式，可以讀取螢幕、控制其他 App、讀取你的檔案並使用網路。Vitruvian 不會限制或檢查它的行為。僅在你信任其作者時才加入。",
        agreeAdd: "加入工具",
        updateTitleFormat: "更新「%@」？",
        updateVersionsFormat: "你目前的版本是 %1$@。此檔案夾中的版本是 %2$@。",
        updateChanged: "自你同意以來，工具對自身的說明已經變更。請重新閱讀。",
        updateKeepsData: "工具已儲存的內容會保留。",
        updateConfirm: "更新工具",
        removeTitleFormat: "移除「%@」？",
        removeMessage: "Vitruvian 會刪除它自己的那份工具副本。你加入工具時所用的檔案夾不會受影響。",
        removeKeepData: "移除並保留它儲存的內容",
        removeDeleteData: "移除並刪除它儲存的內容",
        removeKeptTitleFormat: "「%@」儲存的內容已保留",
        removeKeptMessage: "它的程式沒有停止，所以 Vitruvian 沒有刪除工具儲存的內容。這些內容在此檔案夾中：",
        removeUndeletedTitleFormat: "「%@」的部分檔案無法刪除",
        removeUndeletedMessage: "工具已移除，但 Vitruvian 無法刪除它的全部檔案。剩下的內容在這裡：",
        stoppedFormat: "「%@」已停止運作",
        panelNotShown: "無法顯示此頁面。原因記錄在「設定」中此工具的記錄裡。",
        showInIsland: "在 Dynamic Island 中顯示",
        catalogTitle: "Vitruvian 目錄",
        catalogEmpty: "目錄中還沒有擴充功能或工具。",
        installButton: "安裝",
        installedLabel: "已安裝",
        updateAvailable: "有可用的更新",
        updateNow: "更新",
        agreeCatalog: "來自 Vitruvian 目錄：VitruvianSoftware 收錄了此工具，且下載的檔案與收錄的完全一致。",
        catalogUnreachable: "Vitruvian 無法連線到目錄。請檢查網路連線，然後再試一次。",
        catalogNotOurs: "此工具列表未經 VitruvianSoftware 簽署，因此 Vitruvian 不會使用它。",
        downloadMismatch: "下載的檔案與目錄中列出的不一致，因此未安裝任何內容。",
        downloadNotTheTool: "下載的檔案不是目錄所說的工具，因此未安裝任何內容。",
        installRefusedFormat: "未安裝「%@」",
        showStatusInIsland: "在收合的 Dynamic Island 上顯示其狀態",
        agreeShowsStatus: "它會在收合的 Dynamic Island 上顯示一個小狀態標記。",
        agreeShowsStatusAndWords: "它會在收合的 Dynamic Island 上顯示一個小狀態標記和幾個字。",
        markOK: "正常",
        markBusy: "進行中",
        markAttention: "需要留意",
        markFailure: "失敗",
        kindExtension: "擴充功能",
        kindTool: "工具",
        pageTitle: "擴充功能",
        installedTitle: "已安裝",
        catalogAllInstalled: "目錄中的項目都已安裝。",
        summaryNone: "尚無擴充功能",
        summaryOne: "已安裝 1 個擴充功能",
        summaryCountFormat: "已安裝 %d 個擴充功能",
        summaryManage: "管理",
        summaryBrowse: "瀏覽",
        updateFromCatalog: "從目錄更新",
        updateMovesToCatalogFormat: "你是從檔案夾 %@ 加入此工具的；今後它將來自 Vitruvian 目錄。",
        updateVersionsCatalogFormat: "你目前的版本是 %1$@。目錄中的版本是 %2$@。",
        sdkLine: "使用 Vitruvian SDK 打造你自己的擴充功能。",
        vitruvianSection: "Vitruvian",
        searchSettings: "搜尋設定",
        noSettingsMatchFormat: "沒有符合「%@」的設定",
        pageNotSearchable: "無法搜尋此頁面。",
        panelRefusedFormat: "%1$@ 傳送了 Vitruvian 無法顯示的頁面（%2$@）。更新此擴充功能可能會解決問題。",
        panelTooLargeFormat: "超過 %@ 的大小上限",
        panelNotWellFormedFormat: "%@ 格式不正確",
        chooseFolder: "選擇…")

    package static let zhHK = ExternalToolStrings(
        sectionTitle: "擴充功能與工具",
        sectionEmpty: "尚未加入擴充功能或工具。兩者都是獨立程式。擴充功能會在 Dynamic Island、「設定」或視窗中加入自己的頁面。工具為 Vitruvian 加入指令。",
        addButton: "從資料夾加入…",
        statusRunning: "執行中",
        statusStopped: "已停止運作",
        startAgain: "重新啟動",
        statusChanged: "加入後已變更。請更新後再使用。",
        commandsTitle: "指令",
        usesTitle: "它聲明會使用的功能",
        usesNote: "此列表由工具自行提供，並不限制工具能做的事。",
        useNotify: "顯示訊息並播放提示音",
        useOpen: "打開連結",
        useClipboardRead: "讀取剪貼板",
        useClipboardWrite: "寫入剪貼板",
        useKeystrokes: "在其他 App 中貼上並觸發選單指令",
        useProcesses: "結束其他程式",
        useStorage: "儲存它自己的設定",
        updateButton: "從資料夾更新…",
        refusalTitle: "無法加入此資料夾",
        refusalNoManifest: "其中沒有 vitruvian-tool.json 檔案，因此它不是工具。",
        refusalMistakeFormat: "它的 vitruvian-tool.json 檔案有錯誤。請告知工具的作者：%@",
        refusalNeedsNewerFormat: "它需要此版本的 Vitruvian 沒有的功能：%@",
        refusalProgramFormat: "它的程式 %@ 不存在，或者 macOS 無法執行它。",
        refusalQuarantined: "此資料夾是下載而來，macOS 已將其隔離。Vitruvian 不會替你解除隔離。如果你信任它，請在「終端機」中執行以下指令，然後重新加入：",
        refusalTooBigFormat: "資料夾太大。一個工具最多可包含 %1$@ 和 %2$@ 個檔案。",
        refusalNotAdded: "Vitruvian 無法拷貝該資料夾，或者它在你閱讀時發生了變更。未加入任何內容。",
        agreeTitleFormat: "將「%@」加入 Vitruvian？",
        agreeFromFormat: "來自 %@",
        agreeOwnWords: "名稱、發佈者和描述均由工具自行提供，Vitruvian 並未核實。",
        agreeHeadline: "此工具可以在這部 Mac 上做 Vitruvian 能做的任何事。",
        agreeDetail: "它是一個獨立的程式，可以讀取螢幕、控制其他 App、讀取你的檔案並使用網絡。Vitruvian 不會限制或檢查它的行為。僅在你信任其作者時才加入。",
        agreeAdd: "加入工具",
        updateTitleFormat: "更新「%@」？",
        updateVersionsFormat: "你目前的版本是 %1$@。此資料夾中的版本是 %2$@。",
        updateChanged: "自你同意以來，工具對自身的說明已經變更。請重新閱讀。",
        updateKeepsData: "工具已儲存的內容會保留。",
        updateConfirm: "更新工具",
        removeTitleFormat: "移除「%@」？",
        removeMessage: "Vitruvian 會刪除它自己的那份工具副本。你加入工具時所用的資料夾不會受影響。",
        removeKeepData: "移除並保留它儲存的內容",
        removeDeleteData: "移除並刪除它儲存的內容",
        removeKeptTitleFormat: "「%@」儲存的內容已保留",
        removeKeptMessage: "它的程式沒有停止，所以 Vitruvian 沒有刪除工具儲存的內容。這些內容在此資料夾中：",
        removeUndeletedTitleFormat: "「%@」的部分檔案無法刪除",
        removeUndeletedMessage: "工具已移除，但 Vitruvian 無法刪除它的全部檔案。剩下的內容在這裡：",
        stoppedFormat: "「%@」已停止運作",
        panelNotShown: "無法顯示此頁面。原因記錄在「設定」中此工具的記錄內。",
        showInIsland: "在 Dynamic Island 中顯示",
        catalogTitle: "Vitruvian 目錄",
        catalogEmpty: "目錄中仍未有擴充功能或工具。",
        installButton: "安裝",
        installedLabel: "已安裝",
        updateAvailable: "有可用的更新",
        updateNow: "更新",
        agreeCatalog: "來自 Vitruvian 目錄：VitruvianSoftware 收錄了此工具，而下載的檔案與收錄的完全相同。",
        catalogUnreachable: "Vitruvian 無法連接到目錄。請檢查網絡連線，然後再試一次。",
        catalogNotOurs: "此工具列表未經 VitruvianSoftware 簽署，因此 Vitruvian 不會使用它。",
        downloadMismatch: "下載的檔案與目錄中列出的不相符，因此未安裝任何內容。",
        downloadNotTheTool: "下載的檔案不是目錄所指的工具，因此未安裝任何內容。",
        installRefusedFormat: "未安裝「%@」",
        showStatusInIsland: "在收合的 Dynamic Island 上顯示其狀態",
        agreeShowsStatus: "它會在收合的 Dynamic Island 上顯示一個細小的狀態標記。",
        agreeShowsStatusAndWords: "它會在收合的 Dynamic Island 上顯示一個細小的狀態標記和幾個字。",
        markOK: "正常",
        markBusy: "進行中",
        markAttention: "需要留意",
        markFailure: "失敗",
        kindExtension: "擴充功能",
        kindTool: "工具",
        pageTitle: "擴充功能",
        installedTitle: "已安裝",
        catalogAllInstalled: "目錄中的項目都已安裝。",
        summaryNone: "仍未有擴充功能",
        summaryOne: "已安裝 1 個擴充功能",
        summaryCountFormat: "已安裝 %d 個擴充功能",
        summaryManage: "管理",
        summaryBrowse: "瀏覽",
        updateFromCatalog: "從目錄更新",
        updateMovesToCatalogFormat: "你是從資料夾 %@ 加入此工具的；今後它會來自 Vitruvian 目錄。",
        updateVersionsCatalogFormat: "你目前的版本是 %1$@。目錄中的版本是 %2$@。",
        sdkLine: "使用 Vitruvian SDK 製作你自己的擴充功能。",
        vitruvianSection: "Vitruvian",
        searchSettings: "搜尋設定",
        noSettingsMatchFormat: "沒有符合「%@」的設定",
        pageNotSearchable: "無法搜尋此頁面。",
        panelRefusedFormat: "%1$@ 傳送了 Vitruvian 無法顯示的頁面（%2$@）。更新此擴充功能或可解決問題。",
        panelTooLargeFormat: "超過 %@ 的大小上限",
        panelNotWellFormedFormat: "%@ 格式不正確",
        chooseFolder: "選擇…")
}

extension FeatureStrings {
    package static func externalTools(_ language: AppLanguage) -> ExternalToolStrings {
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
