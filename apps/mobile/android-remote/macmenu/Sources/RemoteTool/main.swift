// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// The Vitruvian Remote extension executable (`dev.vitruvian.remote`, `bin/tool`).

import Foundation
import RemoteMenuCore
import RemoteToolCore
import VitruvianToolKit
import VitruvianToolProtocol

let tool = Tool(version: RemoteVersion.current)
let controller = RemoteToolController.fromEnvironment()

let islandPanel = tool.panel(
    RemoteToolController.islandPanelID,
    onOpen: { app, _ in
        let tree = controller.islandPage()
        controller.syncClosedIslandStatus(to: app)
        return tree
    },
    onEvent: { app, _, event in
        controller.handleIslandEvent(event, app: app)
    }
)

let settingsPanel = tool.panel(
    RemoteToolController.settingsPanelID,
    onOpen: { app, _ in
        let tree = controller.settingsPage()
        controller.syncClosedIslandStatus(to: app)
        return tree
    },
    onEvent: { app, _, event in
        controller.handleSettingsEvent(event, app: app)
    }
)

for commandID in RemoteToolController.Command.all {
    tool.command(commandID) { app in
        try controller.runCommand(commandID, app: app)
    }
}

tool.onStart = { app in
    // The app's hello has been read: whether it draws sections is known.
    controller.offersSections = app.supports(.sections)
    controller.start()
    controller.syncClosedIslandStatus(to: app)
}

tool.every(seconds: 5) { app in
    let state = controller.reconcileProcessAndPoll()
    controller.syncClosedIslandStatus(to: app)
    if islandPanel.isOpen {
        _ = islandPanel.render(RemotePages.islandPage(state))
    }
    if settingsPanel.isOpen {
        _ = settingsPanel.render(RemotePages.settingsPage(state))
    }
}

let exitCode = tool.serve()
controller.stop()
exit(exitCode)
