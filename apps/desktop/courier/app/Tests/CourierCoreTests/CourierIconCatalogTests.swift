// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Foundation
import XCTest

@testable import CourierCore

final class CourierIconCatalogTests: XCTestCase {
    private static let expectedMaterialSymbolRows: [String] = [
        "ac_unit.tsx", "account_circle.tsx", "add.tsx", "air.tsx", "archive.tsx",
        "assignment.tsx", "asterisk.tsx", "audio_file.tsx", "auto_awesome.tsx",
        "background_replace.tsx", "beach_access.tsx", "bed.tsx", "blur_on.tsx",
        "bolt.tsx", "book_2.tsx", "business_center.tsx", "cake.tsx",
        "calendar_month.tsx", "call.tsx", "campaign.tsx", "casino.tsx",
        "celebration.tsx", "check.tsx", "check_circle.tsx", "chevron_forward.tsx",
        "chevron_right.tsx", "clear_day.tsx", "close.tsx", "code.tsx",
        "content_copy.tsx", "csv.tsx", "deceased.tsx", "directions_bike.tsx",
        "directions_boat.tsx", "directions_car.tsx", "directions_walk.tsx",
        "download.tsx", "draft.tsx", "edit_square.tsx", "email.tsx",
        "error_outline.tsx", "escalator_warning.tsx", "expand_more.tsx", "explore.tsx",
        "eyeglasses.tsx", "family_restroom.tsx", "favorite.tsx", "filter_list.tsx",
        "fingerprint.tsx", "fitness_center.tsx", "folder_zip.tsx", "footprint.tsx",
        "forward.tsx", "function.tsx", "group.tsx", "hardware.tsx",
        "headset_mic.tsx", "heat.tsx", "hiking.tsx", "home.tsx",
        "hourglass_bottom.tsx", "image.tsx", "inbox.tsx", "joystick.tsx",
        "keep.tsx", "key.tsx", "kitchen.tsx", "language.tsx", "library_add.tsx",
        "link.tsx", "local_cafe.tsx", "location_city.tsx", "looks.tsx",
        "low_priority_space.tsx", "map.tsx", "maps_ugc.tsx", "mark_email_unread.tsx",
        "mode_comment.tsx", "mood.tsx", "moon_stars.tsx", "moped.tsx",
        "more_horiz.tsx", "motorcycle.tsx", "movie.tsx", "music_note.tsx",
        "nature.tsx", "nest_eco_leaf.tsx", "newspaper.tsx", "notifications.tsx",
        "notifications_off.tsx", "pentagon.tsx", "person.tsx", "pets.tsx",
        "photo_camera.tsx", "photo_library.tsx", "podcasts.tsx", "pool.tsx",
        "rainy.tsx", "reply.tsx", "restaurant.tsx", "reviews.tsx", "road.tsx",
        "rowing.tsx", "sailing.tsx", "schedule.tsx", "schedule_send.tsx",
        "school.tsx", "search.tsx", "self_improvement.tsx", "settings.tsx",
        "shopping_cart.tsx", "signature.tsx", "signpost.tsx", "skateboarding.tsx",
        "skillet_cooktop.tsx", "sms.tsx", "speaker.tsx", "speed.tsx",
        "sports_basketball.tsx", "sports_cricket.tsx", "sports_football.tsx",
        "sports_gymnastics.tsx", "sports_score.tsx", "sports_soccer.tsx",
        "sports_tennis.tsx", "stadia_controller.tsx", "star.tsx", "stethoscope.tsx",
        "stop.tsx", "storefront.tsx", "stroller.tsx", "stylus_pencil.tsx",
        "surfing.tsx", "sync.tsx", "theater_comedy.tsx", "train.tsx",
        "translate.tsx", "travel.tsx", "unfold_more.tsx", "video_file.tsx",
        "videocam.tsx", "view_sidebar.tsx", "visibility.tsx", "volume_up.tsx",
        "warning.tsx", "watch.tsx", "water_bottle.tsx", "water_drop.tsx",
        "waves.tsx", "weekend.tsx", "wine_bar.tsx",
    ]

