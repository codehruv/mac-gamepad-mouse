import Foundation

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
