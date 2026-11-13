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
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import Foundation

/// Pure form parser, validator and answer builder for `elicitation/create`,
/// ported from T3 Code's `elicitationForm.ts:1-223`.
public struct ACPElicitationForm: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case form
        case url(String)
    }

    fileprivate enum FieldRule: Equatable, Sendable {
        case text
        case number(integer: Bool)
        case boolean
        case choice(values: Set<String>)
        case multiChoice(values: Set<String>, minItems: Int, maxItems: Int)
    }

    public let mode: Mode
    public let question: AgentQuestion
    private let fieldOrder: [String]
    private let rules: [String: FieldRule]
    private let requiredFields: Set<String>

    /// Parses an `elicitation/create` request into an askable `ACPElicitationForm`,
    /// or returns `nil` when the schema or URL is unaskable (`elicitationForm.ts:179-209`).
    public static func parse(
        requestID: String,
        params: ACPElicitationCreateParams
    ) -> ACPElicitationForm? {
        let modeString = params.mode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "form"
        let trimmedTitle = nonEmptyTrimmed(params.title)

        if modeString == "url" {
            guard let rawURL = nonEmptyTrimmed(params.url),
                  let parsedURL = URL(string: rawURL),
                  let scheme = parsedURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }
            let question = AgentQuestion(
                requestID: requestID,
                title: trimmedTitle,
                message: params.message,
                url: rawURL,
                fields: []
            )
            return ACPElicitationForm(
                mode: .url(rawURL),
                question: question,
                fieldOrder: [],
                rules: [:],
                requiredFields: []
            )
        }

        guard modeString == "form" else {
            return nil
        }

        let schemaObj = params.requestedSchema?.objectValue
        let requiredList: [String] = (schemaObj?["required"]?.arrayValue ?? []).compactMap(\.stringValue)
        let requiredSet = Set(requiredList)
        let propertiesObj = schemaObj?["properties"]?.objectValue ?? [:]

        // Deterministic key ordering for stable field arrays in Swift dictionaries.
        let sortedKeys = propertiesObj.keys.sorted()
        var rules: [String: FieldRule] = [:]
        var fields: [AgentQuestion.Field] = []

        for key in sortedKeys {
            // Question IDs must survive trimming to round-trip answers (`elicitationForm.ts:195-196`).
            guard nonEmptyTrimmed(key) == key,
                  let propertyObj = propertiesObj[key]?.objectValue,
                  let parsed = parseField(property: propertyObj) else {
                return nil
            }
            rules[key] = parsed.rule
            let label = nonEmptyTrimmed(propertyObj["title"]?.stringValue) ?? key
            let description = nonEmptyTrimmed(propertyObj["description"]?.stringValue)
            fields.append(
                AgentQuestion.Field(
                    id: key,
                    type: parsed.fieldType,
                    label: label,
                    description: description,
                    required: requiredSet.contains(key),
                    options: parsed.options
                )
            )
        }

        // Every declared `required` key must refer to an askable property.
        for req in requiredSet where rules[req] == nil {
            return nil
        }

        let question = AgentQuestion(
            requestID: requestID,
            title: trimmedTitle,
            message: params.message,
            url: nil,
            fields: fields
        )
        return ACPElicitationForm(
            mode: .form,
            question: question,
            fieldOrder: sortedKeys,
            rules: rules,
            requiredFields: requiredSet
        )
    }

    /// Validates user-supplied string answers against the schema and returns typed ACP JSON values,
    /// or `nil` when a required field is missing or invalid (`elicitationForm.ts:211-221`).
    public func validate(answers: [String: String]) -> [String: ACPJSONValue]? {
        if case .url = mode {
            return [:]
        }
        var output: [String: ACPJSONValue] = [:]
        for id in fieldOrder {
            guard let rule = rules[id] else { continue }
            if let raw = answers[id], let typed = Self.typedAnswer(rule: rule, raw: raw) {
                output[id] = typed
            } else if requiredFields.contains(id) {
                return nil
            }
        }
        return output
    }

    /// Maps an `AgentAnswer` into the `elicitation/create` JSON-RPC result.
    /// Invalid form submissions are declined; user cancellation returns `cancel` (`elicitationForm.ts:179`).
    public func resolve(answer: AgentAnswer) -> ACPElicitationCreateResult {
        switch mode {
        case .url:
            switch answer {
            case .cancelled:
                return ACPElicitationCreateResult(action: .cancel)
            case .option(let id):
                let lowered = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if lowered == "decline" || lowered == "reject" || lowered == "deny" {
                    return ACPElicitationCreateResult(action: .decline)
                }
                return ACPElicitationCreateResult(action: .accept)
            case .form:
                return ACPElicitationCreateResult(action: .accept)
            }
        case .form:
            switch answer {
            case .cancelled:
                return ACPElicitationCreateResult(action: .cancel)
            case .option(let id):
                let lowered = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if lowered == "decline" {
                    return ACPElicitationCreateResult(action: .decline)
                }
                if fieldOrder.count == 1, let singleID = fieldOrder.first,
                   let validated = validate(answers: [singleID: id]) {
                    return ACPElicitationCreateResult(action: .accept, content: validated)
                }
                return ACPElicitationCreateResult(action: .decline)
            case .form(let values):
                guard let validated = validate(answers: values) else {
                    return ACPElicitationCreateResult(action: .decline)
                }
                return ACPElicitationCreateResult(action: .accept, content: validated)
            }
        }
    }

    // MARK: - Schema Parsing Helpers

    private static func parseField(
        property: [String: ACPJSONValue]
    ) -> (rule: FieldRule, fieldType: AgentQuestion.FieldType, options: [AgentQuestion.Option])? {
        guard let typeName = property["type"]?.stringValue else { return nil }
        switch typeName {
        case "string":
            let rawEnum = nonNull(property["enum"])
            let rawOneOf = nonNull(property["oneOf"])
            if rawEnum == nil && rawOneOf == nil {
                return (.text, .text, [])
            }
            let parsedOptions: [AgentQuestion.Option]?
            if let oneOfArray = rawOneOf?.arrayValue {
                parsedOptions = titledOptions(oneOfArray)
            } else if let enumArray = rawEnum?.arrayValue {
                parsedOptions = enumOptions(enumArray)
            } else {
                parsedOptions = nil
            }
            guard let options = parsedOptions, !options.isEmpty else { return nil }
            let values = Set(options.map(\.value))
            return (.choice(values: values), .choice, options)

        case "array":
            guard let itemsObj = property["items"]?.objectValue else { return nil }
            let parsedOptions: [AgentQuestion.Option]?
            if itemsObj["type"]?.stringValue == "string", let enumArray = itemsObj["enum"]?.arrayValue {
                parsedOptions = enumOptions(enumArray)
            } else if itemsObj["type"] == nil, let anyOfArray = itemsObj["anyOf"]?.arrayValue {
                parsedOptions = titledOptions(anyOfArray)
            } else {
                parsedOptions = nil
            }
            guard let options = parsedOptions, !options.isEmpty else { return nil }
            let values = Set(options.map(\.value))
            let minItems = property["minItems"]?.intValue ?? 0
            let maxItems = property["maxItems"]?.intValue ?? Int.max
            // Empty-only or impossible bounds cannot be answered (`elicitationForm.ts:112-116`).
            if minItems < 0 || maxItems == 0 || minItems > maxItems || minItems > values.count {
                return nil
            }
            return (.multiChoice(values: values, minItems: minItems, maxItems: maxItems), .multiChoice, options)

        case "boolean":
            let options = [
                AgentQuestion.Option(value: "true", label: "true", description: "Yes"),
                AgentQuestion.Option(value: "false", label: "false", description: "No"),
            ]
            return (.boolean, .boolean, options)

        case "number":
            return (.number(integer: false), .number, [])

        case "integer":
            return (.number(integer: true), .integer, [])

        default:
            return nil
        }
    }

    private static func enumOptions(_ entries: [ACPJSONValue]) -> [AgentQuestion.Option]? {
        guard !entries.isEmpty else { return nil }
        var rawStrings: [String] = []
        rawStrings.reserveCapacity(entries.count)
        for entry in entries {
            guard let str = entry.stringValue else { return nil }
            rawStrings.append(str)
        }

        var counts: [String: Int] = [:]
        for value in rawStrings {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            counts[trimmed, default: 0] += 1
        }

        let initial: [AgentQuestion.Option] = rawStrings.map { value in
            let plain = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (!plain.isEmpty && counts[plain] == 1) ? plain : jsonQuoted(value)
            return AgentQuestion.Option(value: value, label: label, description: label)
        }

        if Set(initial.map(\.label)).count == initial.count {
            return initial
        }
        return initial.map { option in
            let quoted = jsonQuoted(option.value)
            return AgentQuestion.Option(value: option.value, label: quoted, description: quoted)
        }
    }

    private static func titledOptions(_ entries: [ACPJSONValue]) -> [AgentQuestion.Option]? {
        guard !entries.isEmpty else { return nil }
        var options: [AgentQuestion.Option] = []
        options.reserveCapacity(entries.count)
        for entry in entries {
            guard let obj = entry.objectValue,
                  let constValue = obj["const"]?.stringValue,
                  let label = nonEmptyTrimmed(obj["title"]?.stringValue) ?? nonEmptyTrimmed(constValue) else {
                return nil
            }
            let desc = nonEmptyTrimmed(obj["description"]?.stringValue) ?? label
            options.append(AgentQuestion.Option(value: constValue, label: label, description: desc))
        }
        return options
    }

    private static func typedAnswer(rule: FieldRule, raw: String) -> ACPJSONValue? {
        switch rule {
        case .text:
            return .string(raw)

        case .boolean:
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized == "true" { return .bool(true) }
            if normalized == "false" { return .bool(false) }
            return nil

        case .number(let integer):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let parsed = Double(trimmed), parsed.isFinite else {
                return nil
            }
            if integer {
                guard parsed.rounded() == parsed,
                      parsed >= Double(Int.min),
                      parsed <= Double(Int.max) else {
                    return nil
                }
                return .int(Int(parsed))
            }
            return .double(parsed)

        case .choice(let values):
            return values.contains(raw) ? .string(raw) : nil

        case .multiChoice(let values, let minItems, let maxItems):
            let rawItems = parseMultiChoiceAnswerItems(raw)
            guard let rawItems else { return nil }
            var seen = Set<String>()
            var selected: [String] = []
            for item in rawItems where values.contains(item) {
                if seen.insert(item).inserted {
                    selected.append(item)
                }
            }
            if selected.isEmpty && !rawItems.isEmpty {
                return nil
            }
            guard selected.count >= minItems && selected.count <= maxItems else {
                return nil
            }
            return .array(selected.map(ACPJSONValue.string))
        }
    }

    private static func parseMultiChoiceAnswerItems(_ raw: String) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return []
        }
        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let arr = try? JSONDecoder().decode([ACPJSONValue].self, from: data) {
            var strings: [String] = []
            for item in arr {
                guard let s = item.stringValue else { return nil }
                strings.append(s)
            }
            return strings
        }
        return trimmed.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func nonNull(_ value: ACPJSONValue?) -> ACPJSONValue? {
        guard let value, value != .null else { return nil }
        return value
    }

    private static func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func jsonQuoted(_ value: String) -> String {
        ACPJSONValue.string(value).serializedJSONString()
    }
}
