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

import HomeSpeakerCore
import SwiftUI

/// The selected speaker's volume: a mute button, a slider and the level.
///
/// The slider only sends when it is released -- dragging would otherwise
/// fire a command per pixel at Google -- and the level shown afterwards is
/// the one read back from the speaker, not the one asked for.
/// The control's state. An ObservableObject rather than `@State`: the
/// Command Line Tools toolchain has no SwiftUI macro plugin, so `@State`
/// stops `swift build` there (see SettingsViewModel.selectedTab).
@MainActor
final class SpeakerVolumeModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready(SpeakerVolume)
        case unavailable(String)
    }

    @Published var phase: Phase = .loading
    @Published var level: Double = 0
    @Published var busy = false
}

@MainActor
struct SpeakerVolumeControl: View {
    let target: SpeakerDevice
    let structureId: String

    @StateObject private var model = SpeakerVolumeModel()

    var body: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .loading:
                ProgressView().controlSize(.small)
                Text("Reading volume…").font(.caption).foregroundStyle(.secondary)
            case .unavailable(let why):
                Image(systemName: "speaker.slash").foregroundStyle(.secondary)
                Text(why).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .ready(let v):
                Button { Task { await toggleMute(v) } } label: {
                    Image(systemName: v.muted ? "speaker.slash.fill" : icon(for: Int(model.level)))
                        .frame(width: 18)
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                .accessibilityLabel(v.muted ? "Unmute \(target.name)" : "Mute \(target.name)")
                Slider(value: $model.level, in: 0...100, step: 1) { editing in
                    if !editing { Task { await commit() } }
                }
                .disabled(model.busy || v.muted)
                .accessibilityLabel("\(target.name) volume")
                Text(v.muted ? "muted" : "\(Int(model.level))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .task(id: target.id) { await load() }
    }

    private func icon(for percent: Int) -> String {
        switch percent {
        case 0: return "speaker.fill"
        case 1..<34: return "speaker.wave.1.fill"
        case 34..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private func load() async {
        model.phase = .loading
        await refresh()
    }

    private func refresh() async {
        do {
            let v = try await GoogleHomeClient.shared.volume(of: target, structureId: structureId)
            // An offline speaker reports the last level it had; that number
            // would look current, so it is not shown.
            guard v.online else { model.phase = .unavailable("\(target.name) is offline."); return }
            model.level = Double(v.percent)
            model.phase = .ready(v)
        } catch {
            model.phase = .unavailable(error.localizedDescription)
        }
    }

    private func commit() async {
        model.busy = true
        defer { model.busy = false }
        do {
            let v = try await GoogleHomeClient.shared.setVolumeConfirmed(Int(model.level), on: target, structureId: structureId)
            model.level = Double(v.percent)
            model.phase = .ready(v)
        } catch {
            model.phase = .unavailable(error.localizedDescription)
        }
    }

    private func toggleMute(_ v: SpeakerVolume) async {
        model.busy = true
        defer { model.busy = false }
        do {
            try await GoogleHomeClient.shared.setMuted(!v.muted, on: target, structureId: structureId)
        } catch {
            model.phase = .unavailable(error.localizedDescription)
            return
        }
        await refresh()
    }
}
