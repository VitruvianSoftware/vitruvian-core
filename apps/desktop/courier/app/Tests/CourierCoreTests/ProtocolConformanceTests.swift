// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Holds Protocol.swift to apps/desktop/courier/protocol: protocol.json is the definition, and the engine's Go
/// tests check the same examples against it, so neither side can drift from the other.
///
/// Under Bazel the files are the test's `data` (runfiles); under SwiftPM scripts/test.sh sets COURIER_PROTOCOL_DIR.
final class ProtocolConformanceTests: XCTestCase {
    private var spec: [String: Any] = [:]
    private var examples: [(name: String, json: [String: Any])] = []

    override func setUpWithError() throws {
        let dir = try XCTUnwrap(Self.protocolDirectory(), "protocol.json not found: run under Bazel, or set COURIER_PROTOCOL_DIR (scripts/test.sh does)")
        let specData = try Data(contentsOf: dir.appendingPathComponent("protocol.json"))
        spec = try XCTUnwrap(JSONSerialization.jsonObject(with: specData) as? [String: Any])
        let exampleDir = dir.appendingPathComponent("examples")
        let names = try FileManager.default.contentsOfDirectory(atPath: exampleDir.path)
            .filter { $0.hasSuffix(".json") }.sorted()
        for name in names {
            let data = try Data(contentsOf: exampleDir.appendingPathComponent(name))
            examples.append((name, try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], name)))
        }
        // A loop over nothing would pass without checking anything.
        XCTAssertGreaterThan(examples.count, 30, "the examples are missing")
    }

    static func protocolDirectory() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let dir = environment["COURIER_PROTOCOL_DIR"] { candidates.append(dir) }
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/apps/desktop/courier/protocol")
            }
        }
        return candidates.map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("protocol.json").path) }
    }

    private var specTypes: [String: [String: Any]] { spec["types"] as? [String: [String: Any]] ?? [:] }
    private var specMethods: [String: [String: Any]] { spec["methods"] as? [String: [String: Any]] ?? [:] }
    private var specErrors: [[String: Any]] {
        (spec["errors"] as? [String: Any])?["codes"] as? [[String: Any]] ?? []
    }

    private func swiftType(named name: String) -> (any ProtocolType.Type)? {
        ProtocolMethods.types.first { $0.protocolName == name }
    }

    // MARK: - The definition

    func testProtocolNumberAndFrameLimitMatch() {
        XCTAssertEqual(spec["protocol"] as? Int, CourierProtocol.version)
        XCTAssertEqual((spec["transport"] as? [String: Any])?["max_frame_bytes"] as? Int, CourierProtocol.maxFrameBytes)
    }

    func testEveryTypeIsNamedAndHasExactlyItsFields() {
        XCTAssertEqual(Set(ProtocolMethods.types.map { $0.protocolName }), Set(specTypes.keys),
                       "Swift's types must be named exactly as protocol.json's")
        for (name, definition) in specTypes {
            guard let type = swiftType(named: name) else { continue }
            let fields = (definition["fields"] as? [String: Any] ?? [:]).keys
            XCTAssertEqual(Set(type.fieldNames), Set(fields), "\(name)'s fields")
            XCTAssertEqual(type.fieldNames.count, Set(type.fieldNames).count, "\(name) names a field twice")
        }
    }

    func testEveryValuesListMatches() {
        var listed: [String: [String]] = [:]
        for (name, definition) in specTypes {
            for (field, spec) in definition["fields"] as? [String: [String: Any]] ?? [:] {
                if let values = spec["values"] as? [String] { listed["\(name).\(field)"] = values }
            }
        }
        XCTAssertEqual(ProtocolMethods.values, listed)
    }

    func testEveryMethodHasItsParamsAndResult() {
        XCTAssertEqual(Set(ProtocolMethods.all.keys), Set(specMethods.keys))
        for (method, definition) in specMethods {
            guard let types = ProtocolMethods.all[method] else { continue }
            XCTAssertEqual(types.params.protocolName, definition["params"] as? String, "\(method)'s params")
            XCTAssertEqual(types.result.protocolName, definition["result"] as? String, "\(method)'s result")
        }
        let notifications = spec["notifications"] as? [String: [String: Any]] ?? [:]
        XCTAssertEqual(Array(notifications.keys), [ProtocolMethods.changedNotification])
        XCTAssertEqual(notifications[ProtocolMethods.changedNotification]?["params"] as? String, Changed.protocolName)
    }

    func testEveryErrorCodeIsKnown() {
        let listed = specErrors.map { "\($0["code"] as? Int ?? 0) \($0["name"] as? String ?? "")" }
        let known = RPCErrorCode.known.map { "\($0.number) \($0.name)" }
        XCTAssertEqual(known, listed)
        for entry in RPCErrorCode.known {
            XCTAssertEqual(RPCErrorCode(number: entry.number), entry.code)
            XCTAssertEqual(entry.code.number, entry.number)
        }
        XCTAssertEqual(RPCErrorCode(number: -32099), .other(-32099))
    }

    // MARK: - The examples

    func testEveryExampleDecodesAndReencodes() throws {
        var checked = 0
        for (name, example) in examples {
            if let request = example["request"] as? [String: Any] {
                let method = try XCTUnwrap(request["method"] as? String, name)
                guard let types = ProtocolMethods.all[method] else {
                    // Only an example of an unknown method may name one, and its answer is method_not_found.
                    let error = (example["response"] as? [String: Any])?["error"] as? [String: Any]
                    XCTAssertEqual(error?["code"] as? Int, -32601, "\(name): unknown method \(method)")
                    checked += 2
                    continue
                }
                if let params = request["params"] {
                    try assertRoundTrip(params, as: types.params, in: "\(name) params")
                    checked += 1
                }
                let response = try XCTUnwrap(example["response"] as? [String: Any], name)
                if let result = response["result"] {
                    try assertRoundTrip(result, as: types.result, in: "\(name) result")
                    checked += 1
                }
                if let error = response["error"] as? [String: Any] {
                    try assertError(error, method: method, in: name)
                    checked += 1
                }
            } else if let notification = example["notification"] as? [String: Any] {
                XCTAssertEqual(notification["method"] as? String, ProtocolMethods.changedNotification, name)
                let params = try XCTUnwrap(notification["params"], name)
                try assertRoundTrip(params, as: Changed.self, in: "\(name) params")
                let changed = try JSONDecoder().decode(Changed.self, from: JSONSerialization.data(withJSONObject: params))
                if changed.kind == .resync {
                    XCTAssertEqual(Change(changed), .resync, name)
                } else {
                    XCTAssertNotEqual(Change(changed), .resync, "\(name) reads as a resync")
                }
                checked += 1
            } else {
                XCTFail("\(name) is neither a request nor a notification")
            }
        }
        XCTAssertGreaterThan(checked, examples.count)
    }

    private func assertRoundTrip(_ value: Any, as type: any ProtocolType.Type, in context: String) throws {
        let original = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        let reencoded: Data
        do {
            reencoded = try type.roundTrip(original)
        } catch {
            XCTFail("\(context) does not decode as \(type.protocolName): \(error)")
            return
        }
        let again = try JSONSerialization.jsonObject(with: reencoded, options: [.fragmentsAllowed])
        // Every key the example has must come back, with its value, and nothing else: a key Swift does not know
        // would be dropped here, and a T|null written as absent would be missing.
        XCTAssertEqual(again as? NSObject, value as? NSObject,
                       "\(context): \(type.protocolName) re-encodes as \(String(decoding: reencoded, as: UTF8.self))")
    }

    private func assertError(_ error: [String: Any], method: String, in context: String) throws {
        let number = try XCTUnwrap(error["code"] as? Int, context)
        let entry = try XCTUnwrap(specErrors.first { $0["code"] as? Int == number }, "\(context): code \(number)")
        XCTAssertEqual(error["message"] as? String, entry["message"] as? String, context)
        if case .other = RPCErrorCode(number: number) { XCTFail("\(context): \(number) is not known to Swift") }
        // A method may give its own codes, and every method the general ones.
        let general = [-32700, -32600, -32601, -32602, -32603, -32002] + (method == "hello" ? [-32001] : [])
        let own = specMethods[method]?["errors"] as? [Int] ?? []
        XCTAssertTrue((general + own).contains(number), "\(context): \(method) may not give \(number)")
        if let dataType = entry["data"] as? String {
            let data = try XCTUnwrap(error["data"], "\(context): \(number) carries \(dataType)")
            try assertRoundTrip(data, as: try XCTUnwrap(swiftType(named: dataType)), in: "\(context) data")
        }
    }
}
