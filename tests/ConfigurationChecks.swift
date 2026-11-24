import Foundation

@main
struct ConfigurationChecks {
    static var passed = 0

    static func check(_ name: String, _ body: () throws -> Void) throws {
        try body()
        passed += 1
        print("PASS \(name)")
    }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "Expectation failed") throws {
        if try condition() == false { throw ConfigurationError(message: message) }
    }

    static func decode(_ text: String) throws -> ControllerConfiguration {
        let config = try JSONDecoder().decode(ControllerConfiguration.self, from: Data(text.utf8))
        try config.validate()
        return config
    }

    static func rejects(_ text: String) throws {
        do {
            _ = try decode(text)
        } catch { return }
        throw ConfigurationError(message: "Invalid configuration was accepted: \(text)")
    }

    static func main() throws {
        if CommandLine.arguments.contains("--print-default-config") {
            print(String(data: try ControllerConfiguration().encoded(), encoding: .utf8)!, terminator: "")
            return
        }
        try check("minimal configuration gets desktop defaults") {
            let config = try decode("{}")
            try expect(config.leftStick.mode == .mouse && config.rightStick.mode == .scroll)
            try expect(config.buttons["leftTrigger"]?.type == .dictation)
            try expect(config.buttons["leftStick"]?.type == .dictation)
        }
        try check("default JSON round trips without losing shortcuts") {
            let original = ControllerConfiguration()
            let decoded = try JSONDecoder().decode(ControllerConfiguration.self, from: original.encoded())
            try expect(decoded == original)
        }
        try check("documented example matches shipped desktop defaults") {
            let example = try String(contentsOfFile: "config.example.json", encoding: .utf8)
            try expect(decode(example) == ControllerConfiguration())
        }
        try check("swap, disable and invert sticks") {
            let config = try decode(#"{"leftStick":{"mode":"disabled"},"rightStick":{"mode":"mouse","invertY":true}}"#)
            try expect(config.leftStick.mode == .disabled && config.rightStick.mode == .mouse && config.rightStick.invertY)
        }
        try check("explicit empty bindings disable all configurable buttons") {
            try expect(decode(#"{"buttons":{}}"#).buttons.isEmpty)
        }
        try check("custom key and dictation shortcuts decode") {
            let config = try decode(#"{"dictation":{"key":"f5"},"buttons":{"y":{"type":"key","key":"c","modifiers":["command","shift"]}}}"#)
            try expect(config.dictation.keyCode == 96)
            try expect(config.buttons["y"]?.shortcut?.modifiers == [.command, .shift])
        }
        try check("back paddles and touchpad bindings decode") {
            let config = try decode(#"{"buttons":{"backLeft":{"type":"key","key":"c","modifiers":["command"]},"backRight":{"type":"mouse","button":"right"},"backLeft2":{"type":"none"},"touchpad":{"type":"key","key":"enter"}},"touchpad":{"invertY":true}}"#)
            try expect(config.buttons["backRight"]?.button == .right)
            try expect(config.touchpad.enabled && config.touchpad.invertY)
            try expect(config.touchpad.scrollSensitivity == 600)
        }
        try check("touchpad config validates types and sensitivity") {
            for text in [#"{"touchpad":{"scrollSensitivity":0}}"#,
                         #"{"touchpad":{"scrollSensitivity":3001}}"#,
                         #"{"touchpad":{"enabled":"yes"}}"#] { try rejects(text) }
        }
        try check("USB and Bluetooth Edge reports decode paddles and touch contact") {
            for (size, id, offset) in [(64, UInt8(1), 1), (78, UInt8(0x31), 2)] {
                var bytes = [UInt8](repeating: 0, count: size)
                bytes[0] = id
                bytes[offset + 9] = 0xc2
                bytes[offset + 32] = 0x80
                let lifted = DualSenseReport(bytes: bytes)!
                try expect(!lifted.touching && lifted.buttons == ["backLeft", "backRight", "touchpad"])
                bytes[offset + 32] = 1
                bytes[offset + 34] = 0x70
                bytes[offset + 35] = 0x43 // y = 1079, bottom of pad
                let down = DualSenseReport(bytes: bytes)!
                try expect(down.touching && down.y == -1)
                bytes[offset + 9] = 0x30 // Fn buttons must not trigger paddles
                try expect(DualSenseReport(bytes: bytes)!.buttons.isEmpty)
            }
            try expect(DualSenseReport(bytes: []) == nil)
            try expect(DualSenseReport(bytes: [1, 0, 0]) == nil)
            var wrongID = [UInt8](repeating: 0, count: 64)
            wrongID[0] = 0x02
            try expect(DualSenseReport(bytes: wrongID) == nil)
        }
        try check("touchpad scroll follows movement including center; lift does not scroll") {
            var state = TouchpadScrollState()
            let config = TouchpadConfiguration()
            try expect(state.update(y: 0, touching: false, configuration: config) == 0)
            try expect(state.update(y: -0.5, touching: true, configuration: config) == 0)
            try expect(state.update(y: 0, touching: true, configuration: config) == -300)
            try expect(state.update(y: 0.5, touching: true, configuration: config) == -300)
            try expect(state.update(y: 0, touching: false, configuration: config) == 0)
            try expect(state.update(y: -0.5, touching: true, configuration: config) == 0)
        }
        try check("touchpad reset waits for lift; inversion and disable work") {
            var state = TouchpadScrollState()
            var config = TouchpadConfiguration()
            try expect(state.update(y: 0.5, touching: true, configuration: config) == 0)
            _ = state.update(y: 0, touching: false, configuration: config)
            _ = state.update(y: 0, touching: true, configuration: config)
            config.invertY = true
            try expect(state.update(y: 0.5, touching: true, configuration: config) == 300)
            config.enabled = false
            try expect(state.update(y: 1, touching: true, configuration: config) == 0)
            state.reset()
            config.enabled = true
            try expect(state.update(y: 0, touching: true, configuration: config) == 0)
        }
        try check("reject unsupported schema version") { try rejects(#"{"version":2}"#) }
        try check("reject malformed JSON") { try rejects("{") }
        try check("reject wrong numeric types and unsafe ranges") {
            for text in [#"{"deadzone":"0.2"}"#, #"{"deadzone":1}"#, #"{"deadzone":-1}"#,
                         #"{"pointerSensitivity":0}"#, #"{"scrollSpeed":9999999}"#] { try rejects(text) }
        }
        try check("reject unknown stick modes, buttons, keys and modifiers") {
            for text in [#"{"leftStick":{"mode":"moues"}}"#,
                         #"{"buttons":{"unknownButton":{"type":"none"}}}"#,
                         #"{"buttons":{"a":{"type":"key","key":"typo"}}}"#,
                         #"{"dictation":{"key":"d","modifiers":["commnad"]}}"#] { try rejects(text) }
        }
        try check("reject incomplete and contradictory action payloads") {
            for text in [#"{"buttons":{"a":{"type":"mouse"}}}"#,
                         #"{"buttons":{"a":{"type":"key"}}}"#,
                         #"{"buttons":{"a":{"type":"none","key":"a"}}}"#,
                         #"{"buttons":{"a":{"type":"mouse","button":"left","key":"a"}}}"#] { try rejects(text) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let file = ConfigurationFile(url: url)
        try check("first load creates config; slider save persists") {
            var config = try file.load()
            config.pointerSensitivity = 1700
            try file.save(config)
            try expect(file.load().pointerSensitivity == 1700)
        }
        try check("slider save refuses to overwrite external edits") {
            let edited = Data(#"{"pointerSensitivity":2300}"#.utf8)
            try edited.write(to: url)
            do {
                try file.save(ControllerConfiguration())
                throw ConfigurationError(message: "Overwrote external edits")
            } catch let error as ConfigurationError {
                try expect(error.message.contains("Config changed"))
            }
            try expect(Data(contentsOf: url) == edited)
            try expect(file.load().pointerSensitivity == 2300)
        }
        try check("invalid JSON is never replaced by defaults") {
            let invalid = Data("{broken".utf8)
            try invalid.write(to: url)
            do {
                _ = try file.load()
                throw ConfigurationError(message: "Invalid JSON loaded")
            } catch is DecodingError {}
            try expect(Data(contentsOf: url) == invalid)
        }
        try check("disabled or newly connected held buttons cannot fire") {
            var state = ButtonState()
            try expect(state.update(["a"]).pressed.isEmpty)
            try expect(state.update(["a"]).pressed.isEmpty)
            try expect(state.update([]).released.isEmpty)
            try expect(state.update(["a"]).pressed == ["a"])
            try expect(state.update(["a"]).pressed.isEmpty)
            try expect(state.update([]).released == ["a"])
        }
        try check("reload and disconnect require a fresh press") {
            var state = ButtonState()
            _ = state.update([])
            _ = state.update(["a"])
            state.reset()
            try expect(state.update(["a"]).pressed.isEmpty)
            _ = state.update([])
            try expect(state.update(["a", "b"]).pressed == ["a", "b"])
            try expect(state.update(["b"]).released == ["a"])
        }
        print("\(passed) configuration and input checks passed")
    }
}
