// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Inline voice-note and audio player (`Audio.tsx` / `MSC1767Audio`) with interactive waveform bar scrubbing,
/// elapsed/duration readout, `0.5× / 1× / 1.5× / 2×` speed pill, and an unplayed indicator dot.
struct VoiceNoteView: View {
    let message: TimelineMessage
    let chatTitle: String
    @ObservedObject var audioPlayer: AudioPlayerModel
    var queueInRoom: [AudioPlayerModel.Track] = []

    private static let defaultWaveform: [Int] = [
        18, 32, 48, 70, 54, 36, 62, 88, 74, 46, 28, 58,
        82, 66, 40, 24, 52, 76, 48, 30, 42, 64, 38, 20,
    ]
    private static let barCount = 28

    static var userVisibleStrings: [String] {
        [
            String(localized: "Play voice message"),
            String(localized: "Pause voice message"),
            String(localized: "Playback speed"),
            String(localized: "Unplayed voice message"),
            String(localized: "Voice message"),
        ] + AudioPlayerModel.Speed.allCases.map(\.label)
    }

    private var isCurrentTrack: Bool {
        audioPlayer.currentTrack?.eventID == message.id
    }

    private var isPlayingThisTrack: Bool {
        isCurrentTrack && audioPlayer.isPlaying
    }

    private var activeProgress: Double {
        isCurrentTrack ? audioPlayer.progress : 0
    }

    private var totalDurationMS: Int {
        if isCurrentTrack, let track = audioPlayer.currentTrack, track.durationMS > 0 {
            return track.durationMS
        }
        return max(message.durationMS ?? 0, 0)
    }

    private var displayedElapsedMS: Int {
        isCurrentTrack ? audioPlayer.elapsedMS : 0
    }

    private var showsUnplayedDot: Bool {
        message.kind == .voiceNote && !message.played && !message.mine && !isCurrentTrack
    }

    private var normalizedBars: [Double] {
        Self.normalizeWaveform(message.waveform.isEmpty ? Self.defaultWaveform : message.waveform, count: Self.barCount)
    }

    private var trackForMessage: AudioPlayerModel.Track {
        let sender = message.mine
            ? String(localized: "You")
            : (message.senderName.isEmpty ? chatTitle : message.senderName)
        return AudioPlayerModel.Track(
            eventID: message.id,
            roomID: message.roomID,
            mediaPath: message.mediaPath,
            senderName: sender,
            chatTitle: chatTitle,
            durationMS: max(message.durationMS ?? 0, 0),
            waveform: message.waveform,
            isVoiceNote: message.kind == .voiceNote
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            playPauseButton

            VStack(alignment: .leading, spacing: 5) {
                waveformScrubber
                    .frame(height: 24)

                HStack(spacing: 6) {
                    Text(timeLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(secondaryColor)

                    if showsUnplayedDot {
                        Circle()
                            .fill(unplayedDotColor)
                            .frame(width: 6, height: 6)
                            .help(String(localized: "Unplayed voice message"))
                            .accessibilityLabel(String(localized: "Unplayed voice message"))
                    }

                    Spacer(minLength: 4)

                    speedPillButton
                }
            }
        }
        .padding(.vertical, 3)
        .frame(minWidth: 230, maxWidth: 310, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var playPauseButton: some View {
        Button {
            let track = trackForMessage
            let queue = queueInRoom.isEmpty ? [track] : queueInRoom
            audioPlayer.playOrPause(track, queueInRoom: queue)
        } label: {
            ZStack {
                Circle()
                    .fill(buttonFillColor)
                    .frame(width: 32, height: 32)
                Image(systemName: isPlayingThisTrack ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(buttonIconColor)
                    .offset(x: isPlayingThisTrack ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
        .help(isPlayingThisTrack ? String(localized: "Pause voice message") : String(localized: "Play voice message"))
        .accessibilityLabel(
            isPlayingThisTrack ? String(localized: "Pause voice message") : String(localized: "Play voice message")
        )
    }

    private var waveformScrubber: some View {
        GeometryReader { geo in
            let bars = normalizedBars
            let count = max(bars.count, 1)
            let spacing: CGFloat = 2.5
            let totalSpacing = spacing * CGFloat(max(count - 1, 0))
            let barWidth = max((geo.size.width - totalSpacing) / CGFloat(count), 2)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, amplitude in
                    let barPosition = Double(index + 1) / Double(count)
                    let isPlayedBar = isCurrentTrack && barPosition <= activeProgress + 0.001
                    Capsule(style: .continuous)
                        .fill(isPlayedBar ? activeBarColor : inactiveBarColor)
                        .frame(
                            width: barWidth,
                            height: max(CGFloat(amplitude) * geo.size.height, 4)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard geo.size.width > 0 else { return }
                        let fraction = min(max(Double(value.location.x / geo.size.width), 0), 1)
                        if !isCurrentTrack {
                            let track = trackForMessage
                            let queue = queueInRoom.isEmpty ? [track] : queueInRoom
                            audioPlayer.playOrPause(track, queueInRoom: queue)
                        }
                        audioPlayer.seek(to: fraction)
                    }
            )
        }
    }

    private var speedPillButton: some View {
        Button {
            audioPlayer.cycleSpeed()
        } label: {
            Text(audioPlayer.speed.label)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(pillTextColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(pillBackgroundColor)
                )
        }
        .buttonStyle(.plain)
        .help(String(localized: "Playback speed"))
        .accessibilityLabel(String(localized: "Playback speed \(audioPlayer.speed.label)"))
    }

    private var timeLabel: String {
        if isCurrentTrack {
            return "\(Self.formatMillis(displayedElapsedMS)) / \(Self.formatMillis(totalDurationMS))"
        }
        return Self.formatMillis(totalDurationMS)
    }

    // MARK: - Styling

    private var buttonFillColor: Color {
        message.mine ? .white.opacity(0.22) : Color.accentColor
    }

    private var buttonIconColor: Color {
        .white
    }

    private var activeBarColor: Color {
        message.mine ? .white : Color.accentColor
    }

    private var inactiveBarColor: Color {
        if message.mine {
            return .white.opacity(message.played ? 0.38 : 0.52)
        }
        return Color.primary.opacity(message.played ? 0.25 : 0.38)
    }

    private var secondaryColor: Color {
        message.mine ? .white.opacity(0.82) : .secondary
    }

    private var unplayedDotColor: Color {
        message.mine ? .white : Color.accentColor
    }

    private var pillBackgroundColor: Color {
        message.mine ? .white.opacity(0.2) : Color.primary.opacity(0.09)
    }

    private var pillTextColor: Color {
        message.mine ? .white : .primary
    }

    // MARK: - Helpers

    static func formatMillis(_ millis: Int) -> String {
        let totalSeconds = max(millis / 1000, 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func normalizeWaveform(_ raw: [Int], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let source = raw.isEmpty ? defaultWaveform : raw
        let maxVal = Double(max(source.max() ?? 1, 1))
        return (0 ..< count).map { idx in
            let pos = Double(idx) / Double(max(count - 1, 1)) * Double(max(source.count - 1, 0))
            let lower = Int(pos.rounded(.down))
            let upper = min(lower + 1, source.count - 1)
            let weight = pos - Double(lower)
            let sample = Double(source[lower]) * (1 - weight) + Double(source[upper]) * weight
            let normalized = min(max(sample / maxVal, 0.16), 1.0)
            return normalized
        }
    }
}
