#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 GamepadMouse/ControllerConfiguration.swift \
    GamepadMouse/ButtonState.swift GamepadMouse/KeyboardInjector.swift \
    tests/ConfigurationChecks.swift -o build/config-checks
build/config-checks "$@"
