// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// Inline location card (`Location.tsx`).
///
/// Renders a completely offline coordinate grid and pin canvas with zero outbound tile or network requests on render,
/// displays the place name (if present) and formatted `lat, lon`, and offers three user-triggered actions:
/// **Open in Apple Maps**, **Open in Google Maps**, and **Copy Location**.
public struct LocationCardView: View {
    public let coordinate: GeoCoordinate
    public var onBubble: Bool
    public var onOpenURL: (URL) -> Void
    public var onCopyLocation: (String) -> Void

    @State private var copied = false

    public static let userVisibleStrings: [String] = [
        String(localized: "Shared Location"),
        String(localized: "Open in Apple Maps"),
        String(localized: "Open in Google Maps"),
        String(localized: "Copy Location"),
        String(localized: "Copied"),
    ]

    public init(
        coordinate: GeoCoordinate,
        onBubble: Bool = false,
        onOpenURL: @escaping (URL) -> Void = { url in
            _ = NSWorkspace.shared.open(url)
        },
        onCopyLocation: @escaping (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    ) {
        self.coordinate = coordinate
        self.onBubble = onBubble
        self.onOpenURL = onOpenURL
        self.onCopyLocation = onCopyLocation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            offlineCoordinateCanvas
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(onBubble ? Color.white : Color.red)
                    Text(coordinate.label ?? String(localized: "Shared Location"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(onBubble ? Color.white : Color.primary)
                        .lineLimit(2)
                }
                Text(coordinate.formattedCoordinates)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(onBubble ? Color.white.opacity(0.82) : Color.secondary)
            }
            .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        onOpenURL(coordinate.appleMapsURL)
                    } label: {
                        Label(String(localized: "Open in Apple Maps"), systemImage: "map")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        onOpenURL(coordinate.googleMapsURL)
                    } label: {
                        Label(String(localized: "Open in Google Maps"), systemImage: "globe")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    onCopyLocation(coordinate.copyText)
                    copied = true
                } label: {
                    Label(
                        copied ? String(localized: "Copied") : String(localized: "Copy Location"),
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(onBubble ? Color.black.opacity(0.18) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(onBubble ? Color.white.opacity(0.22) : Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String(
                localized: "\(coordinate.label ?? String(localized: "Shared Location")), \(coordinate.formattedCoordinates)"
            )
        )
    }

    private var offlineCoordinateCanvas: some View {
        ZStack(alignment: .bottomTrailing) {
            Canvas { context, size in
                let bgRect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(bgRect),
                    with: .color(Color.teal.opacity(onBubble ? 0.25 : 0.14))
                )

                // Draw offline latitude / longitude grid lines.
                let gridColor = Color.primary.opacity(onBubble ? 0.16 : 0.10)
                let step: CGFloat = 22
                var gridPath = Path()
                var x: CGFloat = step
                while x < size.width {
                    gridPath.move(to: CGPoint(x: x, y: 0))
                    gridPath.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = step
                while y < size.height {
                    gridPath.move(to: CGPoint(x: 0, y: y))
                    gridPath.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(gridPath, with: .color(gridColor), lineWidth: 0.75)

                // Draw crosshair axes through the center.
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                var axisPath = Path()
                axisPath.move(to: CGPoint(x: 0, y: center.y))
                axisPath.addLine(to: CGPoint(x: size.width, y: center.y))
                axisPath.move(to: CGPoint(x: center.x, y: 0))
                axisPath.addLine(to: CGPoint(x: center.x, y: size.height))
                context.stroke(
                    axisPath,
                    with: .color(Color.accentColor.opacity(0.32)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )

                // Draw accuracy ring around the coordinate pin.
                let ringRadius: CGFloat = 24
                let ringRect = CGRect(
                    x: center.x - ringRadius,
                    y: center.y - ringRadius,
                    width: ringRadius * 2,
                    height: ringRadius * 2
                )
                context.fill(Path(ellipseIn: ringRect), with: .color(Color.red.opacity(0.14)))
                context.stroke(Path(ellipseIn: ringRect), with: .color(Color.red.opacity(0.42)), lineWidth: 1.2)
            }
            .frame(height: 104)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white, .red)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            Text(coordinate.formattedCoordinates)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.ultraThinMaterial))
                .padding(6)
        }
        .frame(height: 104)
    }
}
