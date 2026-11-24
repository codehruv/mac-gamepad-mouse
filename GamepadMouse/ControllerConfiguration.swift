import Foundation

enum StickMode: String, Codable, CaseIterable {
    case mouse, scroll, disabled
}

struct StickBinding: Codable, Equatable {
    var mode: StickMode
    var invertX: Bool = false
    var invertY: Bool = false

    init(mode: StickMode) { self.mode = mode }

    private enum CodingKeys: String, CodingKey { case mode, invertX, invertY }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decode(StickMode.self, forKey: .mode)
        invertX = try c.decodeIfPresent(Bool.self, forKey: .invertX) ?? false
        invertY = try c.decodeIfPresent(Bool.self, forKey: .invertY) ?? false
    }
}

enum ShortcutModifier: String, Codable, Hashable, CaseIterable { case command, option, control, shift }

struct TouchpadConfiguration: Codable, Equatable {
    var enabled = true
    var scrollSensitivity: Double = 600
    var invertY = false

    init() {}
    private enum CodingKeys: String, CodingKey { case enabled, scrollSensitivity, invertY }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        scrollSensitivity = try c.decodeIfPresent(Double.self, forKey: .scrollSensitivity) ?? scrollSensitivity
        invertY = try c.decodeIfPresent(Bool.self, forKey: .invertY) ?? invertY
    }
}

struct KeyShortcut: Codable, Equatable {
    var key: String
    var modifiers: [ShortcutModifier] = []

    init(key: String, modifiers: [ShortcutModifier] = []) {
        self.key = key
        self.modifiers = modifiers
    }

    private enum CodingKeys: String, CodingKey { case key, modifiers }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        modifiers = try c.decodeIfPresent([ShortcutModifier].self, forKey: .modifiers) ?? []
    }

    var keyCode: UInt16? { Self.keyCodes[key.lowercased()] }
    var label: String { (modifiers.map(\.rawValue) + [key]).joined(separator: "+") }

    // macOS virtual key codes: physical US keyboard positions, independent of Carbon imports.
    static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "enter": 36,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
        "`": 50, "backspace": 51, "escape": 53, "f17": 64, "f18": 79,
        "f19": 80, "f20": 90, "f5": 96, "f6": 97, "f7": 98, "f3": 99,
        "f8": 100, "f9": 101, "f11": 103, "f13": 105, "f16": 106,
        "f14": 107, "f10": 109, "f12": 111, "f15": 113, "home": 115,
        "pageup": 116, "delete": 117, "f4": 118, "end": 119, "f2": 120,
        "pagedown": 121, "f1": 122, "left": 123, "right": 124, "down": 125, "up": 126
    ]
}

enum MouseBinding: String, Codable { case left, right, middle }
enum ActionType: String, Codable { case mouse, key, switcher, dictation, none }

struct ButtonAction: Codable, Equatable {
    var type: ActionType
    var button: MouseBinding?
    var key: String?
    var modifiers: [ShortcutModifier]

    init(type: ActionType, button: MouseBinding? = nil, key: String? = nil,
         modifiers: [ShortcutModifier] = []) {
        self.type = type
        self.button = button
        self.key = key
        self.modifiers = modifiers
    }

    private enum CodingKeys: String, CodingKey { case type, button, key, modifiers }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(ActionType.self, forKey: .type)
        button = try c.decodeIfPresent(MouseBinding.self, forKey: .button)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        modifiers = try c.decodeIfPresent([ShortcutModifier].self, forKey: .modifiers) ?? []
    }

    var shortcut: KeyShortcut? {
        key.map { KeyShortcut(key: $0, modifiers: modifiers) }
    }

    var label: String {
        switch type {
        case .mouse: return "\(button?.rawValue.capitalized ?? "?") click / hold"
        case .key: return shortcut?.label ?? "Missing key"
        case .switcher: return "\(shortcut?.label ?? "Missing key") — select on release"
        case .dictation: return "Toggle Dictation"
        case .none: return "Disabled"
        }
    }
}

struct ApplicationProfile: Codable, Equatable {
    var apps: [String]
    var buttons: [String: ButtonAction] = [:]

