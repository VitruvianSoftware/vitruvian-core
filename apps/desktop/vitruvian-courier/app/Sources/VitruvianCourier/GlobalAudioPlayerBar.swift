// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Persistent floating audio bar (`GlobalAudioPlayer.tsx`) shown at the top of `MainWindow` when the user switches
/// away from the chat where a voice note or audio clip is playing.
struct GlobalAudioPlayerBar: View {
    @ObservedObject var audioPlayer: AudioPlayerModel
    var onJumpToMessage: (String, String) -> Void

    static var userVisibleStrings: [String] {
        [
            String(localized: "Play voice message"),
            String(localized: "Pause voice message"),
            String(localized: "Playback speed"),
            String(localized: "Jump to Message"),
            String(localized: "Close audio player"),
            String(localized: "Voice message"),
        ] + AudioPlayerModel.Speed.allCases.map(\.label)
    }

    var body: some View {
        if let track = audioPlayer.currentTrack {
            HStack(spacing: 10) {
                Button {
                    audioPlayer.playOrPause(track)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 26, height: 26)
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: audioPlayer.isPlaying ? 0 : 0.5)
                    }
                }
                .buttonStyle(.plain)
                .help(
                    audioPlayer.isPlaying
                        ? String(localized: "Pause voice message")
                        : String(localized: "Play voice message")
                )
                .accessibilityLabel(
                    audioPlayer.isPlaying
                        ? String(localized: "Pause voice message")
                        : String(localized: "Play voice message")
                )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(headerTitle(for: track))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }

                    Text("\(VoiceNoteView.formatMillis(audioPlayer.elapsedMS)) / \(VoiceNoteView.formatMillis(track.durationMS))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

                scrubber(for: track)
                    .frame(minWidth: 120, maxWidth: .infinity)
                    .frame(height: 18)

                Button {
                    audioPlayer.cycleSpeed()
                } label: {
                    Text(audioPlayer.speed.label)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .help(String(localized: "Playback speed"))
                .accessibilityLabel(String(localized: "Playback speed \(audioPlayer.speed.label)"))

                Button {
                    onJumpToMessage(track.roomID, track.eventID)
                } label: {
                    Label(String(localized: "Jump to Message"), systemImage: "arrow.turn.down.right")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Jump to Message"))

                Button {
                    audioPlayer.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Close audio player"))
                .accessibilityLabel(String(localized: "Close audio player"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) {
                Divider()
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func headerTitle(for track: AudioPlayerModel.Track) -> String {
        let sender = track.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let chat = track.chatTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sender.isEmpty, !chat.isEmpty, sender != chat {
            return "\(sender) · \(chat)"
        }
        if !sender.isEmpty {
            return sender
        }
        if !chat.isEmpty {
            return chat
        }
        return String(localized: "Voice message")
    }

    private func scrubber(for track: AudioPlayerModel.Track) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let filledWidth = width * CGFloat(min(max(audioPlayer.progress, 0), 1))
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 5)
                Capsule(style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: max(filledWidth, 4), height: 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(Double(value.location.x / width), 0), 1)
                        audioPlayer.seek(to: fraction)
                    }
            )
        }
    }
}
