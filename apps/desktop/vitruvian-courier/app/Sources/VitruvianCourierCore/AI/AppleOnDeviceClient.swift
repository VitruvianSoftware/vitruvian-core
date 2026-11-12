// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public struct AppleOnDeviceClient: ChatModelClient, Sendable {
    public static let modelName = "On-Device"

    private let availabilityOverride: (isAvailable: Bool, reason: String)?

    public init(availabilityOverride: (isAvailable: Bool, reason: String)? = nil) {
        self.availabilityOverride = availabilityOverride
    }

    public var availability: (isAvailable: Bool, reason: String) {
        if let availabilityOverride {
            return availabilityOverride
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return (true, "")
            case .unavailable(.deviceNotEligible):
                return (false, String(localized: "This Mac does not support Apple Intelligence."))
            case .unavailable(.appleIntelligenceNotEnabled):
                return (false, String(localized: "Turn on Apple Intelligence in System Settings."))
            case .unavailable(.modelNotReady):
                return (false, String(localized: "Apple Intelligence is still preparing its on-device model."))
            @unknown default:
                return (false, String(localized: "Apple Intelligence is not available on this Mac."))
            }
        }
        #endif
        return (false, String(localized: "Apple Intelligence requires macOS 26 or later on a supported Mac."))
    }

    public func listModels() async throws -> [String] {
        let status = availability
        guard status.isAvailable else {
            throw AIClientError.server(status: 0, message: status.reason)
        }
        return [Self.modelName]
    }

    public func complete(_ turns: [AIChatTurn], model _: String) async throws -> String {
        let status = availability
        guard status.isAvailable else {
            throw AIClientError.server(status: 0, message: status.reason)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let systemText = turns
                .filter { $0.role == .system }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            let userText = turns
                .filter { $0.role != .system }
                .map(\.text)
                .joined(separator: "\n\n")

            do {
                let session = systemText.isEmpty
                    ? LanguageModelSession()
                    : LanguageModelSession(instructions: systemText)
                let response = try await session.respond(to: userText)
                let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw AIClientError.badResponse
                }
                return trimmed
            } catch let error as AIClientError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw AIClientError.server(status: 0, message: error.localizedDescription)
            }
        }
        #endif
        throw AIClientError.server(status: 0, message: status.reason)
    }
}
