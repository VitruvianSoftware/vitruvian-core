// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// What the camera page starts, stops and watches. The app's is
/// `CameraPreviewService.shared`.
@MainActor
package protocol NotchEmbeddedCamera: ObservableObject {
    var isEmbeddedPresented: Bool { get }
    func showEmbedded()
    func hideEmbedded()
}

extension CameraPreviewService: NotchEmbeddedCamera {}

/// The camera page: a card that starts the camera, then its preview over the
/// whole page; its stop button sits in the island's top row
/// (`NotchCameraStopButton`). Leaving the page stops the camera.
package struct NotchCameraView<Camera: NotchEmbeddedCamera, Preview: View>: View {
    package let size: CGSize
    @ObservedObject private var service: Camera
    /// The live image at a size.
    private let preview: (_ size: CGSize) -> Preview
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    package init(size: CGSize, camera: Camera,
                 preview: @escaping (_ size: CGSize) -> Preview) {
        self.size = size
        _service = ObservedObject(wrappedValue: camera)
        self.preview = preview
    }

    package var body: some View {
        Group {
            if service.isEmbeddedPresented {
                // The preview takes the whole page; its camera picker and stop
                // button sit in the island's top row, clear of the image.
                preview(NotchLayout.cameraPreviewSize(in: size))
            } else {
                HStack(spacing: 16) {
                    Image(systemName: "web.camera").font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(text.cameraHint).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(text.startCamera) { service.showEmbedded() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { service.hideEmbedded() }
    }
}

extension NotchCameraView where Camera == CameraPreviewService, Preview == CameraPreviewView {
    /// The app's camera page: the shared camera and its live preview. Its
    /// camera picker and stop button sit in the island's top row.
    package init(size: CGSize) {
        self.init(size: size, camera: .shared) { CameraPreviewView(size: $0, showsCameraMenu: false) }
    }
}

/// The camera the mirror shows, in the island's top row while it runs with
/// more than one camera around: the current one's name, cut short beside the
/// camera, over a native menu of them all.
package struct NotchCameraChooser: View {
    @ObservedObject private var service = CameraPreviewService.shared
    @ObservedObject private var l10n = L10n.shared
    private var strings: CameraPreviewFeatureStrings { FeatureStrings.cameraPreview(l10n.language) }

    private var current: String {
        service.devices.first { $0.uniqueID == service.selectedDeviceID }?.localizedName ?? strings.cameraMenuLabel
    }

    package var body: some View {
        if service.isEmbeddedPresented, service.state == .running, service.session != nil, service.devices.count > 1 {
            NotchMenuButton(title: strings.cameraMenuLabel, items: service.devices.map { device in
                NotchMenuItem(title: device.localizedName, checked: device.uniqueID == service.selectedDeviceID) {
                    service.selectCamera(device)
                }
            }, cornerRadius: 9) {
                NotchBandMenuLabel(title: current)
            }
            .help(current)
            .accessibilityValue(current)
        }
    }
}

/// Stops the mirror from the island's top row: a glyph beside the camera,
/// where a word may not fit, and the word itself across a full row.
package struct NotchCameraStopButton<Camera: NotchEmbeddedCamera>: View {
    @ObservedObject private var service: Camera
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchBand) private var band

    package init(camera: Camera) {
        _service = ObservedObject(wrappedValue: camera)
    }

    package var body: some View {
        if service.isEmbeddedPresented {
            let title = FeatureStrings.notchActivities(l10n.language).stopCamera
            if band.besideCamera {
                NotchIconButton(symbol: "video.slash", title: title, action: service.hideEmbedded)
            } else {
                NotchPillButton(title: title, prominent: true, action: service.hideEmbedded)
            }
        }
    }
}

extension NotchCameraStopButton where Camera == CameraPreviewService {
    /// The app's stop button, for the shared camera.
    package init() { self.init(camera: .shared) }
}
