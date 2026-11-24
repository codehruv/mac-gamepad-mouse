import Foundation

/// DualSense USB/Bluetooth wire layout; only full input reports carry Edge extras.
/// Protocol reference: Sony's hid-playstation driver in the Linux kernel.
struct DualSenseReport {
    let buttons: Set<String>
    let touching: Bool
    let y: Double

    init?(bytes: [UInt8]) {
        let offset: Int
        if bytes.count == 64 && bytes[0] == 0x01 { offset = 1 }
        else if bytes.count == 78 && bytes[0] == 0x31 { offset = 2 }
        else { return nil }
        let flags = bytes[offset + 9]
        var pressed = Set<String>()
        if flags & 0x40 != 0 { pressed.insert("backLeft") }
        if flags & 0x80 != 0 { pressed.insert("backRight") }
        if flags & 0x02 != 0 { pressed.insert("touchpad") }
        buttons = pressed
        touching = bytes[offset + 32] & 0x80 == 0
        let rawY = Int(bytes[offset + 34] >> 4) | Int(bytes[offset + 35]) << 4
        y = 1 - Double(min(rawY, 1079)) / 1079 * 2
    }
}

/// Track actual finger contact; lift and fresh touches must never jump the scroll position.
struct TouchpadScrollState {
    private var lastY: Double?
    private var needsLift = true

    mutating func reset() {
        lastY = nil
        needsLift = true
    }

    mutating func update(y: Double, touching: Bool, configuration: TouchpadConfiguration) -> Double {
        guard touching else {
            lastY = nil
            needsLift = false
            return 0
        }
        guard configuration.enabled, !needsLift else { return 0 }
        defer { lastY = y }
        guard let previous = lastY else { return 0 }
        return -(y - previous) * configuration.scrollSensitivity * (configuration.invertY ? -1 : 1)
    }
}

/// Buttons held during enable, reconnect or reload must be released before firing.
struct ButtonState {
    private var previous = Set<String>()
    private var blocked = Set<String>()
    private var armed = false

    mutating func reset() {
        previous.removeAll()
        blocked.removeAll()
        armed = false
    }

    mutating func update(_ current: Set<String>) -> (pressed: Set<String>, released: Set<String>) {
        if !armed {
            armed = true
            previous = current
            blocked = current
            return ([], [])
        }
        let pressed = current.subtracting(previous).subtracting(blocked)
        let released = previous.subtracting(current).subtracting(blocked)
        blocked.formIntersection(current)
        previous = current
        return (pressed, released)
    }
}
