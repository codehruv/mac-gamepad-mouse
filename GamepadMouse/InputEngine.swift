import AppKit
import Combine
import Foundation
import GameController

/// Poll controller state at 60 Hz; file I/O happens only on load or UI edits.
final class InputEngine: ObservableObject {
    weak var mergePollCoordinator: GlobalKeyboardManager?
    @Published var isEnabled = false
    @Published private(set) var configuration = ControllerConfiguration()
    @Published private(set) var configurationError: String?
    @Published private(set) var lastTickSummary = ""

    private let configFile = ConfigurationFile()
    private let controllerService: ControllerService
    private let mouse: MouseInjector
    private let keyboard: KeyboardInjector
    private let uiState: GamepadUIState
    private var timer: Timer?
    private var lastTickTime: Date?
    private var lastController: ObjectIdentifier?
    private var buttonState = ButtonState()
    private var touchpadState = TouchpadScrollState()
    private var touchpad: GCControllerTouchpad?
    private let dualSenseInput = DualSenseInput()
    @Published private(set) var extraInputStatus = ""
    private var activeButtons: [String: ButtonAction] = [:]
    private var repeatDeadline: [String: Date] = [:]
    private var mergedPollFrameIndex = 0
    private var terminationObserver: NSObjectProtocol?

    var configurationURL: URL { configFile.url }
    var pointerSensitivity: Double {
        get { configuration.pointerSensitivity }
        set { var next = configuration; next.pointerSensitivity = newValue; saveConfiguration(next) }
    }
    var scrollSpeed: Double {
        get { configuration.scrollSpeed }
        set { var next = configuration; next.scrollSpeed = newValue; saveConfiguration(next) }
    }
    var deadzone: Double {
        get { configuration.deadzone }
        set { var next = configuration; next.deadzone = newValue; saveConfiguration(next) }
    }

