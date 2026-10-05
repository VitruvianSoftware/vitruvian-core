// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

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
/// whole page with a stop button. Leaving the page stops the camera.
package struct NotchCameraView<Camera: NotchEmbeddedCamera, Preview: View>: View {
    package let size: CGSize
    @ObservedObject private var service: Camera
    /// The live image at a size, with the button that stops it.
    private let preview: (_ size: CGSize, _ stop: @escaping () -> Void) -> Preview
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    package init(size: CGSize, camera: Camera,
                 preview: @escaping (_ size: CGSize, _ stop: @escaping () -> Void) -> Preview) {
        self.size = size
        _service = ObservedObject(wrappedValue: camera)
        self.preview = preview
    }

    package var body: some View {
        Group {
            if service.isEmbeddedPresented {
                // The preview takes the whole page, with its stop button over the image.
                preview(NotchLayout.cameraPreviewSize(in: size)) { service.hideEmbedded() }
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
    /// The app's camera page: the shared camera and its live preview.
    package init(size: CGSize) {
        self.init(size: size, camera: .shared) { size, stop in
            CameraPreviewView(size: size, showsCameraMenu: true, onStop: stop)
        }
    }
}