    private enum CodingKeys: String, CodingKey { case apps, buttons }
    init(apps: [String], buttons: [String: ButtonAction] = [:]) {
        self.apps = apps
        self.buttons = buttons
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = try c.decode([String].self, forKey: .apps)
        buttons = try c.decodeIfPresent([String: ButtonAction].self, forKey: .buttons) ?? [:]
    }
}

struct ConfigurationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ControllerConfiguration: Codable, Equatable {
    var version = 1
    var leftStick = StickBinding(mode: .mouse)
    var rightStick = StickBinding(mode: .scroll)
    var touchpad = TouchpadConfiguration()
    var pointerSensitivity: Double = 1200
    var scrollSpeed: Double = 35
    var deadzone: Double = 0.12
    var dictation = KeyShortcut(key: "d", modifiers: [.control, .option])
    var buttons: [String: ButtonAction] = Self.desktopButtons
    var profiles: [String: ApplicationProfile] = [:]
    var showModeOverlay = true

    static let buttonNames = [
        "a", "b", "x", "y", "leftShoulder", "rightShoulder", "leftTrigger",
        "rightTrigger", "menu", "options", "home", "leftStick", "rightStick", "dpadUp",
        "dpadDown", "dpadLeft", "dpadRight", "backLeft", "backRight",
        "backLeft2", "backRight2", "touchpad"
    ]
    static let desktopButtons: [String: ButtonAction] = [
        "a": .init(type: .mouse, button: .left),
        "b": .init(type: .key, key: "escape"),
        "x": .init(type: .mouse, button: .right),
        "y": .init(type: .key, key: "enter"),
        "leftShoulder": .init(type: .key, key: "[", modifiers: [.command]),
        "rightShoulder": .init(type: .switcher, key: "tab", modifiers: [.control]),
        "leftTrigger": .init(type: .dictation),
        "rightTrigger": .init(type: .switcher, key: "tab", modifiers: [.command]),
        "menu": .init(type: .key, key: "space", modifiers: [.command]),
        "options": .init(type: .key, key: "up", modifiers: [.control]),
        "rightStick": .init(type: .mouse, button: .middle),
        "leftStick": .init(type: .dictation),
        "backLeft": .init(type: .key, key: "c", modifiers: [.command]),
        "backRight": .init(type: .key, key: "v", modifiers: [.command]),
        "dpadUp": .init(type: .key, key: "up"),
        "dpadDown": .init(type: .key, key: "down"),
        "dpadLeft": .init(type: .key, key: "left"),
        "dpadRight": .init(type: .key, key: "right")
    ]

    init() {}
    private enum CodingKeys: String, CodingKey {
        case version, leftStick, rightStick, touchpad, pointerSensitivity, scrollSpeed, deadzone, dictation, buttons,
             profiles, showModeOverlay
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        leftStick = try c.decodeIfPresent(StickBinding.self, forKey: .leftStick) ?? leftStick
        rightStick = try c.decodeIfPresent(StickBinding.self, forKey: .rightStick) ?? rightStick
        touchpad = try c.decodeIfPresent(TouchpadConfiguration.self, forKey: .touchpad) ?? touchpad
        pointerSensitivity = try c.decodeIfPresent(Double.self, forKey: .pointerSensitivity) ?? pointerSensitivity
        scrollSpeed = try c.decodeIfPresent(Double.self, forKey: .scrollSpeed) ?? scrollSpeed
        deadzone = try c.decodeIfPresent(Double.self, forKey: .deadzone) ?? deadzone
        dictation = try c.decodeIfPresent(KeyShortcut.self, forKey: .dictation) ?? dictation
        // An explicit buttons object is complete: {} disables all configurable buttons.
        buttons = try c.decodeIfPresent([String: ButtonAction].self, forKey: .buttons) ?? buttons
        profiles = try c.decodeIfPresent([String: ApplicationProfile].self, forKey: .profiles) ?? profiles
        showModeOverlay = try c.decodeIfPresent(Bool.self, forKey: .showModeOverlay) ?? showModeOverlay
    }

