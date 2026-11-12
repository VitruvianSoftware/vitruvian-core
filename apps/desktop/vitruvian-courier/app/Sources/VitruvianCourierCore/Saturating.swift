// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Arithmetic on the engine's millisecond times that stops at the ends of Int64 instead of trapping. The engine
/// clamps what it stores, but a row from before it did, or a newer engine, could still hand over any Int64.
extension Int64 {
    /// self − other, or Int64.min / Int64.max where that is past the end.
    func saturatingMinus(_ other: Int64) -> Int64 {
        let (result, overflow) = subtractingReportingOverflow(other)
        return overflow ? (other < 0 ? .max : .min) : result
    }

    /// self + other, or Int64.min / Int64.max where that is past the end.
    func saturatingPlus(_ other: Int64) -> Int64 {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? (other < 0 ? .min : .max) : result
    }
}