    init(controllerService: ControllerService, mouse: MouseInjector, keyboard: KeyboardInjector, uiState: GamepadUIState) {
        self.controllerService = controllerService
        self.mouse = mouse
        self.keyboard = keyboard
        self.uiState = uiState
        reloadConfiguration()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.stopTimer() }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        stopTimer()
    }

    func reloadConfiguration() {
        do {
            let next = try configFile.load()
            releaseAllButtons()
            configuration = next
            configurationError = nil
        } catch {
            configurationError = "Could not load config: \(error.localizedDescription). Previous mapping kept."
        }
    }

    private func saveConfiguration(_ next: ControllerConfiguration) {
        do {
            try configFile.save(next)
            releaseAllButtons()
            configuration = next
            configurationError = nil
        } catch {
            configurationError = error.localizedDescription
        }
    }

    func updateAccessibilityTrustState() {
        if !AccessibilityGate.isTrusted {
            isEnabled = false
            stopTimer()
        }
    }

    func startStopTimerIfNeeded() {
        timer?.invalidate()
        timer = nil
        releaseAllButtons()
        lastTickTime = nil
        lastController = nil
        guard isEnabled, AccessibilityGate.isTrusted else {
            mergePollCoordinator?.inputEngineMainTimerStoppedFromMainRunLoop()
            return
        }
        mergePollCoordinator?.inputEngineMainTimerStartedFromMainRunLoop()
        let next = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        next.tolerance = 0.002
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        releaseAllButtons()
        lastTickTime = nil
        lastController = nil
        mergePollCoordinator?.inputEngineMainTimerStoppedFromMainRunLoop()
    }

    func onEnabledChanged() { startStopTimerIfNeeded() }

    private func tick() {
        guard isEnabled, AccessibilityGate.isTrusted else { return }
        mergedPollFrameIndex += 1
        let controller = controllerService.selectedController
        let pad = controller?.extendedGamepad
        mergePollCoordinator?.onInputEngineTimerTickFromMainRunLoop(frameIndex: mergedPollFrameIndex, extendedGamepad: pad)

        guard let controller, let pad else {
            releaseAllButtons()
            touchpad = nil
            lastController = nil
            lastTickTime = nil
            setLastTickSummary("No extended gamepad")
            return
        }
        let identity = ObjectIdentifier(controller)
        if identity != lastController {
            releaseAllButtons()
            lastTickTime = nil
            lastController = identity
            touchpad = controller.physicalInputProfile.touchpads.sorted { $0.key < $1.key }.first?.value
        }
        let now = Date()
        let dt = lastTickTime.map { min(max(now.timeIntervalSince($0), 1.0 / 240.0), 0.1) } ?? 1.0 / 60.0
        lastTickTime = now
        applyStick(pad.leftThumbstick, binding: configuration.leftStick, deltaTime: dt)
        applyStick(pad.rightThumbstick, binding: configuration.rightStick, deltaTime: dt)

        if uiState.onScreenKeyboardVisible {
            releaseAllButtons()
            setLastTickSummary("Virtual keyboard owns buttons")
            return
        }
        let edgeReport = dualSenseInput.snapshot(for: controller)
        let extraStatus = edgeReport == nil ? "" : "DualSense Edge paddles and touchpad connected"
        if extraInputStatus != extraStatus { extraInputStatus = extraStatus }
        if let edgeReport {
            let dy = touchpadState.update(y: edgeReport.y, touching: edgeReport.touching,
                                         configuration: configuration.touchpad)
            if dy != 0 { mouse.scrollPixels(deltaY: CGFloat(dy), deltaX: 0) }
        } else if let touchpad {
            let dy = touchpadState.update(y: Double(touchpad.touchSurface.yAxis.value),
                touching: touchpad.touchState != .up, configuration: configuration.touchpad)
            if dy != 0 { mouse.scrollPixels(deltaY: CGFloat(dy), deltaX: 0) }
        }
        let changes = buttonState.update(pressedButtons(pad).union(edgeReport?.buttons ?? []))
        for id in changes.released.sorted() { releaseButton(id) }
        for id in changes.pressed.sorted() {
            guard let action = configuration.buttons[id] else { continue }
            activeButtons[id] = action
            pressAction(action)
            if id.hasPrefix("dpad"), action.type == .key {
                repeatDeadline[id] = now.addingTimeInterval(0.35)
            }
        }
        for id in Array(repeatDeadline.keys) {
            if let deadline = repeatDeadline[id], now >= deadline, let action = activeButtons[id] {
                pressAction(action)
                repeatDeadline[id] = now.addingTimeInterval(0.08)
            }
        }
        let summary = activeButtons.keys.sorted().joined(separator: ", ")
        setLastTickSummary(summary.isEmpty ? "idle" : summary)
    }

    private func applyStick(_ stick: GCControllerDirectionPad, binding: StickBinding, deltaTime: TimeInterval) {
        let x = CGFloat(stick.xAxis.value) * (binding.invertX ? -1 : 1)
        let y = CGFloat(stick.yAxis.value) * (binding.invertY ? -1 : 1)
        switch binding.mode {
        case .disabled: break
        case .mouse:
            let (dx, dy) = DefaultMapping.pointerDelta(leftX: x, leftY: y, deadzone: CGFloat(deadzone),
                sensitivityPointsPerSecond: pointerSensitivity, deltaTime: deltaTime)
            if dx != 0 || dy != 0 { mouse.movePointer(deltaX: dx, deltaY: dy) }
        case .scroll:
            let (dx, dy) = DefaultMapping.scrollDelta(rightX: x, rightY: y, deadzone: CGFloat(deadzone),
                scrollSpeed: CGFloat(scrollSpeed) * CGFloat(deltaTime * 60))
            if dx != 0 || dy != 0 { mouse.scrollPixels(deltaY: dy, deltaX: dx) }
        }
    }

    private func pressedButtons(_ pad: GCExtendedGamepad) -> Set<String> {
        var values: [(String, Bool)] = [
            ("a", pad.buttonA.isPressed), ("b", pad.buttonB.isPressed),
            ("x", pad.buttonX.isPressed), ("y", pad.buttonY.isPressed),
            ("leftShoulder", pad.leftShoulder.isPressed), ("rightShoulder", pad.rightShoulder.isPressed),
            ("leftTrigger", pad.leftTrigger.isPressed), ("rightTrigger", pad.rightTrigger.isPressed),
            ("menu", pad.buttonMenu.isPressed), ("options", pad.buttonOptions?.isPressed == true),
            ("home", pad.buttonHome?.isPressed == true), ("rightStick", pad.rightThumbstickButton?.isPressed == true),
            ("leftStick", pad.leftThumbstickButton?.isPressed == true),
            ("dpadUp", pad.dpad.up.isPressed), ("dpadDown", pad.dpad.down.isPressed),
            ("dpadLeft", pad.dpad.left.isPressed), ("dpadRight", pad.dpad.right.isPressed),
            ("touchpad", touchpad?.button.isPressed == true)
        ]
        if #available(macOS 14.4, *) {
            values += [
                ("backLeft", pad.buttons[__GCInputBackLeftButton(0)?.rawValue ?? ""]?.isPressed == true),
                ("backRight", pad.buttons[__GCInputBackRightButton(0)?.rawValue ?? ""]?.isPressed == true),
                ("backLeft2", pad.buttons[__GCInputBackLeftButton(1)?.rawValue ?? ""]?.isPressed == true),
                ("backRight2", pad.buttons[__GCInputBackRightButton(1)?.rawValue ?? ""]?.isPressed == true)
            ]
        }
        return Set(values.filter { $0.1 }.map { $0.0 })
    }

    private func pressAction(_ action: ButtonAction) {
        switch action.type {
        case .mouse:
            guard let button = action.button else { return }
            let count = activeButtons.values.filter { $0.type == .mouse && $0.button == button }.count
            if count == 1 { postMouse(button, down: true) }
        case .key:
            if let shortcut = action.shortcut { keyboard.tapShortcut(shortcut) }
        case .dictation: keyboard.tapShortcut(configuration.dictation)
        case .none: break
        }
    }

    private func releaseButton(_ id: String) {
        repeatDeadline[id] = nil
        guard let action = activeButtons.removeValue(forKey: id), action.type == .mouse,
              let button = action.button else { return }
        if !activeButtons.values.contains(where: { $0.type == .mouse && $0.button == button }) {
            postMouse(button, down: false)
        }
    }

    private func postMouse(_ button: MouseBinding, down: Bool) {
        switch button {
        case .left: down ? mouse.leftMouseDown() : mouse.leftMouseUp()
        case .right: down ? mouse.rightMouseDown() : mouse.rightMouseUp()
        case .middle: down ? mouse.otherMouseDown() : mouse.otherMouseUp()
        }
    }

    private func releaseAllButtons() {
        for button in [MouseBinding.left, .right, .middle] {
            if activeButtons.values.contains(where: { $0.type == .mouse && $0.button == button }) {
                postMouse(button, down: false)
            }
        }
        activeButtons.removeAll()
        repeatDeadline.removeAll()
        buttonState.reset()
        touchpadState.reset()
    }

    private func setLastTickSummary(_ text: String) {
        if lastTickSummary != text { lastTickSummary = text }
    }
}