    func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError(message: message) }
        }
        try require(version == 1, "Unsupported config version \(version); expected 1.")
        try require(pointerSensitivity.isFinite && (200...4000).contains(pointerSensitivity),
                    "pointerSensitivity must be between 200 and 4000.")
        try require(scrollSpeed.isFinite && (5...120).contains(scrollSpeed), "scrollSpeed must be between 5 and 120.")
        try require(deadzone.isFinite && (0...0.95).contains(deadzone), "deadzone must be between 0 and 0.95.")
        try require(touchpad.scrollSensitivity.isFinite && (50...3000).contains(touchpad.scrollSensitivity),
                    "touchpad.scrollSensitivity must be between 50 and 3000.")
        try require(dictation.keyCode != nil, "Unknown dictation key: \(dictation.key).")
        func validateButtons(_ candidate: [String: ButtonAction], context: String) throws {
            for (id, action) in candidate {
                try require(Self.buttonNames.contains(id), "\(context)unknown button: \(id).")
                switch action.type {
                case .mouse:
                    try require(action.button != nil && action.key == nil && action.modifiers.isEmpty,
                                "\(context)\(id): mouse needs button (left/right/middle), without key or modifiers.")
                case .key, .switcher:
                    try require(action.shortcut?.keyCode != nil && action.button == nil,
                                "\(context)\(id): key needs a supported key name, without a mouse button.")
                    if action.type == .switcher {
                        try require(!action.modifiers.isEmpty, "\(context)\(id): switcher requires at least one modifier.")
                    }
                case .dictation, .none:
                    try require(action.button == nil && action.key == nil && action.modifiers.isEmpty,
                                "\(context)\(id): \(action.type.rawValue) does not take button, key or modifiers.")
                }
            }
        }
        try validateButtons(buttons, context: "")
        var claimedApps: [String: String] = [:]
        for name in profiles.keys.sorted() {
            guard let profile = profiles[name] else { continue }
            try require(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Profile names cannot be blank.")
            try require(!profile.apps.isEmpty, "Profile \(name) must list at least one app bundle ID.")
            try validateButtons(profile.buttons, context: "Profile \(name), ")
            for bundleID in profile.apps {
                try require(!bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            "Profile \(name) contains a blank app bundle ID.")
                if let owner = claimedApps[bundleID] {
                    throw ConfigurationError(message: "App \(bundleID) appears in profiles \(owner) and \(name).")
                }
                claimedApps[bundleID] = name
            }
        }
    }

    func profileName(for bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        return profiles.keys.sorted().first { profiles[$0]?.apps.contains(bundleID) == true }
    }

    func buttons(for bundleID: String?) -> [String: ButtonAction] {
        guard let name = profileName(for: bundleID), let profile = profiles[name] else { return buttons }
        return buttons.merging(profile.buttons) { _, override in override }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data([10])
    }
}

/// File I/O is outside the input loop. Invalid edits leave the last good mapping active.
final class ConfigurationFile {
    let url: URL
    private var loadedData: Data?

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/gamepad-mouse/config.json")) {
        self.url = url
    }

    func load() throws -> ControllerConfiguration {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ControllerConfiguration().encoded().write(to: url, options: .withoutOverwriting)
        }
        let data = try Data(contentsOf: url)
        let configuration = try JSONDecoder().decode(ControllerConfiguration.self, from: data)
        try configuration.validate()
        loadedData = data
        return configuration
    }

    /// Load an external edit only when its bytes differ from the last valid load/save.
    /// Missing or invalid files never replace the last good in-memory configuration.
    func loadIfChanged() throws -> ControllerConfiguration? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigurationError(message: "Config file is missing. Previous mapping kept.")
        }
        let data = try Data(contentsOf: url)
        guard data != loadedData else { return nil }
        let configuration = try JSONDecoder().decode(ControllerConfiguration.self, from: data)
        try configuration.validate()
        loadedData = data
        return configuration
    }

    func save(_ configuration: ControllerConfiguration) throws {
        guard let loadedData, try Data(contentsOf: url) == loadedData else {
            throw ConfigurationError(message: "Config changed on disk. Reload Config before saving slider changes.")
        }
        let data = try configuration.encoded()
        try data.write(to: url, options: .atomic)
        self.loadedData = data
    }
}
