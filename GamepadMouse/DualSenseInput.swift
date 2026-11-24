import Foundation
import GameController
import IOKit.hid

/// Read only the Edge extras omitted by GameController, without seizing the device.
/// All callbacks and consumers use the main run loop. Never monitors keyboards.
final class DualSenseInput {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var readers: [io_service_t: Reader] = [:]

    init() {
        IOHIDManagerSetDeviceMatching(manager,
            [kIOHIDVendorIDKey: 0x054c, kIOHIDProductIDKey: 0x0df2] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context, result == kIOReturnSuccess else { return }
            let owner = Unmanaged<DualSenseInput>.fromOpaque(context).takeUnretainedValue()
            owner.readers[IOHIDDeviceGetService(device)] = Reader(device: device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let owner = Unmanaged<DualSenseInput>.fromOpaque(context).takeUnretainedValue()
            owner.readers[IOHIDDeviceGetService(device)] = nil
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        readers.removeAll()
    }

    func snapshot(for controller: GCController) -> DualSenseReport? {
        // Fail closed when several Edges are connected: GCController exposes no
        // public serial identifier with which to pair them unambiguously.
        guard controller.vendorName?.contains("DualSense Edge") == true,
              readers.count == 1, let reader = readers.values.first,
              let received = reader.received, Date().timeIntervalSince(received) < 0.5 else { return nil }
        return reader.report
    }

    private final class Reader {
        let device: IOHIDDevice
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
        var report: DualSenseReport?
        var received: Date?

        init(device: IOHIDDevice) {
            self.device = device
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 256, { context, result, _, _, _, bytes, length in
                guard let context, result == kIOReturnSuccess else { return }
                let reader = Unmanaged<Reader>.fromOpaque(context).takeUnretainedValue()
                guard let report = DualSenseReport(bytes: Array(UnsafeBufferPointer(start: bytes, count: length))) else { return }
                reader.report = report
                reader.received = Date()
            }, Unmanaged.passUnretained(self).toOpaque())
        }

        deinit {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 256, nil, nil)
            buffer.deallocate()
        }
    }
}
