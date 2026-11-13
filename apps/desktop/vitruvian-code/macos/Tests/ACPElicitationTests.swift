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

import Foundation
@testable import VitruvianCodeCore
import XCTest

final class ACPElicitationTests: XCTestCase {
    func testFormValidationCoversRequiredFieldsEnumsTitledChoicesMultiChoiceBooleanAndNumbers() {
        let schema: ACPJSONValue = .object([
            "type": .string("object"),
            "required": .array([.string("env"), .string("replicas")]),
            "properties": .object([
                "env": .object([
                    "type": .string("string"),
                    "title": .string("Environment"),
                    "enum": .array([.string("dev"), .string("prod")]),
                ]),
                "strategy": .object([
                    "type": .string("string"),
                    "title": .string("Strategy"),
                    "oneOf": .array([
                        .object(["const": .string("canary"), "title": .string("Canary"), "description": .string("Gradual")]),
                        .object(["const": .string("bluegreen"), "title": .string("Blue/Green")]),
                    ]),
                ]),
                "targets": .object([
                    "type": .string("array"),
                    "title": .string("Regions"),
                    "minItems": .int(1),
                    "maxItems": .int(2),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array([.string("us"), .string("eu"), .string("ap")]),
                    ]),
                ]),
                "dryRun": .object([
                    "type": .string("boolean"),
                    "title": .string("Dry Run"),
                ]),
                "replicas": .object([
                    "type": .string("integer"),
                    "title": .string("Replicas"),
                ]),
                "notes": .object([
                    "type": .string("string"),
                    "title": .string("Notes"),
                ]),
            ]),
        ])

        let params = ACPElicitationCreateParams(
            sessionId: "s1",
            mode: "form",
            title: "Release Config",
            message: "Fill deployment parameters",
            requestedSchema: schema
        )

        guard let form = ACPElicitationForm.parse(requestID: "req-1", params: params) else {
            XCTFail("Expected schema to parse as an askable ACPElicitationForm")
            return
        }

        XCTAssertEqual(form.question.requestID, "req-1")
        XCTAssertEqual(form.question.title, "Release Config")
        XCTAssertEqual(form.question.fields.count, 6)

        // Valid answers accept with typed JSON values.
        let accepted = form.resolve(
            answer: .form([
                "env": "prod",
                "strategy": "canary",
                "targets": "us, eu",
                "dryRun": "true",
                "replicas": "3",
                "notes": "ship it",
            ])
        )
        XCTAssertEqual(accepted.action, .accept)
        XCTAssertEqual(accepted.content?["env"], .string("prod"))
        XCTAssertEqual(accepted.content?["strategy"], .string("canary"))
        XCTAssertEqual(accepted.content?["targets"], .array([.string("us"), .string("eu")]))
        XCTAssertEqual(accepted.content?["dryRun"], .bool(true))
        XCTAssertEqual(accepted.content?["replicas"], .int(3))
        XCTAssertEqual(accepted.content?["notes"], .string("ship it"))

        // Missing required `env` or non-integer `replicas` or out-of-enum choice declines.
        XCTAssertEqual(form.resolve(answer: .form(["replicas": "2"])).action, .decline)
        XCTAssertEqual(form.resolve(answer: .form(["env": "prod", "replicas": "2.5"])).action, .decline)
        XCTAssertEqual(form.resolve(answer: .form(["env": "invalid", "replicas": "2"])).action, .decline)

        // Explicit cancellation maps to `cancel` (`elicitationForm.ts:179`).
        XCTAssertEqual(form.resolve(answer: .cancelled).action, .cancel)
    }

    func testUnaskableFormSchemasReturnNil() {
        // Unsupported nested object property.
        let unsupportedProp = ACPElicitationCreateParams(
            sessionId: "s1",
            mode: "form",
            message: "Bad schema",
            requestedSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "nested": .object(["type": .string("object")]),
                ]),
            ])
        )
        XCTAssertNil(ACPElicitationForm.parse(requestID: "r1", params: unsupportedProp))

        // Required field missing from `properties`.
        let missingRequired = ACPElicitationCreateParams(
            sessionId: "s1",
            mode: "form",
            message: "Missing required",
            requestedSchema: .object([
                "type": .string("object"),
                "required": .array([.string("ghost")]),
                "properties": .object([:]),
            ])
        )
        XCTAssertNil(ACPElicitationForm.parse(requestID: "r2", params: missingRequired))

        // Array with impossible bounds (`minItems > maxItems`).
        let impossibleArray = ACPElicitationCreateParams(
            sessionId: "s1",
            mode: "form",
            message: "Impossible array",
            requestedSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "items": .object([
                        "type": .string("array"),
                        "minItems": .int(3),
                        "maxItems": .int(1),
                        "items": .object(["type": .string("string"), "enum": .array([.string("a"), .string("b")])]),
                    ]),
                ]),
            ])
        )
        XCTAssertNil(ACPElicitationForm.parse(requestID: "r3", params: impossibleArray))
    }

    func testURLModeRequiresHTTPOrHTTPSAndResolvesConsent() {
        let validURL = ACPElicitationCreateParams(
            sessionId: "s1",
            mode: "url",
            title: "Sign in",
            message: "Authorize in browser",
            url: "https://example.com/oauth"
        )
        guard let form = ACPElicitationForm.parse(requestID: "url-1", params: validURL) else {
            XCTFail("Expected valid https URL elicitation to parse")
            return
        }
        XCTAssertEqual(form.question.url, "https://example.com/oauth")
        XCTAssertTrue(form.question.fields.isEmpty)
        XCTAssertEqual(form.resolve(answer: .option("accept")).action, .accept)
        XCTAssertEqual(form.resolve(answer: .option("decline")).action, .decline)
        XCTAssertEqual(form.resolve(answer: .cancelled).action, .cancel)

        let unsafeURL = ACPElicitationCreateParams(
            sessionId: "s1",
            mode: "url",
            message: "Bad scheme",
            url: "javascript:alert(1)"
        )
        XCTAssertNil(ACPElicitationForm.parse(requestID: "url-2", params: unsafeURL))
    }
}
