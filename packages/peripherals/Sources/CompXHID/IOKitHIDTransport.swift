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

import CompXProtocol
import Foundation
import IOKit
import IOKit.hid

/// Talks to the mouse through IOKit's HID manager.
///
/// - Matching: vendor ID + product ID + primary usage page `0xFF05`. On macOS
///   interface 1 is ONE `IOHIDDevice` whose primary usage page is the vendor
///   page; the consumer and mouse collections ride on the same device, so input
///   reports with other IDs arrive too and are dropped here.
/// - Opened with `kIOHIDOptionsTypeNone`. Never seize it: it is also the pointer.
/// - Output: `IOHIDDeviceSetReport(kIOHIDReportTypeOutput)` with the report ID
///   as BOTH the argument and the first buffer byte, exactly as hidapi's macOS
///   backend does for numbered reports.
/// - Input: an input-report callback scheduled on a private thread's run loop
///   queues replies; `read(timeout:)` waits on a semaphore. `IOHIDDeviceGetReport`
///   is not reliable on this class of device, so it is not used.
public final class IOKitHIDTransport: HIDTransport {
    /// What the callback buffer looks like. Decided on hardware: see
    /// `reportsIncludeReportID` below and the package README.
    public let reportsIncludeReportID: Bool

    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let inputReportID: UInt8
    private let bufferSize = 64
    private let buffer: UnsafeMutablePointer<UInt8>

    private let lock = NSLock()
    private var queue: [[UInt8]] = []
    private let available = DispatchSemaphore(value: 0)

    /// Filled in by the input thread. A box, so the thread never retains `self`.
    private final class RunLoopBox: @unchecked Sendable { var runLoop: CFRunLoop? }
    private let loop = RunLoopBox()
    private var thread: Thread?
    private var isClosed = false

    /// Whether a CompX mouse is attached, without opening it.
    public static func isPresent() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, matching() as CFDictionary)
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        return !(IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).isEmpty
    }

    static func matching() -> [String: Any] {
        [
            kIOHIDVendorIDKey: CompXDevice.vendorID,
            kIOHIDProductIDKey: CompXDevice.productID,
            kIOHIDPrimaryUsagePageKey: CompXDevice.vendorUsagePage,
        ]
    }

    public init(inputReportID: UInt8 = CompXDevice.reportID) throws {
        self.inputReportID = inputReportID
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, Self.matching() as CFDictionary)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        // Deterministic pick if a second mouse is ever attached.
        guard let device = devices.min(by: { Self.locationID($0) < Self.locationID($1) }) else {
            throw CompXError.deviceNotFound
        }
        self.device = device
        let opened = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else {
            throw CompXError.io(operation: "IOHIDDeviceOpen", code: opened)
        }
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
        // On macOS the callback buffer for a numbered report starts with the
        // report ID (hidapi copies it verbatim and its read() returns it at
        // [0]). Verified on hardware on 2026-10-07 with --trace.
        reportsIncludeReportID = true
        startInputThread()
    }

    deinit {
        close()
        buffer.deallocate()
    }

    public func write(reportID: UInt8, payload: [UInt8]) throws {
        drainPendingInput()
        let report = [reportID] + payload
        let result = report.withUnsafeBufferPointer { bytes in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID),
                                 bytes.baseAddress!, bytes.count)
        }
        guard result == kIOReturnSuccess else {
            throw CompXError.io(operation: "IOHIDDeviceSetReport", code: result)
        }
    }

    public func read(timeout: Duration) throws -> [UInt8] {
        guard available.wait(timeout: .now() + timeout.timeInterval) == .success else {
            throw CompXError.timeout
        }
        lock.lock()
        defer { lock.unlock() }
        return queue.removeFirst()
    }

    public func close() {
        lock.lock()
        if isClosed { lock.unlock(); return }
        isClosed = true
        lock.unlock()
        if let runLoop = loop.runLoop {
            // Unschedule on the run loop's own thread, then let it exit. The
            // block must not capture `self`: close() also runs from deinit.
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [device, buffer, bufferSize] in
                IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
                IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
            while thread?.isFinished == false { Thread.sleep(forTimeInterval: 0.001) }
        }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: - Input

    fileprivate func receive(reportID: UInt32, bytes: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard reportID == UInt32(inputReportID), length > 0 else { return }
        let report = Array(UnsafeBufferPointer(start: bytes, count: length))
        lock.lock()
        queue.append(report)
        lock.unlock()
        available.signal()
    }

    private func drainPendingInput() {
        lock.lock()
        defer { lock.unlock() }
        while available.wait(timeout: .now()) == .success { queue.removeFirst() }
    }

    private func startInputThread() {
        let ready = DispatchSemaphore(value: 0)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let thread = Thread { [device, buffer, bufferSize, loop] in
            let runLoop = CFRunLoopGetCurrent()!
            loop.runLoop = runLoop
            IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, _, _, _, reportID, report, length in
                guard let context else { return }
                Unmanaged<IOKitHIDTransport>.fromOpaque(context).takeUnretainedValue()
                    .receive(reportID: reportID, bytes: report, length: length)
            }, context)
            IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "CompXHID input"
        self.thread = thread
        thread.start()
        ready.wait()
    }

    private static func locationID(_ device: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int) ?? 0
    }
}
