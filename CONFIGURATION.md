# JSON controller configuration

Gamepad Mouse creates `~/.config/gamepad-mouse/config.json` on first launch.
Use **Open Config** in the Controls section, save your edits, then choose
**Reload Config** or press **Cmd+R** while the app is focused. No rebuild is
needed for mappings. [config.example.json](config.example.json) is the desktop
layout shipped by this fork.
The same controls live in the **Controller** menu, and closing the settings
window keeps controller mapping running. Quitting the app releases held inputs.

The controller starts disabled. Enable it in the app after granting Accessibility
permission. Quit Controlly or disable its mappings before enabling this app so
one press produces one action. Use Show keyboard / Hide keyboard in the app for
the floating keyboard. Automatic opening on text focus starts off so it does not
interrupt desktop shortcuts or dictation. L3 sends Dictation instead.

## Default desktop layout

| Controller input | Action |
| --- | --- |
| Left stick | Pointer |
| Right stick | Horizontal and vertical scroll |
| Cross / A | Left click; hold to drag |
| Circle / B | Escape |
| Square / X | Right click |
| Triangle / Y | Enter |
| D-pad | Arrow keys; hold to repeat |
| L1 / R1 | Cmd+[ / Cmd+] (back / forward where supported) |
| L2 | Toggle Dictation shortcut |
| R2 | Cmd+Tab (switch between recent apps) |
| Options / Menu | Cmd+Space (Spotlight) |
| Create / View | Ctrl+Up (Mission Control with macOS default shortcut) |
| L3 | Toggle Dictation shortcut |
| R3 | Middle click |
| Left / right back paddle | Cmd+C / Cmd+V (copy / paste) |
| Touchpad swipe up / down | Vertical scrolling |

Inputs use Apple's extended gamepad names, not a vendor/product ID. On a
PlayStation controller `a`, `b`, `x`, `y` mean Cross, Circle, Square, Triangle.
`menu` is Options and `options` is Create. Button availability depends on the
controller and macOS; the Home/PS button may be intercepted by macOS. Generic
back buttons require macOS 14.4+ and must be exposed by the controller's profile.
The DualSense Edge uses a nonexclusive, controller-only HID reader for paddles
and touch contacts omitted by Apple's GameController profile. USB and full
Bluetooth reports are supported. With multiple Edge controllers connected,
this fallback is disabled to avoid mixing devices. Other controllers that mirror
paddles onto face buttons cannot supply separate bindings through this API.

The touchpad scrolls while a finger moves, with no scroll on first contact or
finger lift. `touchpad` accepts `enabled` (default true), `scrollSensitivity`
(50–3000 pixels per normalized unit, default 600), and `invertY` (default false).
For example: `"touchpad": {"enabled": true, "scrollSensitivity": 600, "invertY": false}`.

## Sticks and tuning

Set either stick's `mode` to `mouse`, `scroll`, or `disabled`. `invertX` and
`invertY` are optional booleans, both false by default. Swap the two modes to
swap the sticks. Tuning is shared by both sticks:

- `pointerSensitivity`: 200–4000 points per second, default 1200.
- `scrollSpeed`: 5–120, default 35 (the original app's scale at 60 Hz).
- `deadzone`: 0–0.95, default 0.12. Input inside this radius produces no motion.

Sliders save these three values to the same JSON file. If you have edited it
externally, sliders refuse to overwrite those edits until you reload.

## Buttons and shortcuts

`buttons` is a dictionary of input names to actions. Omitting `buttons` entirely
uses the default desktop bindings; supplying it replaces the whole dictionary.
An empty `{}` disables all configurable buttons. An omitted button or an action
of `{"type":"none"}` does nothing.

The supported names are `a`, `b`, `x`, `y`, `leftShoulder`, `rightShoulder`,
`leftTrigger`, `rightTrigger`, `menu`, `options`, `home`, `leftStick` (L3), `rightStick`, `dpadUp`,
`dpadDown`, `dpadLeft`, `dpadRight`, `backLeft`, `backRight`, `backLeft2`,
`backRight2`, and `touchpad` (physical click). The `2` paddle names address the
second paddle on that side, when present. Existing explicit `buttons` maps need
the new paddle/L3 entries added; reloading does not merge defaults into your map.

```json
{
  "type": "key",
  "key": "c",
  "modifiers": ["command", "shift"]
}
```

This sends one Cmd+Shift+C tap when pressed. Supported modifiers are `command`,
`option`, `control`, and `shift`. Keys include letters, digits, US punctuation,
`enter`/`return`, `escape`, `space`, `tab`, `backspace`, `delete` (forward delete),
`left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`, and `f1`–`f20`.
Key names refer to physical US keyboard positions. Modifier-only holds, macros,
layers, hold-to-talk, and per-app profiles are not implemented.

Use `{"type":"mouse","button":"left"}` for a held left click (`right` and
`middle` also work), or `{"type":"dictation"}` for the dictation shortcut below.
Several inputs can share one mouse button without releasing each other's hold.

## macOS Dictation

The default `dictation` object is `{"key":"d","modifiers":["control","option"]}`.
In **System Settings → Keyboard → Dictation**, enable Dictation and customize
its shortcut to **Ctrl+Option+D**. Alternatively, set the JSON to the shortcut
already configured on your Mac. Press L2 to start dictating into the focused
text field, then press it again to stop. This app sends a shortcut; macOS does
the speech recognition. L3 also toggles the same shortcut. It does not read the controller microphone or upload
audio itself. Dictation setup and speech behavior must be checked on your Mac.

## Reloading and extending

Invalid JSON, unsupported versions, unknown input/action/key names, or invalid
numeric values display an error and keep the last successfully loaded mapping.
The file is never replaced with defaults on a decode error. Reloading, disabling,
switching controllers, and disconnecting release held mouse buttons. A button
held during enable/reconnect/reload must be released and pressed again to fire.

Add input names in `ControllerConfiguration.buttonNames` and
`InputEngine.pressedButtons`. Add new action types in `ActionType`, validation,
and `InputEngine.pressAction`/`releaseButton`. Keep file I/O out of `tick()`.

Run `sh scripts/check.sh` for configuration, persistence and button-state checks.
Run `sh scripts/build.sh` for a native `.app` build using macOS Command Line
Tools without installing Xcode or dependencies. The Xcode project also includes
the new sources. Existing upstream builds under `dist/` do **not** include this
fork's JSON support: use the app you build in `build/`.
