import AppKit
import Combine
import SwiftUI

private struct ModeOverlayView: View {
    @ObservedObject var inputEngine: InputEngine

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(inputEngine.activeProfileName.capitalized)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(inputEngine.frontmostApplicationName.isEmpty ? "Desktop" : inputEngine.frontmostApplicationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 220, height: 54)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }
}

private final class ModeOverlayController: ObservableObject {
    private let inputEngine: InputEngine
    private let panel: NSPanel
    private var subscriptions = Set<AnyCancellable>()

    init(inputEngine: InputEngine) {
        self.inputEngine = inputEngine
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 54),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.contentView = NSHostingView(rootView: ModeOverlayView(inputEngine: inputEngine))
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isExcludedFromWindowsMenu = true

        inputEngine.$configuration
            .map(\.showModeOverlay)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in self?.setVisible(visible) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.positionPanel() }
            .store(in: &subscriptions)
    }

    func presentIfNeeded() {
        setVisible(inputEngine.configuration.showModeOverlay)
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            positionPanel()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 16,
                                     y: frame.maxY - panel.frame.height - 16))
    }
}

/// Ensures the app participates like a normal document-style app (Dock, ⌘Tab, Mission Control, Launchpad when installed in Applications).
private final class GamepadMouseAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            Self.configureMainWindows()
        }
    }

    private static func configureMainWindows() {
        for window in NSApp.windows {
            guard !(window is NSPanel) else { continue }
            var behavior = window.collectionBehavior
            behavior.remove(.stationary)
            behavior.insert(.managed)
            window.collectionBehavior = behavior
            window.isExcludedFromWindowsMenu = false
            if window.title.isEmpty {
                window.title = "Gamepad Mouse"
            }
        }
    }
}

/// Hooks the SwiftUI host window once it exists (may appear after `applicationDidFinishLaunching`).
private struct MainSwiftUIWindowHook: NSViewRepresentable {
    final class Coordinator {
        var didApply = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.didApply else { return }
        DispatchQueue.main.async {
            guard let window = nsView.window, !(window is NSPanel) else { return }
            context.coordinator.didApply = true
            NSApp.setActivationPolicy(.regular)
            var behavior = window.collectionBehavior
            behavior.remove(.stationary)
            behavior.insert(.managed)
            window.collectionBehavior = behavior
            window.isExcludedFromWindowsMenu = false
            window.title = "Gamepad Mouse"
        }
    }
}

@main
struct GamepadMouseApp: App {
    @NSApplicationDelegateAdaptor(GamepadMouseAppDelegate.self) private var appDelegate
    @StateObject private var controllerService: ControllerService
    @StateObject private var gamepadUIState: GamepadUIState
    @StateObject private var keyboardManager: GlobalKeyboardManager
    @StateObject private var inputEngine: InputEngine
    @StateObject private var modeOverlayController: ModeOverlayController

    init() {
        let cs = ControllerService()
        let ui = GamepadUIState()
        let mouse = MouseInjector()
        let keys = KeyboardInjector()
        let km = GlobalKeyboardManager(controllerService: cs, gamepadUIState: ui, keyboardInjector: keys)
        let ie = InputEngine(controllerService: cs, mouse: mouse, keyboard: keys, uiState: ui)
        km.attachMergedPolling(for: ie)
        _controllerService = StateObject(wrappedValue: cs)
        _gamepadUIState = StateObject(wrappedValue: ui)
        _keyboardManager = StateObject(wrappedValue: km)
        _inputEngine = StateObject(wrappedValue: ie)
        _modeOverlayController = StateObject(wrappedValue: ModeOverlayController(inputEngine: ie))
        ie.startStopTimerIfNeeded()
        SyntheticInputActivity.setActive(ie.isEnabled && AccessibilityGate.isTrusted)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controllerService)
                .environmentObject(inputEngine)
                .environmentObject(gamepadUIState)
                .environmentObject(keyboardManager)
                .background(MainSwiftUIWindowHook())
                .onAppear { modeOverlayController.presentIfNeeded() }
        }
        .commands {
            CommandMenu("Controller") {
                Button("Open Config") { NSWorkspace.shared.open(inputEngine.configurationURL) }
                Button("Reload Config") { inputEngine.reloadConfiguration() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Toggle("Enable Controller", isOn: $inputEngine.isEnabled)
                    .disabled(!AccessibilityGate.isTrusted)
                Toggle("Show Mode Overlay", isOn: $inputEngine.showModeOverlay)
                Divider()
                Button("Mode: \(inputEngine.activeProfileName.capitalized)") {}
                    .disabled(true)
            }
        }
    }
}
