// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// A faithful, live miniature of the menu bar corner. It uses the same compact
/// lines the real status item renders, so choices in Settings have an immediate
/// visual cost before they occupy the actual menu bar.
package struct MenuBarMetricsPreview: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @AppStorage(Preferences.menuBarCPU) private var cpu: Bool
    @AppStorage(Preferences.menuBarGPU) private var gpu: Bool
    @AppStorage(Preferences.menuBarMemory) private var memory: Bool
    @AppStorage(Preferences.menuBarCPUTemperature) private var cpuTemperature: Bool
    @AppStorage(Preferences.menuBarGPUTemperature) private var gpuTemperature: Bool
    @AppStorage(Preferences.menuBarBatteryTemperature) private var batteryTemperature: Bool
    @AppStorage(Preferences.menuBarNetwork) private var network: Bool
    @AppStorage(Preferences.menuBarDiskUsage) private var diskUsage: Bool
    @AppStorage(DiskMenuBarStyle.defaultsKey) private var diskStyle = DiskMenuBarStyle.percent
    @AppStorage(Preferences.menuBarDiskActivity) private var diskActivity: Bool
    @AppStorage(Preferences.menuBarBattery) private var battery: Bool
    @AppStorage(Preferences.menuBarBatteryTime) private var batteryTime: Bool
    @AppStorage(Preferences.menuBarPeripheralBattery) private var peripheralBattery: Bool
    @AppStorage(Preferences.menuBarPower) private var power: Bool
    @AppStorage(Preferences.menuBarFanSpeed) private var fanSpeed: Bool
    @AppStorage(Preferences.menuBarConnectedDevices) private var connectedDevices: Bool
    @AppStorage(Preferences.menuBarMetricOrder) private var metricOrder: String
    @AppStorage(Preferences.menuBarCombineTemperatures) private var combineTemperatures: Bool
    @AppStorage(Preferences.menuBarMetricAppearance) private var metricAppearance: String
    @AppStorage(Preferences.menuBarUsageBarNormalColor) private var usageBarNormalColor: String
    @AppStorage(Preferences.menuBarUsageBarElevatedColor) private var usageBarElevatedColor: String
    @AppStorage(Preferences.menuBarUsageBarCriticalColor) private var usageBarCriticalColor: String
    @AppStorage(Preferences.menuBarUsageBarMediumThreshold) private var usageBarMediumThreshold: Int
    @AppStorage(Preferences.menuBarUsageBarHighThreshold) private var usageBarHighThreshold: Int
    @AppStorage(Preferences.menuBarLabelStyle) private var labelStyle: String
    @AppStorage(Preferences.menuBarNetworkUploadFirst) private var networkUploadFirst: Bool
    @AppStorage(Preferences.menuBarMemoryStyle) private var memoryStyle: String
    @AppStorage(Preferences.temperatureUnit) private var temperatureUnit: String
    @AppStorage(Preferences.menuBarMetricSpacing) private var metricSpacing: String
    @AppStorage(Preferences.menuBarHideIconWithMetrics) private var hideIconWithMetrics: Bool
    @AppStorage(Preferences.menuBarSeparateMetrics) private var separateMetrics: Bool
    @ObservedObject private var l10n = L10n.shared

    package var body: some View {
        let _ = metricOrder
        let _ = combineTemperatures
        let _ = metricAppearance
        let _ = usageBarNormalColor
        let _ = usageBarElevatedColor
        let _ = usageBarCriticalColor
        let _ = usageBarMediumThreshold
        let _ = usageBarHighThreshold
        let _ = labelStyle
        let _ = networkUploadFirst
        let _ = memoryStyle
        let _ = diskStyle
        let _ = temperatureUnit
        let _ = metricSpacing
        let metrics = activeMetrics
        let lines = separateMetrics ? [] : MenuBarRenderer.lines(for: monitor.snapshot, metrics: metrics)
        // Separate items are their own status items, which macOS seats to
        // the left of the one that was there first.
        let items = separateMetrics
            ? MenuBarRenderer.metricStatusGroups(for: metrics, strings: l10n.s)
                .map { MenuBarRenderer.lines(for: monitor.snapshot, metrics: $0.metrics) }
                .filter { !$0.isEmpty }
            : []
        // The steady state of the hide option: a pending update or a muted
        // microphone brings the real icon back, and the preview does not
        // pretend to know about either.
        let iconHidden = hideIconWithMetrics && (!lines.isEmpty || !items.isEmpty)

        HStack(spacing: 12) {
            Spacer()
            Image(systemName: "wifi")
                .foregroundStyle(.white.opacity(0.5))
            if PowerSampler.hasInternalBattery {
                Image(systemName: "battery.75")
                    .foregroundStyle(.white.opacity(0.5))
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                linesView(item)
            }
            if !iconHidden || !lines.isEmpty {
                HStack(spacing: 5) {
                    if !iconHidden {
                        glyph
                            .frame(width: BlackHoleGlyph.pointSize.width,
                                   height: BlackHoleGlyph.pointSize.height)
                    }
                    if !lines.isEmpty {
                        linesView(lines)
                    }
                }
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
    }

    private func linesView(_ lines: [[MenuBarSegment]]) -> some View {
        let stacked = lines.count > 1
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 0) {
                    ForEach(Array(line.enumerated()), id: \.offset) { _, segment in
                        segmentView(segment, stacked: stacked)
                    }
                }
                .frame(height: MenuBarRenderer.statusLineHeight(stacked: stacked))
            }
        }
    }

    private var activeMetrics: [MenuBarMetric] {
        let _ = cpu
        let _ = gpu
        let _ = memory
        let _ = cpuTemperature
        let _ = gpuTemperature
        let _ = batteryTemperature
        let _ = network
        let _ = diskUsage
        let _ = diskActivity
        let _ = battery
        let _ = batteryTime
        let _ = peripheralBattery
        let _ = power
        let _ = fanSpeed
        let _ = connectedDevices
        return MenuBarMetric.enabled(in: .standard)
    }

    @ViewBuilder
    private func segmentView(_ segment: MenuBarSegment, stacked: Bool) -> some View {
        switch segment {
        case let .text(string):
            Text(string)
                .font(.system(size: MenuBarRenderer.statusFontSize(stacked: stacked),
                              weight: stacked ? .semibold : .medium,
                              design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: stacked ? 8.8 : 10.8, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: stacked ? 9.2 : 11.4, height: stacked ? 9.2 : 11.4)
        case let .largeSymbol(name):
            Image(systemName: name)
                .font(.system(size: 13.6, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 14.2, height: 14.2)
        case let .metricBlock(label, value, minimumValue, style, pressure):
            metricBlock(label: label,
                        value: value,
                        minimumValue: minimumValue,
                        style: style,
                        pressure: pressure)
        case let .usageBarBlock(label, fraction, style, pressure):
            usageBarBlock(label: label,
                          fraction: fraction,
                          style: style,
                          pressure: pressure)
        case let .networkBlock(down, up, style):
            let rows = networkUploadFirst ? [("↑", up), ("↓", down)] : [("↓", down), ("↑", up)]
            VStack(alignment: .trailing, spacing: -0.6) {
                Text(rows[0].0 + rows[0].1)
                    .lineLimit(1)
                Text(rows[1].0 + rows[1].1)
                    .lineLimit(1)
            }
            .font(.system(size: MenuBarRenderer.networkBlockFontSize(style: style),
                          weight: .semibold,
                          design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: MenuBarRenderer.rateBlockWidth(style: style),
                   height: style == .readable ? 22 : 20,
                   alignment: .center)
        case let .diskActivityBlock(read, write, style):
            VStack(alignment: .trailing, spacing: -0.6) {
                Text("R\(read)")
                    .lineLimit(1)
                Text("W\(write)")
                    .lineLimit(1)
            }
            .font(.system(size: MenuBarRenderer.networkBlockFontSize(style: style),
                          weight: .semibold,
                          design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: MenuBarRenderer.rateBlockWidth(style: style),
                   height: style == .readable ? 22 : 20,
                   alignment: .center)
        case let .batteryBlock(percent, isCharging, style):
            HStack(spacing: style == .readable ? 5 : 4) {
                Image(systemName: MenuBarRenderer.batterySymbol(for: percent, isCharging: isCharging))
                    .font(.system(size: style == .readable ? 17 : 15.5, weight: .regular))
                Text("\(max(0, min(100, percent)))%")
                    .font(.system(size: style == .readable ? 13 : 12,
                                  weight: .semibold,
                                  design: .monospaced))
                    .frame(minWidth: style == .readable ? 33 : 30, alignment: .leading)
            }
            .foregroundStyle(.white)
            .fixedSize(horizontal: true, vertical: true)
        case let .dot(pressure):
            Circle()
                .fill(dotColor(pressure))
                .frame(width: stacked ? 5.5 : 7.5, height: stacked ? 5.5 : 7.5)
        case .separator:
            Text("│")
                .font(.system(size: MenuBarRenderer.statusFontSize(stacked: stacked),
                              weight: .medium,
                              design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.horizontal, 5)
        }
    }

    private func metricBlock(label: String,
                             value: String,
                             minimumValue: String,
                             style: MenuBarBlockStyle,
                             pressure: MemoryPressure?) -> some View {
        VStack(spacing: -1) {
            Text(label)
                .font(.system(size: style == .readable ? 7.2 : 6.6, weight: .medium))
            HStack(spacing: pressure == nil || value.isEmpty ? 0 : 4) {
                if let pressure {
                    Circle()
                        .fill(dotColor(pressure))
                        .frame(width: style == .readable ? 5.2 : 4.8,
                               height: style == .readable ? 5.2 : 4.8)
                }
                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: style == .readable ? 13 : 12,
                                      weight: .semibold,
                                      design: .monospaced))
                        .frame(minWidth: metricValueMinWidth(minimumValue: minimumValue, style: style),
                               alignment: .center)
                }
            }
        }
        .foregroundStyle(.white)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func usageBarBlock(label: String,
                               fraction: Double?,
                               style: MenuBarBlockStyle,
                               pressure: MemoryPressure?) -> some View {
        let size = MenuBarRenderer.usageBarSize(style: style, showsPressure: pressure != nil)
        let barWidth: CGFloat = style == .readable ? 10 : 9
        let barHeight: CGFloat = style == .readable ? 20 : 18
        let innerHeight = barHeight - 4.2
        let clamped = fraction.map(MenuBarUsageBarSupport.clampedFraction)

        return HStack(spacing: 2) {
            VStack(spacing: -1.8) {
                ForEach(Array(label.prefix(3).enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(.system(size: style == .readable ? 6.5 : 6.1,
                                      weight: .semibold))
                        .frame(height: (size.height - 2) / 3)
                }
            }
            .frame(width: style == .readable ? 6.5 : 6)

            if let pressure {
                Circle()
                    .fill(dotColor(pressure))
                    .frame(width: style == .readable ? 4.8 : 4.4,
                           height: style == .readable ? 4.8 : 4.4)
                    .padding(.trailing, 0.2)
            }

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                    .stroke(Color.white, lineWidth: 1.15)
                if let clamped, clamped > 0 {
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .fill(usageBarColor(for: clamped))
                        .frame(width: barWidth - 4.2,
                               height: max(1, innerHeight * clamped))
                        .padding(.bottom, 2.1)
                } else if clamped == nil {
                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: barWidth - 4.8, height: 1)
                }
            }
            .frame(width: barWidth, height: barHeight)
        }
        .foregroundStyle(.white)
        .frame(width: size.width, height: size.height)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func usageBarColor(for fraction: Double) -> Color {
        let level = MenuBarUsageBarSupport.currentLevel(for: fraction)
        let hex = MenuBarUsageBarSupport.currentColorHex(for: level)
        let rgb = MenuBarUsageBarSupport.rgb(for: hex,
                                             fallback: MenuBarUsageBarSupport.defaultNormalColor)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func metricValueMinWidth(minimumValue: String, style: MenuBarBlockStyle) -> CGFloat {
        switch minimumValue {
        case "100% 999°":
            return style == .readable ? 62 : 56
        case "100%", "999°":
            return style == .readable ? 33 : 30
        case "99W":
            return style == .readable ? 28 : 25
        case "100%+9":
            return style == .readable ? 50 : 46
        default:
            return 0
        }
    }

    private func dotColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .gray
        }
    }

    private var glyph: some View {
        Group {
            if let image = BlackHoleGlyph.image(active: true) {
                Image(nsImage: image).renderingMode(.template)
            } else {
                Image(systemName: "circle.fill")
            }
        }
        .foregroundStyle(.white)
    }
}
