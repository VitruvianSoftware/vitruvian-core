// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation

/// Pure-Swift BlurHash base83 + DCT decoder (`BlurHashDecoder.decode(_:width:height:)`).
///
/// Decodes compact BlurHash strings stored on Matrix event `info` (`xyz.amorgan.blurhash`)
/// into a small `CGImage` suitable for immediate inline placeholder rendering while the
/// full image or thumbnail loads from the local media store.
public enum BlurHashDecoder {
    private static let alphabet: [UInt8] = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-./:;=?@[]^_{|}~".utf8
    )

    private static let lookupTable: [Int] = {
        var table = Array(repeating: -1, count: 128)
        for (index, byte) in alphabet.enumerated() where Int(byte) < table.count {
            table[Int(byte)] = index
        }
        return table
    }()

    /// Decodes `blurHash` into a `width × height` `CGImage`, or returns `nil` if the string
    /// or dimensions are invalid.
    public static func decode(_ blurHash: String, width: Int = 32, height: Int = 32, punch: Float = 1.0) -> CGImage? {
        guard width > 0, height > 0, width <= 1024, height <= 1024 else { return nil }
        let bytes = Array(blurHash.utf8)
        guard bytes.count >= 6 else { return nil }

        guard let sizeFlag = decode83(bytes, range: 0 ..< 1) else { return nil }
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1
        guard bytes.count == 4 + 2 * numX * numY else { return nil }

        guard let quantisedMaximumValue = decode83(bytes, range: 1 ..< 2) else { return nil }
        let maximumValue = (Float(quantisedMaximumValue + 1) / 166.0) * punch

        var colors: [(Float, Float, Float)] = []
        colors.reserveCapacity(numX * numY)

        guard let dcValue = decode83(bytes, range: 2 ..< 6) else { return nil }
        colors.append(decodeDC(dcValue))

        for index in 1 ..< (numX * numY) {
            let start = 4 + index * 2
            guard let acValue = decode83(bytes, range: start ..< (start + 2)) else { return nil }
            colors.append(decodeAC(acValue, maximumValue: maximumValue))
        }

        // Precompute horizontal and vertical cosine basis values.
        var cosX = Array(repeating: Float(0), count: width * numX)
        for x in 0 ..< width {
            for i in 0 ..< numX {
                cosX[x * numX + i] = cos(Float.pi * Float(x) * Float(i) / Float(width))
            }
        }
        var cosY = Array(repeating: Float(0), count: height * numY)
        for y in 0 ..< height {
            for j in 0 ..< numY {
                cosY[y * numY + j] = cos(Float.pi * Float(y) * Float(j) / Float(height))
            }
        }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)

        for y in 0 ..< height {
            let yRow = y * numY
            let pixelRowOffset = y * bytesPerRow
            for x in 0 ..< width {
                let xRow = x * numX
                var r: Float = 0
                var g: Float = 0
                var b: Float = 0

                for j in 0 ..< numY {
                    let cy = cosY[yRow + j]
                    let colorRow = j * numX
                    for i in 0 ..< numX {
                        let basis = cosX[xRow + i] * cy
                        let color = colors[colorRow + i]
                        r += color.0 * basis
                        g += color.1 * basis
                        b += color.2 * basis
                    }
                }

                let offset = pixelRowOffset + x * 4
                pixels[offset] = UInt8(clamping: linearToSRGB(r))
                pixels[offset + 1] = UInt8(clamping: linearToSRGB(g))
                pixels[offset + 2] = UInt8(clamping: linearToSRGB(b))
                pixels[offset + 3] = 255
            }
        }

        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func decode83(_ bytes: [UInt8], range: Range<Int>) -> Int? {
        var value = 0
        for index in range {
            let byte = Int(bytes[index])
            guard byte >= 0, byte < lookupTable.count else { return nil }
            let digit = lookupTable[byte]
            guard digit >= 0 else { return nil }
            value = value * 83 + digit
        }
        return value
    }

    private static func decodeDC(_ value: Int) -> (Float, Float, Float) {
        let intR = value >> 16
        let intG = (value >> 8) & 255
        let intB = value & 255
        return (sRGBToLinear(intR), sRGBToLinear(intG), sRGBToLinear(intB))
    }

    private static func decodeAC(_ value: Int, maximumValue: Float) -> (Float, Float, Float) {
        let quantR = value / (19 * 19)
        let quantG = (value / 19) % 19
        let quantB = value % 19
        return (
            signPow((Float(quantR) - 9.0) / 9.0, 2.0) * maximumValue,
            signPow((Float(quantG) - 9.0) / 9.0, 2.0) * maximumValue,
            signPow((Float(quantB) - 9.0) / 9.0, 2.0) * maximumValue
        )
    }

    private static func signPow(_ value: Float, _ exp: Float) -> Float {
        copysign(pow(abs(value), exp), value)
    }

    private static func linearToSRGB(_ value: Float) -> Int {
        let v = max(0, min(1, value))
        if v <= 0.0031308 {
            return Int(v * 12.92 * 255 + 0.5)
        } else {
            return Int((1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5)
        }
    }

    private static func sRGBToLinear(_ value: Int) -> Float {
        let v = Float(value) / 255.0
        if v <= 0.04045 {
            return v / 12.92
        } else {
            return pow((v + 0.055) / 1.055, 2.4)
        }
    }
}