    private static let expectedUIPrimitiveRows: [String] = [
        "OutlineCheck.tsx", "OutlineChevronDown.tsx", "OutlineChevronDownSmall.tsx",
        "OutlineChevronRightSmall.tsx", "OutlineClip.tsx", "OutlineClock.tsx",
        "OutlineCompose.tsx", "OutlineSearch.tsx", "OutlineSidebar.tsx",
        "OutlineSpinner.tsx", "OutlineTrash.tsx", "SolidCircleCheck.tsx",
        "SolidMoon.tsx", "PlusIcon.tsx", "SearchIcon.tsx", "ErrorCircle.tsx",
        "ConfettiIcon.tsx", "icons-custom.tsx", "icons-general.tsx",
        "icons-toolbar.tsx", "icons-networks.tsx", "icons.tsx",
        "default.tsx", "drag_handle.tsx", "drag_indicator.tsx",
        "CreateLabelNudgeIcon.tsx",
    ]

    func testEverySection22MaterialSymbolRowIsMappedToValidSFSymbol() {
        XCTAssertEqual(Self.expectedMaterialSymbolRows.count, 151)
        XCTAssertEqual(CourierIconCatalog.labelAndSpaceIcons.count, 151)
        XCTAssertEqual(
            CourierIconCatalog.labelAndSpaceIcons.map(\.ledgerComponent),
            Self.expectedMaterialSymbolRows
        )

        for entry in CourierIconCatalog.labelAndSpaceIcons {
            XCTAssertFalse(entry.title.isEmpty, "Missing title for \(entry.ledgerComponent)")
            XCTAssertFalse(entry.sfSymbol.isEmpty, "Missing sfSymbol for \(entry.ledgerComponent)")
            XCTAssertNotEqual(entry.category, .all, "Icon entry \(entry.ledgerComponent) must have a specific category")
            XCTAssertNotNil(
                NSImage(systemSymbolName: entry.sfSymbol, accessibilityDescription: entry.title),
                "SF Symbol '\(entry.sfSymbol)' for \(entry.ledgerComponent) did not resolve on macOS"
            )
            XCTAssertTrue(CourierIconCatalog.allowedLabelSFSymbols.contains(entry.sfSymbol))
        }

        let primitiveNames = Set(CourierIconCatalog.uiPrimitiveIcons.map(\.ledgerComponent))
        for expected in Self.expectedUIPrimitiveRows {
            XCTAssertTrue(primitiveNames.contains(expected), "Missing UI primitive icon row \(expected)")
        }
        for entry in CourierIconCatalog.uiPrimitiveIcons {
            XCTAssertFalse(entry.title.isEmpty, "Missing title for \(entry.ledgerComponent)")
            XCTAssertNotNil(
                NSImage(systemSymbolName: entry.sfSymbol, accessibilityDescription: entry.title),
                "SF Symbol '\(entry.sfSymbol)' for UI primitive \(entry.ledgerComponent) did not resolve on macOS"
            )
        }

        for defaultIcon in LabelsModel.icons {
            XCTAssertTrue(CourierIconCatalog.allowedLabelSFSymbols.contains(defaultIcon))
            XCTAssertNotNil(NSImage(systemSymbolName: defaultIcon, accessibilityDescription: defaultIcon))
        }
    }

    func testSearchFiltersByCategoryKeywordAndMaterialName() {
        let allResults = CourierIconCatalog.search(query: "", category: .all)
        XCTAssertEqual(allResults.count, 151)

        let wineResults = CourierIconCatalog.search(query: "wine")
        XCTAssertTrue(wineResults.contains { $0.ledgerComponent == "wine_bar.tsx" && $0.sfSymbol == "wineglass" })

        let rowingResults = CourierIconCatalog.search(query: "rowing")
        XCTAssertTrue(rowingResults.contains { $0.ledgerComponent == "rowing.tsx" && $0.sfSymbol == "figure.rower" })

        let kayakResults = CourierIconCatalog.search(query: "kayak")
        XCTAssertTrue(kayakResults.contains { $0.ledgerComponent == "rowing.tsx" })

        let snowResults = CourierIconCatalog.search(query: "ac_unit")
        XCTAssertEqual(snowResults.first?.ledgerComponent, "ac_unit.tsx")
        XCTAssertEqual(snowResults.first?.sfSymbol, "snowflake")

        for category in CourierIconCategory.allCases where category != .all {
            XCTAssertFalse(category.title.isEmpty)
            let filtered = CourierIconCatalog.search(query: "", category: category)
            XCTAssertFalse(filtered.isEmpty, "Category \(category) should not be empty")
            XCTAssertTrue(filtered.allSatisfy { $0.category == category })
        }
    }
}
